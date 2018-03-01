#!/bin/bash

batchSize=$(awk '/MaxMessageCount/ {print $2}' ../../crypto-configtxgen/configtx.yaml)
batchTimeout=$(awk '/BatchTimeout/ {print $2}' ../../crypto-configtxgen/configtx.yaml)
runTime=$(awk '/loadDuration/ {print $2/60000 "min"}' ./config.yaml)
numClients=$(awk '/numClients/ {print $2}' ./config.yaml)
inputRate=$(awk -v numClients=$numClients '/numLocalRequestsPerSec/ {print $2*numClients,"Tx/s"}' ./config.yaml)
openSystem=$(awk '/openSystem/ {print $2}' ./config.yaml)

cat > exp_desc.txt <<- EXP_DESC
Batch-Size: $batchSize
Block-Cutoff: $batchTimeout
Runtime: $runTime
Number of Clients: $numClients
Total input rate: $inputRate
Open System: $openSystem
EXP_DESC

