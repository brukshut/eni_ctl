#!/bin/bash -x

##
## eni_ctl bootstrap.sh
##

## functions
function fetch_eni_ctl {
  cleanup
  git clone https://github.com/brukshut/eni_ctl /tmp/eni_ctl
}

function cleanup {
  [[ -d /tmp/eni_ctl ]] && sudo rm -rf /tmp/eni_ctl
}

function copy_files {
  for file in /lib/systemd/system/eni.service /etc/network/interfaces /etc/dhcp/dhclient.conf; do
    filename=$(basename $file)
    [[ -e /tmp/${filename} ]] && sudo cp /tmp/${filename} $file ||
      ( [[ -e /tmp/eni_ctl/files/${filename} ]] && sudo cp /tmp/eni_ctl/files/${filename} $file )
    sudo chown root:root $file
    sudo chmod 0644 $file
    [[ $(basename $file) == 'eni.service' ]] &&
      sudo systemctl daemon-reload && sudo systemctl enable eni.service
  done

  for script in eni_ctl.sh add_routes.sh configure_eni.sh configure_interfaces.sh; do 
    [[ -e /tmp/eni_ctl/scripts/${script} ]] && 
      sudo cp /tmp/eni_ctl/scripts/${script} /usr/local/sbin/${script}
      sudo chown root:root /usr/local/sbin/${script}
      sudo chmod 755 /usr/local/sbin/${script}
  done
}

function configure_eni {
  fetch_eni_ctl
  copy_files
  cleanup
}

## end functions

## main

configure_eni

## end main
