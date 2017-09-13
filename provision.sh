#!/bin/bash -e

echo ".----------"
echo "|"
echo "|  Block R Network Provisoner"
echo "|  Association Engagement Tracker"
echo "|"
echo "'----------"

CONFIG_DIR=blockr_config
DEBUG=true
FABRIC=$GOPATH/src/github.com/hyperledger/fabric
GOPATH=/work/projects/go
SYNC_WAIT=5
WITH_TLS=true

getIP() {
  ssh $1 "/usr/sbin/ip addr | grep 'inet .*global' | cut -f 6 -d ' ' | cut -f1 -d '/' | head -n 1"
}

probePeerOrOrderer() {
  echo "" | nc $1 7050 && return 0
  echo "" | nc $1 7051 && return 0
  return 1
}

probeFabric() {
  ssh $1 "ls $FABRIC &> /dev/null || echo 'not found'" | grep -q "not found"
  if [ $? -eq 0 ];then
    echo "1"
    return
  fi
  echo "0"
}

deployFabric() {
  scp install.sh $1:install.sh
  ssh $1 "bash install.sh"
}

query() {
  NODE_ROOT_TLS=""
  ORDERER_TLS=""
  if [ "$WITH_TLS" = true ]; then
    NODE_ROOT_TLS="CORE_PEER_TLS_ROOTCERT_FILE=$FABRIC/$CONFIG_DIR/peerOrganizations/blockr/peers/$1.blockr/tls/ca.crt"
    ORDERER_TLS="--tls true --cafile $FABRIC/$CONFIG_DIR/ordererOrganizations/blockr/orderers/$1.blockr/tls/ca.crt"
  fi
  ssh_args='{"Args":["query","a"]}'
  SSH_CMD="$NODE_ROOT_TLS FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR CORE_PEER_MSPCONFIGPATH=$NODE_ADMIN_MSP CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_ADDRESS=$1:7051 $FABRIC/build/bin/peer chaincode query -n exampleCC -v 1.0 -C blockr -c '$ssh_args' $ORDERER_TLS"
  if [ "$DEBUG" = true ]; then
    echo $SSH_CMD
  fi
  ssh $1 $SSH_CMD
}

invoke() {
  NODE_ROOT_TLS=""
  ORDERER_TLS=""
  if [ "$WITH_TLS" = true ]; then
    NODE_ROOT_TLS="CORE_PEER_TLS_ROOTCERT_FILE=$FABRIC/$CONFIG_DIR/peerOrganizations/blockr/peers/$1.blockr/tls/ca.crt"
    ORDERER_TLS="--tls true --cafile $FABRIC/$CONFIG_DIR/ordererOrganizations/blockr/orderers/$1.blockr/tls/ca.crt"
  fi
  ssh_args='{"Args":["invoke","a","b","10"]}'
  SSH_CMD="$NODE_ROOT_TLS FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR CORE_PEER_MSPCONFIGPATH=$NODE_ADMIN_MSP CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_ADDRESS=$1:7051 $FABRIC/build/bin/peer chaincode invoke -n exampleCC -v 1.0 -C blockr -c '$ssh_args' -o $1:7050 $ORDERER_TLS"
  if [ "$DEBUG" = true ]; then
    echo $SSH_CMD
  fi
  ssh $1 $SSH_CMD
}

[[ -z $GOPATH ]] && (echo "Environment variable GOPATH isn't set!"; exit 1)
[[ -d "$FABRIC" ]] || (echo "Directory $FABRIC doesn't exist!"; exit 1)

#
# read config and set variables
#
echo ".----------"
echo "|  Read config.sh to determine which servers to provision"
echo "'----------"
. config.sh
bootPeer=$(echo ${nodes} | awk '{print $1}')
NODE_ADMIN_MSP=$FABRIC/$CONFIG_DIR/peerOrganizations/blockr/users/Admin@blockr/msp/

#
# make sure fabric is installed on all servers
#
echo ".----------"
echo "|  Ensure Hyperledger Fabric is installed on each node"
echo "'----------"
for p in $nodes; do
  if [ `probeFabric $p` == "1" ];then
    echo "Didn't detect fabric installation on $p, proceeding to install fabric on it"
    deployFabric $p
  fi
done

#
# prepapre configuraton files
#
echo ".----------"
echo "|  Create configuraton files for the network"
echo "'----------"
rm -rf $CONFIG_DIR 
for p in $nodes ; do
  rm -rf $p
done

