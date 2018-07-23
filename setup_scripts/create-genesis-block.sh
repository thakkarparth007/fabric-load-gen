set -xa 

nOrgs=$1

rm -rf crypto-config/
cryptogen generate --config=./crypto-config.yaml

if [ "$nOrgs" == "2" ]
then 
    configtxgen -profile TwoOrgsOrdererGenesis -outputBlock genesis.block
elif [ "$nOrgs" == "4" ]
then
    configtxgen -profile FourOrgsOrdererGenesis -outputBlock genesis.block
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
