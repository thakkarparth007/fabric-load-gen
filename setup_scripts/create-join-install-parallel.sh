#!/bin/bash

CHANNEL_NAME="$1"
N_ENDORSERS=$2
: ${TIMEOUT:="60"}
COUNTER=1
MAX_RETRY=5
ORDERER_CA=/root/bcnetwork/conf/crypto-config/ordererOrganizations/ordererorg0/msp/cacerts/ca.ordererorg0-cert.pem
ORDERER0=orderer0
PEERS=( 'peer0' 'peer1' 'peer2' 'peer3' 'peer4' 'peer5' 'peer6' 'peer7' )
NPEERS=8
NPEERS_PER_ORG=2
ENDORSEMENT_POLICY=""

# Use the N-Of syntax if you want shorter policies!
setEndorsementPolicy () {
    nEndorsers=$1
    if [ $nEndorsers -eq 1 ]; then
        ENDORSEMENT_POLICY="OR ('Org0MSP.member','Org1MSP.member','Org2MSP.member','Org3MSP.member')"
    elif [ $nEndorsers -eq 2 ]; then
        ENDORSEMENT_POLICY="OR ("
        ENDORSEMENT_POLICY+="AND ('Org0MSP.member','Org1MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org0MSP.member','Org2MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org0MSP.member','Org3MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org1MSP.member','Org2MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org1MSP.member','Org3MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org2MSP.member','Org3MSP.member')"
        ENDORSEMENT_POLICY+=")"
    elif [ $nEndorsers -eq 3 ]; then
        ENDORSEMENT_POLICY="OR ("
        ENDORSEMENT_POLICY+="AND ('Org1MSP.member','Org2MSP.member','Org3MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org0MSP.member','Org2MSP.member','Org3MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org0MSP.member','Org1MSP.member','Org3MSP.member'),"
        ENDORSEMENT_POLICY+="AND ('Org0MSP.member','Org1MSP.member','Org2MSP.member')"
        ENDORSEMENT_POLICY+=")"
	echo $ENDORSEMENT_POLICY;
    elif [ $nEndorsers -eq 4 ]; then
        ENDORSEMENT_POLICY="AND ('Org0MSP.member','Org1MSP.member','Org2MSP.member','Org3MSP.member')"
    else
        echo "Invalid endorsement policy given. Given $nEndorsers. Expected 1/2/3/4";
	exit 1;
    fi
}

verifyResult () {
    if [ $1 -ne 0 ] ; then
        echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
                echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
}

setGlobals () {

    PEER_ID=$1
    ORG_ID=$(($PEER_ID/$NPEERS_PER_ORG)) 

    export CORE_PEER_LOCALMSPID="Org${ORG_ID}MSP"
    export CORE_PEER_MSPCONFIGPATH=/root/bcnetwork/conf/crypto-config/peerOrganizations/org${ORG_ID}/users/Admin@org${ORG_ID}/msp
    export CORE_PEER_ADDRESS=${PEERS[$PEER_ID]}:7051
    env |grep CORE
}

createChannel() {
    setGlobals 0 

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        peer channel create -o $ORDERER0:7050 -c $CHANNEL_NAME -f $CHANNEL_NAME.tx -t 60 >&log.txt
    else
        peer channel create -o $ORDERER0:7050 -c $CHANNEL_NAME -f $CHANNEL_NAME.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
    fi
    res=$?
    cat log.txt
    verifyResult $res "Channel creation failed"
    echo "===================== Channel \"$CHANNEL_NAME\" is created successfully ===================== "
    echo
}

updateAnchorPeers() {
    PEER_ID=$1
    setGlobals $PEER_ID

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        peer channel update -o $ORDERER0:7050 -c $CHANNEL_NAME -f ${CORE_PEER_LOCALMSPID}anchors.tx >&log.txt
    else
        peer channel update -o $ORDERER0:7050 -c $CHANNEL_NAME -f ${CORE_PEER_LOCALMSPID}anchors.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
    fi
    res=$?
    cat log.txt
    verifyResult $res "Anchor peer update failed"
    echo "===================== Anchor peers for org \"$CORE_PEER_LOCALMSPID\" on \"$CHANNEL_NAME\" is updated successfully ===================== "
    echo
}

## Sometimes Join takes time hence RETRY atleast for 5 times
joinWithRetry () {
    peer channel join -b $CHANNEL_NAME.block  >&log.txt
    res=$?
    cat log.txt
    if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
        COUNTER=` expr $COUNTER + 1`
        echo "PEER$1 failed to join the channel, Retry after 2 seconds"
        sleep 2
        joinWithRetry $1
    else
        COUNTER=1
    fi
        verifyResult $res "After $MAX_RETRY attempts, PEER$ch has failed to Join the Channel"
}

joinChannel () {
    for ch in {0..7} ; do
        (setGlobals $ch;
        joinWithRetry $ch;
        echo "===================== PEER$ch joined on the channel \"$CHANNEL_NAME\" ===================== " ;) &
    done
    wait;
}

installChaincode () {
    PEER_ID=$1
    setGlobals $PEER_ID
    peer chaincode install -n generic-chaincode -v 1.0 -p github.com/hyperledger/fabric/examples/chaincode/go/generic-chaincode >&log.txt
    res=$?
    cat log.txt
        verifyResult $res "Chaincode installation on remote peer PEER$PEER has Failed"
    echo "===================== Chaincode is installed on remote peer PEER$PEER ===================== "
    echo
}

instantiateChaincode () {
	PEER=$1
	setGlobals $PEER
	setEndorsementPolicy $N_ENDORSERS

	# while 'peer chaincode' command can get the orderer endpoint from the peer (if join was successful),
	# lets supply it directly as we know it using the "-o" option
	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
		peer chaincode instantiate -o orderer0:7050 -C $CHANNEL_NAME -n generic-chaincode -v 1.0 -c '{"Args":["init"]}' -P "$ENDORSEMENT_POLICY" >&log.txt
	else
		peer chaincode instantiate -o orderer.example.com:7050 --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME -n mycc -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR	('Org1MSP.member','Org2MSP.member')" >&log.txt
	fi
	res=$?
	cat log.txt
	verifyResult $res "Chaincode instantiation on PEER$PEER on channel '$CHANNEL_NAME' failed"
	echo "===================== Chaincode Instantiation on PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
	echo
}

chaincodeQuery () {
  PEER=$1
  setGlobals $PEER
  peer chaincode query -C $CHANNEL_NAME -n generic-chaincode -c '{"Args":["query","a"]}' >&log.txt
  echo "===================== Chaincode Query PEER$PEER on channel '$CHANNEL_NAME' is successful ===================== "
  
}
## Clear channel data from db
for i in peer{0..7}; do ssh $i "curl -X DELETE http://localhost:5984/$CHANNEL_NAME; curl -H 'Content-Type: application/json' -X POST http://localhost:5984/_global_changes/_compact" & done
wait

## Create channel
createChannel

## Join all the peers to the channel
joinChannel
## Set the anchor peers for each org in the channel
## updateAnchorPeers fails in parallel mode.
## Doesn't matter, it's fast enough on its own.
for ((i=0; i<=6; i=i+2))
do
    updateAnchorPeers $i  
done

## Install chaincode on Peer0/Org1 and Peer2/Org2
for ((i=0; i<8; i++))
do
    echo "Installing chaincode on Peer$i ..."
    installChaincode $i &
done
wait

instantiateChaincode 0

sleep 10
for ((i=1; i<8; i++))
do
   chaincodeQuery $i &
done

wait # just for safety.
