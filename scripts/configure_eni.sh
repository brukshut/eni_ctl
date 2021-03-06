#!/bin/bash 

##
## configure_eni.sh
##
PATH=/bin:/sbin:/usr/bin:/usr/sbin

## functions
function die { echo "$*" 1>&2 && exit 1; }

function add_script {
  local script=$1
  [ -e /tmp/${script} ] && 
    ( sudo mv /tmp/${script} /usr/local/sbin/${script}
      sudo chown root:root /usr/local/sbin/${script}
      sudo chmod 755 /usr/local/sbin/${script} ) ||
      die "file not found: /tmp/${script}"
}

function add_file {
  local file=$1
  local directory=$2
  [[ -d ${directory} ]] || die "${directory} does not exist."
  [[ -e /tmp/${file} ]] && 
    ( sudo mv /tmp/${file} ${directory}
      sudo chmod 644 ${directory}/${file}
      sudo chown root:root ${directory}/${file} ) ||
      die "no such file: /tmp/${file}"
}

function add_service {
  local service=$1
  [[ -e /tmp/${service} ]] &&
    ( sudo mv /tmp/${service} /lib/systemd/system/${service} &&
      sudo chown root:root /lib/systemd/system/${service} ) ||
      die "no such file: /tmp/${service}"
}
    
function reload_service {
  local service=$1
  sudo systemctl daemon-reload && sudo systemctl enable ${service} ||
    die
}
## end functions

## main
add_script eni_ctl.sh 
add_service eni.service 
reload_service eni.service
## end main
