set -xa
for ((i=0; i<=7; i++))
do
	scp -r generic-chaincode root@peer$i:/root/gocode/src/github.com/hyperledger/fabric/examples/chaincode/go
done
