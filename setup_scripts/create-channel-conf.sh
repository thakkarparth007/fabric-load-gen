set -xa 

nOrgs=$1
chName=$2

if [ $chName == "" ]; then
    chName="ch1";
fi

if [ "$nOrgs" == "2" ]
then 
    configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ../${chName}.tx -channelID ${chName}

    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../Org0MSPanchors.tx -channelID ${chName} -asOrg Org0MSP

    configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ../Org1MSPanchors.tx -channelID ${chName} -asOrg Org1MSP
elif [ "$nOrgs" == "4" ]
then
    configtxgen -profile FourOrgsChannel -outputCreateChannelTx ../${chName}.tx -channelID ${chName}

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org0MSPanchors.tx -channelID ${chName} -asOrg Org0MSP

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org1MSPanchors.tx -channelID ${chName} -asOrg Org1MSP

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org2MSPanchors.tx -channelID ${chName} -asOrg Org2MSP

    configtxgen -profile FourOrgsChannel -outputAnchorPeersUpdate ../Org3MSPanchors.tx -channelID ${chName} -asOrg Org3MSP
fi
