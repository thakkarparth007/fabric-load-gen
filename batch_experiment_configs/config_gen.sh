#!/bin/bash

egrep -v "#" experiments.txt | \
while read -r line || [[ -n "$line" ]]; do
    numProcesses=$(echo $line | awk '{print $1}');
    numClientsPerProcess=$(echo $line | awk '{print $2}');
    numLocalRequestRate=$(echo $line | awk '{print $3}');
    batchSize=$(echo $line | awk '{print $4}');
    nEndorsers=$(echo $line | awk '{print $5}');
    nChannels=$(echo $line | awk '{print $6}');

    echo $((numProcesses*numClientsPerProcess*numLocalRequestRate))Tx/s Batch-$batchSize $nEndorsers-Endorsers $nChannels-Channels;
done
