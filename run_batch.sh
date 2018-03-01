#!/bin/bash

set -e

expNum=500
OLDIFS=$IFS
IFS=$'\n'

printf "\n\n" >> batch_experiment_configs/log.txt
for line in $(grep -v "#" ./batch_experiment_configs/experiments.txt); do
    if [[ -z "${line// }" ]]; then
        continue;
    fi
    
    if [[ "${line}" == '$'* ]]; then
	echo "";
    	echo "Evaluating '$line'";
    	echo "$(date) Evaluating '$line'" >> batch_experiment_configs/log.txt
	line=$(echo ${line} | sed -r 's/^\$\s*//');
	bash -c "${line}";
	continue;
    fi

    echo "Entering loop";

    numProcesses=$(echo $line | awk '{print $1}');
    numClientsPerProcess=$(echo $line | awk '{print $2}');
    numLocalRequestsPerSec=$(echo $line | awk '{print $3}');
    batchSize=$(echo $line | awk '{print $4}');
    nEndorsers=$(echo $line | awk '{print $5}');
    nChannels=$(echo $line | awk '{print $6}');
    openOrClosed=$(echo $line | awk '{print $7}');
    dbType=$(echo $line | awk '{print $9}');
    if [ $dbType == "LevelDB" ]; then
        dbType="goleveldb"
    else
        dbType="CouchDB"
    fi
    
    vCPU_Count=$(echo $line | awk '{print $10}' | egrep -o "[0-9]+"); # just get the number of vCPUs, not a string like "2vCPU" or "4vCPU"
    ./set_vcpu.sh $vCPU_Count 

    loadType=$(echo $line | awk '{print $11}');
    if [ $loadType == "readWrite" ]; then
        loadSize=$(echo $line | awk '{print $12}');
	sed -r -i 's|chaincode/go/generic-chaincode|chaincode/go/readwrite-chaincode|g' ../../create-join-install-parallel.sh
    else
        sed -r -i 's|chaincode/go/readwrite-chaincode|chaincode/go/generic-chaincode|g' ../../create-join-install-parallel.sh
    fi

    channels=""
    for i in $(seq 1 $nChannels); do
        channels+="ch"$i
	if [ $i -lt $nChannels ]; then
	    channels+=",";
	fi
    done

    brief=$(echo $((numProcesses*numClientsPerProcess*numLocalRequestsPerSec))Tx/s, Batch-$batchSize, $openOrClosed system, $nEndorsers-Endorsers, $nChannels-Channels - Full: "'$(echo $line | awk '{$1=$1;print}')'");
    sed -r -i 's|^brief:.*$|brief: '"$brief"'|' config.yaml
    sed -r -i 's/^numProcesses: [0-9]*/numProcesses: '"$numProcesses"'/' config.yaml
    sed -r -i 's/^numClientsPerProcess: [0-9]*/numClientsPerProcess: '"$numClientsPerProcess"'/' config.yaml
    sed -r -i 's/^numLocalRequestsPerSec: [0-9]*/numLocalRequestsPerSec: '"$numLocalRequestsPerSec"'/' config.yaml
    sed -r -i 's/^batchSize: [0-9]*/batchSize: '"$batchSize"'/' config.yaml
    sed -r -i 's/^endorsementPolicy: "[^"]*"/endorsementPolicy: "'"$nEndorsers"'\/4"/' config.yaml
    sed -r -i 's/^channels: [^ ]*/channels: '"$channels"'/' config.yaml
    sed -r -i 's/^workload: [^ ]*/workload: '"$loadType"Workload'/' config.yaml
    #sed -r -i 's/dataFileName: .\/workloads.\/readWriteExperiments\/(.*).json/dataFileName: .\/workloads.\/readWriteExperiments\/'"$loadSize"'.json/' config.yaml
    sed -r -i 's/readWriteExperiments\/(.*).json/readWriteExperiments\/'"$loadSize"'.json/' config.yaml
    sed -r -i 's/dbType: [^ ]*/dbType: '$dbType'/' config.yaml
    for i in peer{0..7}; do ssh $i "fabric; sed -r -i 's/stateDatabase: [^ ]*/stateDatabase: $dbType/' sampleconfig/core.yaml" & done
    wait

    if [ "$openOrClosed" == "open" ]; then
        sed -r -i 's/openSystem: [^ ]*/openSystem: true/' config.yaml
    else
        sed -r -i 's/openSystem: [^ ]*/openSystem: false/' config.yaml
    fi
    echo "$(date) Starting new experiment from config: ($expNum)" $brief >> batch_experiment_configs/log.txt

    ./run.sh
    logName=$(ls -1 | grep exp_good | egrep -o "[0-9]+" | sort -nr | head -n1)
    loadDurationInS=$(awk '/loadDurationMs/{print $2/1000}' config.yaml)
    inputRate=$(wc -l logs/proposalLatencies.txt | awk '{printf "%.1f",$1/'$loadDurationInS'}');
    echo "$(date) Finished experiment $logName. Approx input rate: $inputRate Tx/s" >> batch_experiment_configs/log.txt
    latestFolder=$(ls -t -1 ~/tools/scripts/fetch-block/ | grep perfLogs | head -n1 | egrep -o "[0-9]+")
    find ~/tools/scripts/fetch-block/perfLogs_$latestFolder/ -name "*.json" -delete
    echo "Done with loop. Next iteration now";
done

echo hi
