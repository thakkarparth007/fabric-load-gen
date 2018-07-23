#!/bin/bash

unset http_proxy
unset https_proxy

echo 1 > /proc/sys/vm/drop_caches
./kill-monitoring.sh

echo "Checking if cryptoconfig and configtx needs to be updated"
oldBatchSize=$(awk '/MaxMessageCount/ {print $2}' ../../crypto-configtxgen/configtx.yaml)
newBatchSize=$(awk '/batchSize/ {print $2}' ./config.yaml)

channels=$(awk '/channels/ {print $2}' ./config.yaml | sed 's/,/ /g')
if [ $channels == "" ]; then
    "'channels' required in config.yaml"
    exit 1
fi

if [ $oldBatchSize != $newBatchSize ]; then
    echo "Regenerating cryptoconfig material"
    pushd ../../crypto-configtxgen
    sed -i -r 's/(MaxMessageCount:).*$/\1 '$newBatchSize'/' ./configtx.yaml
    ./create-genesis-block.sh 4
    popd
else
    echo "Reusing old cryptoconfig material"
fi

echo "Updating endorsement policy if necessary"
newEndorsementPolicy=$(grep 'endorsement' ./config.yaml | grep -o "[0-9]" - | head -n1)
#if [ $newEndorsementPolicy != "1" ]; then
#    echo "Endorsement policy: AND"
#    sed -i 's/-P "OR /-P "AND /' ../../create-join-install-parallel.sh
#else
#    echo "Endorsement policy: OR"
#    sed -i 's/-P "AND /-P "OR /' ../../create-join-install-parallel.sh
#fi

function restartNetwork() {
    pushd /root/tools/scripts/
    RETRIES_MAX=3
    for retry in $(seq 1 $RETRIES_MAX); do
        ./start-network-parallel.sh
    
        sleep 30
    
        FAILED_INIT=false
        for i in $channels; do
            pushd ./crypto-configtxgen
            ./create-channel-conf.sh 4 $i;
            popd
            ./create-join-install-parallel.sh $i $newEndorsementPolicy;
	    if [ $? -eq 1 ]; then
	        FAILED_INIT=true
	        break; # stop if that failed
	    fi
        done

	if [ $FAILED_INIT == "false" ]; then
	    break;  # Done!
	fi
    done
    #./create-join-install-parallel.sh ch1
    popd
}

echo "Restarting network"
restartNetwork

echo "Starting resource monitor"
../../capture-resource-usage.sh

echo "Starting fetch-block"
pushd ../../fetch-block/
latestFolder=$(ls -t -1 . | head -n1 | egrep -o "[0-9]+")
echo perfLogs_$((latestFolder+1)) | ./fetch-block > ../IRL/load_generator/fetch-block-out.txt &
popd

# Set automatic stopping of load gen in closed system.
# Wait for 60s of grace time to allow starting and stopping.
#isOpen=$(awk '/openSystem/ {print $2}' config.yaml)
#if [ $isOpen == "false" ]; then
    duration=$(awk '/loadDurationMs/ {print $2}' config.yaml)
    durationSec=$((duration/1000))
    (sleep $((durationSec+10)); pkill node; ./stopAndPack.sh) &
#fi

echo "Starting load generator"
node main_multiclient.js

#sleep 30;
#./stopAndPack.sh;

#if [ $isOpen != "false" ]; then
#    echo "Don't forget to stop the resource monitors!"
#fi

wait
