#!/bin/bash

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

# Shows micronumbers only for committer. To add micronumbers for endorsers

expNumStart=$1
expNumEnd=$2

echo "ExpNum" \
     "ValidateTransaction(Signature)" \
     "GetTransactionById" \
     "VSCCValidateTx" \
     "TotalValidationPerTx" \
     "TheorTotalValidationPerBlock" \
     "TotalValidationPerTx" \
     "MeasuredTotalValidationPerBlk" \
     "ValidateAndPrepare" \
     "blockStore.AddBlock(disk)" \
     "StateDB.Commit" \
     "HistoryDB.Commit" \
     "TheorCommitPerBlock" \
     "MeasuredCommitPerBlock"

for expNum in $(seq $expNumStart $expNumEnd); do

  pushd exp${expNum}_good;
  blockSize=$(awk '/Batch-Size:/{print $2}' exp_desc.txt)
  
  pushd ./logs/peer0;
  
  ##############################
  # validation starts
  ##############################
  
  # ValidateTx (Signature)
  validateTx=$(grep ValidateTransaction txvalidator.log| awk '{ sum += $7; n++ } END { if (n > 0) printf "%.3f", (sum / n)/1000000; }')
  
  # GetTxById
  getTxById=$(grep GetTransactionById txvalidator.log | awk '{ sum += $7; n++ } END { if (n > 0) printf "%.3f", (sum / n)/1000000; }')
  
  # VSCC Validate
  vsccValidateTx=$(grep VSCCValidateTx txvalidator.log | awk '{ sum += $7; n++ } END { if (n > 0) printf "%.3f", (sum / n)/1000000; }')
  
  # TotalValidationPerTx
  totalValidionPerTx=$(echo "$validateTx+$getTxById+$vsccValidateTx" | bc)
  
  # TheorTotalValPerBlk
  theorTotalValPerBlk=$(echo "$totalValidionPerTx*$blockSize" | bc)
  
  # Measured Block validate time
  blockValidation=$(grep Validated committer.log| awk '{ sum += $6; n++ } END { if (n > 0) printf "%.3f", (sum / n)/1e6; }')
  
  #############################
  # commit starts
  ##############################
  
  # ValidateAndPrepare
  validateAndPrepare=$(grep ValidateAndPrepare kvledger.log| awk '{ sum += $7; n++ } END { if (n > 0) printf "%.3f", (sum / n/1e6); }')
  
  # blockStore.AddBlock(disk)
  blkStoreAddBlock=$(grep disk kvledger.log| awk '{ sum += $8; n++ } END { if (n > 0) printf "%.3f", sum/n/1e6; }')
  
  # StateDB.Commit
  stateDbCommit=$(grep StateDB kvledger.log| awk '{ sum += $7; n++ } END { if (n > 0) printf "%.3f", sum/n/1e6; }')
  
  # HistoryDB.Commit
  historyDbCommit=$(grep HistoryDB kvledger.log| awk '{ sum += $7; n++ } END { if (n > 0) printf "%.3f", sum/n/1e6; }')
  
  # TheorCommitTime
  theorCommitTime=$(echo "$validateAndPrepare+$blkStoreAddBlock+$stateDbCommit+$historyDbCommit" | bc)
  
  # MeasuredCommitTime
  measuredCommitTime=$(grep Committed committer.log| awk '{ sum += $6; n++ } END { if (n > 0) printf "%.3f", (sum / n)/1000000; }')
  
  printf "$expNum "
  printf "%.3f " $validateTx
  printf "%.3f " $getTxById
  printf "%.3f " $vsccValidateTx
  printf "%.3f "  $totalValidionPerTx
  printf "%.3f " $theorTotalValPerBlk
  printf "%.3f " $totalValidionPerTx
  printf "%.3f " $blockValidation
  printf "%.3f " $validateAndPrepare
  printf "%.3f " $blkStoreAddBlock
  printf "%.3f " $stateDbCommit
  printf "%.3f " $historyDbCommit
  printf "%.3f " $theorCommitTime
  printf "%.3f " $measuredCommitTime
  echo ""

  popd
  popd

done
