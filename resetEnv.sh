#!/bin/bash

CONFIG_DIR="blockr_config"
FABRIC=$GOPATH/src/github.com/hyperledger/fabric
PRODUCTION_DIR=/var/hyperledger

#
# stop running binaries
#
pkill orderer 
pkill peer

#
# stop couchdb and remove production artifacts
#
sudo su - $(whoami) - << EOF
  sudo /etc/init.d/couchdb stop
  if [ -d $PRODUCTION_DIR ]; then
    sudo rm -rf $PRODUCTION_DIR
  fi
  echo "Creating Production directory $PRODUCTION_DIR"
  sudo mkdir -p $PRODUCTION_DIR 
  sudo chown $(whoami):$(whoami) $PRODUCTION_DIR 
  mkdir -p $FABRIC/$CONFIG_DIR
  sudo /etc/init.d/couchdb start
EOF

