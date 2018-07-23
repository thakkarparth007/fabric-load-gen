set -xa 
rm -rf crypto-config/
cryptogen generate --config=./crypto-config.yaml

configtxgen -profile TwoOrgsOrdererGenesis -outputBlock genesis.block

configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../ch1.tx -channelID ch1

configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../Org0MSPanchors.tx -channelID ch1 -asOrg Org0MSP

configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../Org1MSPanchors.tx -channelID ch1 -asOrg Org1MSP

for ((i=0; i<1; i++)) 
do
	cp genesis.block crypto-config/ordererOrganizations/ordererorg${i}/orderers/orderer0.ordererorg${i}/ 
done

rm -rf /root/bcnetwork/conf/crypto-config

cp -r crypto-config /root/bcnetwork/conf/

for ((i=0; i<4; i++)) 
do
	ssh peer${i} 'rm -rf /root/bcnetwork/conf/crypto-config/'
	scp -r crypto-config/ peer${i}:/root/bcnetwork/conf/
	if [ "${i}" -le "1" ]; then
		ssh orderer${i} 'rm -rf /root/bcnetwork/conf/crypto-config/'
		scp -r crypto-config/ orderer${i}:/root/bcnetwork/conf/
	fi
done

