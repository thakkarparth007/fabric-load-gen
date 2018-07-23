set -xa 

nOrgs=$1
chName=$2

if [ $chName == "" ]; then
    chName="ch1";
fi

rm -rf crypto-config/
cryptogen generate --config=./crypto-config.yaml

if [ "$nOrgs" == "2" ]
then 
    configtxgen -profile TwoOrgsOrdererGenesis -outputBlock genesis.block

    configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../${chName}.tx -channelID ${chName}

    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../Org0MSPanchors.tx -channelID ${chName} -asOrg Org0MSP

    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../Org1MSPanchors.tx -channelID ${chName} -asOrg Org1MSP
elif [ "$nOrgs" == "4" ]
then
    configtxgen -profile FourOrgsOrdererGenesis -outputBlock genesis.block

    configtxgen -profile FourOrgsChannel -outputCreateChannelTx ../${chName}.tx -channelID ${chName}

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org0MSPanchors.tx -channelID ${chName} -asOrg Org0MSP

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org1MSPanchors.tx -channelID ${chName} -asOrg Org1MSP

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org2MSPanchors.tx -channelID ${chName} -asOrg Org2MSP

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org3MSPanchors.tx -channelID ${chName} -asOrg Org3MSP
fi

for ((i=0; i<1; i++)) 
do
	cp genesis.block crypto-config/ordererOrganizations/ordererorg${i}/orderers/orderer0.ordererorg${i}/ 
done

rm -rf /root/bcnetwork/conf/crypto-config

cp -r crypto-config /root/bcnetwork/conf/

for ((i=0; i<8; i++)) 
do
	(ssh peer${i} 'rm -rf /root/bcnetwork/conf/crypto-config/'
	scp -r crypto-config/ peer${i}:/root/bcnetwork/conf/) &
done


for ((i=0; i<1; i++)) 
do
    (ssh orderer${i} 'rm -rf /root/bcnetwork/conf/crypto-config/'
	scp -r crypto-config/ orderer${i}:/root/bcnetwork/conf/) &
done

wait