PROPAGATEPEERNUM=${PROPAGATEPEERNUM:-3}
i=0
for p in $nodes ; do
  mkdir -p $p/$CONFIG_DIR
  ip=$(getIP $p)
  echo "${p}'s ip address is ${ip}"
  orgLeader=false
  if [[ $i -eq 0 ]];then
    orgLeader=true
  fi
  (( i += 1 ))

  PEER_MSP_ROOT="peerOrganizations/blockr/peers/$p.blockr"
  cat core.yml.template | sed "s|PROPAGATEPEERNUM|${PROPAGATEPEERNUM}| ; s|PEERID|$p| ; s|ADDRESS|$p| ; s|ORGLEADER|$orgLeader| ; s|BOOTSTRAP|$bootPeer:7051| ; s|WITH_TLS|$WITH_TLS| ; s|PEER_MSP_ROOT|$PEER_MSP_ROOT| " > $p/$CONFIG_DIR/core.yaml

  ORDERER_MSP_ROOT="ordererOrganizations/blockr/orderers/$bootPeer.blockr"
  cat orderer.yml.template | sed "s:WITH_TLS:$WITH_TLS: ; s:ORDERER_MSP_ROOT:$ORDERER_MSP_ROOT: " > $p/$CONFIG_DIR/orderer.yaml

  cat configtx.yml.template | sed "s:ANCHOR_PEER_IP:$bootPeer: ; s:ORDERER_IP:$p: ; s:ORDERER_MSP_ROOT:$ORDERER_MSP_ROOT: ; s:PEER_MSP_ROOT:$PEER_MSP_ROOT: " > configtx.yaml

done

if [ -f "blockr-config.yaml" ];then
  rm blockr-config.yaml
fi
cat << EOF >> blockr-config.yaml
################################################################################
#
#  Block R Network Configuration 
#
################################################################################
OrdererOrgs:
  - Name: Org0
    Domain: blockr 
    Specs:
EOF

for p in $nodes ; do
  echo "        - Hostname: $p" >> blockr-config.yaml
done
cat << EOF >> blockr-config.yaml
PeerOrgs:
  - Name: Org1
    Domain: blockr 
    Specs:
EOF
for p in $nodes ; do
  echo "        - Hostname: $p" >> blockr-config.yaml
done
cat << EOF >> blockr-config.yaml
    Users:
      Count: 1
EOF

#
# generate configuraton files
#
echo ".----------"
echo "|  Generate encryption keys"
echo "'----------"
$FABRIC/build/bin/cryptogen generate --config blockr-config.yaml --output $CONFIG_DIR
mv configtx.yaml $CONFIG_DIR
mv blockr-config.yaml $CONFIG_DIR

echo ".----------"
echo "|  Generate 'blockr' channel definition"
echo "'----------"
FABRIC_CFG_PATH=./$CONFIG_DIR $FABRIC/build/bin/configtxgen -profile Channels -outputCreateChannelTx $CONFIG_DIR/blockr.tx -channelID blockr 

echo ".----------"
echo "|  Create genesis block"
echo "'----------"
FABRIC_CFG_PATH=./$CONFIG_DIR $FABRIC/build/bin/configtxgen -profile Genesis -outputBlock $CONFIG_DIR/genesis.block -channelID system

for p in $nodes ; do
echo ".----------"
echo "|  Prepare configuration for node $p"
echo "'----------"
  cp -r $CONFIG_DIR $p

echo ".----------"
echo "|  Reset enviroment on $p"
echo "'----------"
  ssh $p "pkill orderer; pkill peer" || echo ""
  ssh $p "rm -rf /var/hyperledger/production/*"
