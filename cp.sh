for ((i=1; i<=7; i++))
do
	scp lockbased_txmgr.go peer$i:/root/gopath/src/github.com/hyperledger/fabric/core/ledger/kvledger/txmgmt/txmgr/lockbasedtxmgr/lockbased_txmgr.go 
done
