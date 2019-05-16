#!/bin/bash

##
## eni_ctl.sh
## attach, detach aws elastic network interface
##
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export AWS_DEFAULT_REGION="us-west-1"

## FUNCTIONS
function die { echo "$*" 1>&2 && exit 1; }

function attach_eni {
  if [ -z $ATTACHMENT_ID ] || [ $ATTACHMENT_ID == 'null' ]; then
    local cmd="aws ec2 attach-network-interface --network-interface-id ${ENI_ID} --instance-id ${INSTANCE_ID} --device-index 1"
    local output=$(eval "$cmd")
    if [ $? == 0 ]; then
       ## wait for device to appear
      while [[ ! $(ip link show ${DEVICE} up 2>/dev/null) ]]; do sleep 1; done
      echo "successfully attached ${ENI_ID}: ${output//$'\n'}"
    else
      echo "failed to attach ${ENI_ID}: ${output//$'\n'}"
    fi
  else
    ## we have to wait until device has ipaddress before proceeding
    while [[ ! $(ip link show ${DEVICE} up 2>/dev/null) ]]; do sleep 1; done
    echo "${ENI_ID} is already attached: ${ATTACHMENT_ID}"
  fi
}

function detach_eni {
  if [ -z $ATTACHMENT_ID ] || [ $ATTACHMENT_ID == 'null' ]; then
    echo "${ENI_ID} is not attached."
  else
    local cmd="aws ec2 detach-network-interface --attachment-id=${ATTACHMENT_ID}"
    local output=$(eval "$cmd")
    ## trim leading whitespace from aws cli response
    if [ $? == 0 ]; then
      ## wait until device disappears
      while [[ $(ip link show ${DEVICE} 2>/dev/null) ]]; do sleep 1; done
      echo "detached ${ENI_ID}:  ${output//$'\n'}"
    else
      die "$failed to detach ${ENI_ID}: ${output//$'\n'}"
    fi
  fi
}

function fetch_eni_data {
  ## the name of the elastic network interface matches the autoscaling group name
  local asg_name=$1
  local json='/tmp/.eni.json'
  local filter="--filter Name=tag:Name,Values=${asg_name}"
  local cmd="/usr/bin/aws ec2 describe-network-interfaces ${filter} > ${json}"
  local output=$(eval "$cmd")
  [ $? == 0 ] && echo $json || die "failed to fetch eni data: ${output//$'\n'}"
}

function get_fqdn {
  local json=$1
  cat $json | jq -r '.NetworkInterfaces[].TagSet[] | select(.Key=="FQDN") | .Value'
}

function get_gateway {
  local ip=$1
  ## split octets on replace fourth
  IFS=. read -r first second third fourth <<< "${ip}"
  echo ${first}.${second}.${third}.1
}

function get_asg_name {
  local json=$(aws autoscaling describe-auto-scaling-instances --instance-id=${1})
  ## if instance is part of an asg, it returns an array with a single element
  local length=$(echo ${json} | jq '.[] | length')
  [[ $length ]] && echo $json | jq -r .AutoScalingInstances[].AutoScalingGroupName
}

function get_attachment_id {
  local json=$1
  [ -e $json ] && jq -r ".NetworkInterfaces[] | .Attachment.AttachmentId" $json ||
    die "${FUNCNAME[0]}: ${json} not found"
}

function get_eni_id {
  local json=$1
  [ -e $json ] && jq -r ".NetworkInterfaces[] | .NetworkInterfaceId" $json ||
    die "${FUNCNAME[0]}: ${json} not found"
}

function get_instance_id {
  curl -s http://169.254.169.254/latest/meta-data/instance-id ||
    die "${FUNCNAME[0]}: can't fetch instance-id"
}

function get_private_ip {
  local json=$1
  [ -e $json ] && jq -r ".NetworkInterfaces[] | .PrivateIpAddress" $json ||
    die "${FUNCNAME[0]}: ${json} not found"
}

function check_nat {
  ## NAT=true key set on nat_instance autoscaling group
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names=$(get_asg_name $INSTANCE_ID) \
    | jq -r '.AutoScalingGroups[].Tags[] | select(.Key=="NAT") | .Value'
}

function eni_defaults {
  ## fetch instance_id
  local instance_id=$(get_instance_id)
  local asg_name=$(get_asg_name ${instance_id})
  ## eni is tagged with same name as autoscaling group
  local json=$(fetch_eni_data $asg_name)
  local ip=$(get_private_ip $json)
  local fqdn=$(get_fqdn $json)
  local attachment_id=$(get_attachment_id $json)
  local eni_id=$(get_eni_id $json)
  ## determine default gateway and device for routes
  local default_route=$(ip route show default 0.0.0.0/0)
  local gw=$(get_gateway $ip)
  local device=eth1
  ## overwrite existing defaults file
  local defaults=/etc/default/eni
  echo "FQDN=$fqdn" | dd of=${defaults} status=none
  for env in ip gw device asg_name instance_id eni_id attachment_id; do
    echo "${env^^}=${!env}" | dd of=${defaults} oflag=append conv=notrunc status=none
  done
  [[ -e $defaults ]] && source $defaults ||
      die "${FUNCNAME[0]}: can't source $defaults"
}

function usage { printf "%s\n" "Usage: $0 [-a] [-d]" ; exit 1; }
## end functions

## main
while getopts ":ad" opt; do
  case $opt in
    a) ATTACH=true
       eni_defaults && attach_eni
      ;;
    d) DETACH=true
       eni_defaults && detach_eni
      ;;
    *) usage
      ;;
  esac
done

## print usage
[[ $ATTACH || $DETACH ]] || usage
