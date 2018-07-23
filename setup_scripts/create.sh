#CORE_PEER_MSPCONFIGPATH=/root/bcnetwork/conf/crypto-config/ordererOrganizations/ordererorg0/users/Admin@ordererorg0/msp \
CORE_PEER_LOCALMSPID=Org0MSP \
CORE_PEER_MSPCONFIGPATH=/root/bcnetwork/conf/crypto-config/peerOrganizations/org0/users/Admin@org0/msp \
CORE_PEER_ADDRESS=peer0:7051 \
peer channel create -o 10.16.9.105:7050 -c ch1 -f ch1.tx  -t 60