#  SSH_CMD="cd $FABRIC; git reset HEAD --hard && git pull"
#  ssh $p $SSH_CMD 
  scp -rq $p/$CONFIG_DIR/* $p:$FABRIC/$CONFIG_DIR

echo ".----------"
echo "|  Stop any running Docker containers on $p"
echo "'----------"
  ssh $p "docker ps -aq | xargs docker kill &> /dev/null || echo -n " 
  ssh $p "docker ps -aq | xargs docker rm &> /dev/null || echo -n " 
  ssh $p "docker images | grep 'dev-' | awk '{print $3}' | xargs docker rmi &> /dev/null || echo -n " 

echo ".----------"
echo "|  Start orderer on $p"
echo "'----------"
  SSH_CMD="echo 'FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR $FABRIC/build/bin/orderer &> $FABRIC/orderer.out &' > start.sh; bash start.sh "
  if [ "$DEBUG" = true ]; then
    echo $SSH_CMD
  fi
  ssh $p $SSH_CMD 

echo ".----------"
echo "|  Start peer on $p"
echo "'----------"
  SSH_CMD="echo 'FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR $FABRIC/build/bin/peer node start &> $FABRIC/$p.out &' > start.sh; bash start.sh "
  if [ "$DEBUG" = true ]; then
    echo $SSH_CMD
  fi
  ssh $p $SSH_CMD 
done

echo ".----------"
echo "|  Waiting for all nodes to start up"
echo "'----------"
while :; do
  allOnline=true
  for p in $nodes; do
    if [[ `probePeerOrOrderer $p` -ne 0 ]];then
      echo "$p isn't online yet"
      allOnline=false
      break;
    fi
  done
  if [ "${allOnline}" == "true" ];then
    break;
  fi
  sleep $SYNC_WAIT 
done
sleep $SYNC_WAIT 

#
# creating channel
#
BOOT_NODE_ROOT_TLS=""
BOOT_ORDERER_TLS=""
if [ "$WITH_TLS" = true ]; then
  BOOT_NODE_ROOT_TLS="CORE_PEER_TLS_ROOTCERT_FILE=$FABRIC/$CONFIG_DIR/peerOrganizations/blockr/peers/$bootPeer.blockr/tls/ca.crt"
  BOOT_ORDERER_TLS="--tls true --cafile $FABRIC/$CONFIG_DIR/ordererOrganizations/blockr/orderers/$bootPeer.blockr/tls/ca.crt"
fi

echo ".----------"
echo "|  Creating a channel from one node (using the bootPeer $bootPeer)"
echo "'----------"
SSH_CMD="$BOOT_NODE_ROOT_TLS FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR CORE_PEER_MSPCONFIGPATH=$NODE_ADMIN_MSP CORE_PEER_LOCALMSPID=PeerOrg $FABRIC/build/bin/peer channel create -f $FABRIC/$CONFIG_DIR/blockr.tx  -c blockr -o $bootPeer:7050 $BOOT_ORDERER_TLS"
if [ "$DEBUG" = true ]; then
  echo $SSH_CMD
fi
ssh $bootPeer $SSH_CMD

for p in $nodes ; do
  NODE_ROOT_TLS=""
  ORDERER_TLS=""
  if [ "$WITH_TLS" = true ]; then
    NODE_ROOT_TLS="CORE_PEER_TLS_ROOTCERT_FILE=$FABRIC/$CONFIG_DIR/peerOrganizations/blockr/peers/$p.blockr/tls/ca.crt"
    ORDERER_TLS="--tls true --cafile $FABRIC/$CONFIG_DIR/ordererOrganizations/blockr/orderers/$p.blockr/tls/ca.crt"
  fi
echo ".----------"
echo "|  Joining peer $p to the channel"
echo "'----------"
  SSH_CMD="$NODE_ROOT_TLS FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR  CORE_PEER_MSPCONFIGPATH=$NODE_ADMIN_MSP CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_ADDRESS=$p:7051 $FABRIC/build/bin/peer channel join -b blockr.block"
  if [ "$DEBUG" = true ]; then
    echo $SSH_CMD
  fi
  ssh $p $SSH_CMD

echo ".----------"
echo "|  Install chaincode into peer on $p"
echo "'----------"
  SSH_CMD="$NODE_ROOT_TLS FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR  CORE_PEER_MSPCONFIGPATH=$NODE_ADMIN_MSP CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_ADDRESS=$p:7051 GOPATH=$GOPATH $FABRIC/build/bin/peer chaincode install -p github.com/hyperledger/fabric/examples/chaincode/go/chaincode_example02 -n exampleCC -v 1.0"
  if [ "$DEBUG" = true ]; then
    echo $SSH_CMD
  fi
  ssh $p $SSH_CMD
done

echo ".----------"
echo "|  Instantiate chaincode from one node (using the bootPeer $bootPeer)"
echo "'----------"
ssh_args='{"Args":["init","a","100","b","200"]}'
SSH_CMD="$BOOT_NODE_ROOT_TLS FABRIC_CFG_PATH=$FABRIC/$CONFIG_DIR CORE_PEER_MSPCONFIGPATH=$NODE_ADMIN_MSP CORE_PEER_LOCALMSPID=PeerOrg CORE_PEER_ADDRESS=$bootPeer:7051 $FABRIC/build/bin/peer chaincode instantiate -n exampleCC -v 1.0 -C blockr -c '${ssh_args}' -o $bootPeer:7050 $BOOT_ORDERER_TLS"
if [ "$DEBUG" = true ]; then
  echo $SSH_CMD
fi
ssh $bootPeer $SSH_CMD

echo ".----------"
echo "|  Waiting for nodes to synchronize"
echo "'----------"

for p in $nodes ; do
echo ".----------"
echo "|  Querying chaincode on node $p"
echo "'----------"
  query $p
done

echo ".----------"
echo "|  Invoking chaincode five times"
echo "'----------"
for i in `seq 5`; do
  invoke $bootPeer
done

echo ".----------"
echo "|  Waiting for nodes to synchronize"
echo "'----------"
t1=`date +%s`
while :; do
  allInSync=true
  for p in $nodes ; do
    echo "Querying $p..."
    query $p | grep -q 'Query Result: 50'
    if [[ $? -ne 0 ]];then
      allInSync=false
    fi
  done
  if [ "${allInSync}" == "true" ];then
    echo Sync took $(( $(date +%s) - $t1 ))s
    break
  fi
done

