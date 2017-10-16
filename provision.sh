
export CONFIG_DIR=blockr_config
export DEBUG=false
export SETUP_DRIVER_NAME=prepare_node_driver.sh
export FABRIC_CFG_PATH=./$CONFIG_DIR
export FABRIC_PATH=$GOPATH/src/github.com/hyperledger/fabric
export PRODUCTION_DIR=/var/hyperledger
export TARGET_CFG_PATH=$FABRIC_PATH/$CONFIG_DIR
export TEMP_CFG_PATH=./$CONFIG_DIR.temp
export WAIT_SECONDS=1
export WITH_TLS=true

distribute_conf() {
  echo "----------"
  echo " Distribute configuration to Node $1"
  echo "----------"
  if [ -d $TEMP_CFG_PATH ]; then
    rm -rf $TEMP_CFG_PATH
  fi
  mkdir -p $TEMP_CFG_PATH
  cp -r $FABRIC_CFG_PATH/* $TEMP_CFG_PATH 
  cp ./templates/core.yaml $TEMP_CFG_PATH/core.yml.template 
  cp ./templates/orderer.yaml $TEMP_CFG_PATH/orderer.yml.template 

  CORE_PEER_MSP_PATH=''
  CORE_PEER_TLS_CERT_FILE=''
  CORE_PEER_TLS_KEY_FILE=''
  CORE_PEER_TLS_ROOTCERT_FILE=''
  ORDERER_GENERAL_TLS_CERTIFICATE=''
  ORDERER_GENERAL_TLS_PRIVATEKEY=''
  ORDERER_GENERAL_TLS_ROOTCAS=''
  CORE_PEER_MSP_PATH="peerOrganizations/$3/peers/$1.$3/msp"
  ORDERER_MSP_PATH="ordererOrganizations/$3/orderers/$1.$3/msp"
  if [ "$WITH_TLS" = true ]; then
    CORE_PEER_TLS_CERT_FILE="peerOrganizations/$3/peers/$1.$3/tls/server.crt"
    CORE_PEER_TLS_KEY_FILE="peerOrganizations/$3/peers/$1.$3/tls/server.key"
    CORE_PEER_TLS_ROOTCERT_FILE="peerOrganizations/$3/peers/$1.$3/tls/ca.crt"
    ORDERER_GENERAL_TLS_CERTIFICATE="ordererOrganizations/$3/orderers/$1.$3/tls/server.crt"
    ORDERER_GENERAL_TLS_PRIVATEKEY="ordererOrganizations/$3/orderers/$1.$3/tls/server.key"
    ORDERER_GENERAL_TLS_ROOTCAS="ordererOrganizations/$3/orderers/$1.$3/tls/ca.crt"
  fi

  cat $TEMP_CFG_PATH/core.yml.template | sed "s|PEER_ID|$2| ; s|PEER_ENDPOINT|$1| ; s|PEER_ADDRESS|$1:7051| ; s|PEER_BOOTSTRAP|$1:7051| ; s|WITH_TLS|$WITH_TLS| ; s|PEER_CERT|$CORE_PEER_TLS_CERT_FILE| ; s|PEER_KEY|$CORE_PEER_TLS_KEY_FILE| ; s|PEER_ROOTCERT|$CORE_PEER_TLS_ROOTCERT_FILE| ; s|PEER_MSP_PATH|$CORE_PEER_MSP_PATH| ; s|PEER_MSP_ID|$2| " > $TEMP_CFG_PATH/core.yaml
  rm $TEMP_CFG_PATH/core.yml.template

  cat $TEMP_CFG_PATH/orderer.yml.template | sed "s:WITH_TLS:$WITH_TLS: ; s:ORDERER_CERT:$ORDERER_GENERAL_TLS_CERTIFICATE: ; s:ORDERER_KEY:$ORDERER_GENERAL_TLS_PRIVATEKEY: ; s:ORDERER_ROOTCERT:$ORDERER_GENERAL_TLS_ROOTCAS: ; s:ORDERER_MSP_PATH:$ORDERER_MSP_PATH: ; s:ORDERER_MSP_ID:$4:   " > $TEMP_CFG_PATH/orderer.yaml
  rm $TEMP_CFG_PATH/orderer.yml.template

  ssh $1 "rm -rf $TARGET_CFG_PATH"
  ssh $1 "mkdir -p $TARGET_CFG_PATH"
  scp -rq $TEMP_CFG_PATH/* $1:$TARGET_CFG_PATH
  rm -rf $TEMP_CFG_PATH
}

prepare() {
  echo "----------"
  echo " Preparing Node $1"
  echo "----------"

#
# create the driver script
#
  echo '#!/bin/bash' > $SETUP_DRIVER_NAME
  echo '' >> $SETUP_DRIVER_NAME
  echo '#----------------' >> $SETUP_DRIVER_NAME
  echo '#' >> $SETUP_DRIVER_NAME
  echo '# Block R Setup Driver' >> $SETUP_DRIVER_NAME
  echo '#' >> $SETUP_DRIVER_NAME
  echo '#----------------' >> $SETUP_DRIVER_NAME
  echo -n 'export TARGET_CFG_PATH=' >> $SETUP_DRIVER_NAME 
  echo $TARGET_CFG_PATH >> $SETUP_DRIVER_NAME 
  echo -n 'export PRODUCTION_DIR=' >> $SETUP_DRIVER_NAME 
  echo $PRODUCTION_DIR >> $SETUP_DRIVER_NAME 
  echo 'echo " - Stop running daemons"' >> $SETUP_DRIVER_NAME
  echo 'sudo pkill orderer' >> $SETUP_DRIVER_NAME
  echo 'sudo pkill peer' >> $SETUP_DRIVER_NAME
  echo 'echo " - Remove docker images"' >> $SETUP_DRIVER_NAME
  echo 'sudo docker ps -aq | xargs docker kill &> /dev/null' >> $SETUP_DRIVER_NAME
  echo 'sudo docker ps -aq | xargs docker rm &> /dev/null' >> $SETUP_DRIVER_NAME
  echo "sudo docker images | grep 'dev-' | awk '{print $3}' | xargs docker rmi &> /dev/null" >> $SETUP_DRIVER_NAME
  echo -n 'echo " - Reset configuration ' >> $SETUP_DRIVER_NAME
  echo -n $TARGET_CFG_PATH >> $SETUP_DRIVER_NAME
  echo '"' >> $SETUP_DRIVER_NAME
  echo -n 'rm -rf ' >> $SETUP_DRIVER_NAME
  echo $TARGET_CFG_PATH >> $SETUP_DRIVER_NAME
  echo -n 'mkdir ' >> $SETUP_DRIVER_NAME
  echo $TARGET_CFG_PATH >> $SETUP_DRIVER_NAME
  echo 'echo " - Stop daemons"' >> $SETUP_DRIVER_NAME
  echo 'sudo /etc/init.d/couchdb stop &> /dev/null' >> $SETUP_DRIVER_NAME
  echo 'sudo systemctl stop kafka' >> $SETUP_DRIVER_NAME
  if [ "$1" = "vm1" ]; then
    echo 'sudo systemctl stop zookeeper' >> $SETUP_DRIVER_NAME
  fi
  echo 'echo " - Reset production repositories"' >> $SETUP_DRIVER_NAME
  echo 'if [ -d $PRODUCTION_DIR ]; then' >> $SETUP_DRIVER_NAME
  echo '  sudo rm -rf $PRODUCTION_DIR' >> $SETUP_DRIVER_NAME
  echo 'fi' >> $SETUP_DRIVER_NAME
  echo 'sudo mkdir $PRODUCTION_DIR' >> $SETUP_DRIVER_NAME
  echo 'sudo chown $(whoami):$(whoami) $PRODUCTION_DIR' >> $SETUP_DRIVER_NAME
  echo 'if [ -d tmp.zookeeper ]; then' >> $SETUP_DRIVER_NAME
  echo '  sudo -rm -rf /tmp/zookeeper' >> $SETUP_DRIVER_NAME
  echo 'fi' >> $SETUP_DRIVER_NAME
  echo 'if [ -d tmp.kafka-logs ]; then' >> $SETUP_DRIVER_NAME
  echo '  sudo -rm -rf /tmp/kafka-logs' >> $SETUP_DRIVER_NAME
  echo 'fi' >> $SETUP_DRIVER_NAME
  echo 'echo " - Start daemons"' >> $SETUP_DRIVER_NAME
  if [ "$1" = "vm1" ]; then
    echo 'sudo systemctl start zookeeper' >> $SETUP_DRIVER_NAME
  fi
  echo 'sudo systemctl start kafka' >> $SETUP_DRIVER_NAME
  echo 'sudo /etc/init.d/couchdb start &> /dev/null' >> $SETUP_DRIVER_NAME

  scp -q ./$SETUP_DRIVER_NAME $1: 
  ssh $1 "chmod 777 $SETUP_DRIVER_NAME"
  ssh $1 "./$SETUP_DRIVER_NAME"
  if [ "$DEBUG" != true ]; then
    ssh $1 "rm ./$SETUP_DRIVER_NAME"
  fi
  rm ./$SETUP_DRIVER_NAME
}

echo ".----------------"
echo "|"
echo "| Block R Provisoner"
echo "|"
echo "'----------------"

prepare vm1
prepare vm2

echo "----------"
echo " Reset local configuration directory $FABRIC_CFG_PATH"
echo "----------"
rm -rf $FABRIC_CFG_PATH 
mkdir -p $FABRIC_CFG_PATH 

echo "----------"
echo " Generate keys from $FABRIC_CFG_PATH/blockr-config.yaml"
echo "----------"
cp ./templates/blockr-config.yaml $FABRIC_CFG_PATH
$FABRIC_PATH/build/bin/cryptogen generate --config $FABRIC_CFG_PATH/blockr-config.yaml --output $FABRIC_CFG_PATH 

echo "----------"
echo " Generate genesis block from $FABRIC_CFG_PATH/configtx.yaml, profile:Genesis"
echo "----------"
cp ./templates/configtx.yaml $FABRIC_CFG_PATH
$FABRIC_PATH/build/bin/configtxgen -profile Genesis -outputBlock $FABRIC_CFG_PATH/genesis.block -channelID system
if ! [ -f $FABRIC_CFG_PATH/genesis.block ]; then
  echo 'ERROR'
  exit 1
fi

echo "----------"
echo " Generate channel block from $FABRIC_CFG_PATH/configtx.yaml, profile:Channels"
echo "----------"
$FABRIC_PATH/build/bin/configtxgen -profile Channels -outputCreateChannelTx $FABRIC_CFG_PATH/blockr.tx -channelID blockr
if ! [ -f $FABRIC_CFG_PATH/blockr.tx ]; then
  echo 'ERROR'
  exit 1
fi

echo "----------"
echo " Generate Anchorpeer transactions from $FABRIC_CFG_PATH/configtx.yaml, profile:Channels"
echo "----------"
$FABRIC_PATH/build/bin/configtxgen -profile Channels -outputAnchorPeersUpdate $FABRIC_CFG_PATH/Org1MSPanchors.tx -channelID blockr -asOrg Org1MSP
if ! [ -f $FABRIC_CFG_PATH/Org1MSPanchors.tx ]; then
  echo 'ERROR'
  exit 1
fi

$FABRIC_PATH/build/bin/configtxgen -profile Channels -outputAnchorPeersUpdate $FABRIC_CFG_PATH/Org2MSPanchors.tx -channelID blockr -asOrg Org2MSP
if ! [ -f $FABRIC_CFG_PATH/Org2MSPanchors.tx ]; then
  echo 'ERROR'
  exit 1
fi

distribute_conf vm1 Org1MSP nar.blockr Orderer1MSP 0
distribute_conf vm2 Org2MSP car.blockr Orderer2MSP 1

rm -rf $FABRIC_CFG_PATH 

