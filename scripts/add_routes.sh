#!/bin/bash

##
## add_routes.sh
##
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

## functions
function die { exit 1; }

function create_route_table {
  local table=$1
  local number=$2
  local route_conf=/etc/iproute2/rt_tables.d/${table}.conf
  [ -e "${route_conf}" ] ||
    echo "${number} ${table}" | dd of=${route_conf} conv=notrunc status=none
}

function add_rule {
  local device=$1
  local ip=$2
  local table=$3
  local priority="$(expr 100 - ${device##${device%[0-9]}})"
  ## add rule for interface
  #[[ -z "$(ip rule list from $ip)" ]] &&
  #  ip rule add from $ip lookup $table priority $priority || true
  [[ -z "$(ip rule list from ${ip})" ]] && 
    ip rule add from ${ip} lookup ${table} priority ${priority}
}

function add_subnet_route {
  local device=$1
  local ip=$2
  local network=$3
  local table=$4
  ## add route for subnet
  ##[[ -z "$(ip route list $network dev $device src $ip table $table)" ]] &&
  ##  ip route add $network dev $device src $ip table $table || true
  ## add route for subnet
  [[ -z "$(ip route list ${network} dev ${device} src ${ip} table ${table})" ]] &&
    ip route add ${network} dev ${device} src ${ip} table ${table}

}

function add_default_route {
  local device=$1
  local gateway=$2
  local table=$3
  ## add default route for interface
  [[ -z "$(ip route list default via ${gateway} dev ${device} table ${table})" ]] &&
    ip route add default via ${gateway} dev ${device} table ${table}
}

function set_default_route {
  local device=$1
  local gateway=$2
  ip route replace default via $gateway dev $device 
}

function add_routes {
  local device=$1
  local ip=$2
  local gateway=$3
  local network=$4
  local table=$5
  add_rule $device $ip $table
  add_subnet_route $device $ip $network $table
  add_default_route $device $gateway $table
  set_default_route $device $gateway
}

function get_ip {
  local device=$1
  echo $(ip -4 -o addr show ${device} | awk '{print $4}' | sed 's/\/[0-9]*//')
}

function usage {
  echo "${0} -d [device] -g [gateway] -n [network] -t [table]" && exit
}
## end functions

## main
## create route table and add routes
## assumes interface is attached and plumbed
while getopts "d:g:n:t:" opt; do
  case $opt in
    d) device=${OPTARG} ;;
    g) gateway=${OPTARG} ;;
    n) network=${OPTARG} ;;
    t) table=${OPTARG} ;;
    *) usage ;;
  esac
done

## only require device
[[ -z $device ]] && usage
ip link show ${device} > /dev/null && ip=$(get_ip $device) || die
[[ -z $network ]] && network=${ip%.*}.0/24
[[ -z $gateway ]] && gateway=${ip%.*}.1
[[ -z $table ]] && table=${device}
## table number is 100 for eth0, 101 for eth1, etc.
create_route_table $table "10${device##${device%[0-9]}}"
add_routes $device $ip $gateway $network $table

## end main
