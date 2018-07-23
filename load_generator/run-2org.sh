#!/bin/bash
echo 1 > /proc/sys/vm/drop_caches
./kill-monitoring.sh

echo "Checking if cryptoconfig and configtx needs to be updated"
oldBatchSize=$(awk '/MaxMessageCount/ {print $2}' ../../crypto-configtxgen/configtx.yaml)
newBatchSize=$(awk '/batchSize/ {print $2}' ./config.yaml)

if [ $oldBatchSize != $newBatchSize ]; then
    echo "Regenerating cryptoconfig material"
    pushd ../../crypto-configtxgen
    sed -i -r 's/(MaxMessageCount:).*$/\1 '$newBatchSize'/' ./configtx.yaml
    ./create-crypto-and-gensis-block-2org.sh
    popd
else
    echo "Reusing old cryptoconfig material"
fi

echo "Updating endorsement policy if necessary"
newEndorsementPolicy=$(grep 'endorsement' ./config.yaml | grep -o "[0-9]" - | head -n1)
if [ $newEndorsementPolicy != "1" ]; then
    echo "Endorsement policy: AND"
    sed -i 's/-P "OR /-P "AND /' ../../create-join-install-parallel-2org.sh
else
    echo "Endorsement policy: OR"
    sed -i 's/-P "AND /-P "OR /' ../../create-join-install-parallel-2org.sh
fi

echo "Restarting network"
pushd /root/tools/scripts/
./start-network-parallel.sh

./create-join-install-parallel-2org.sh ch1
popd

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
    (sleep $((durationSec+150)) && pkill node && ./stopAndPack-2org.sh) &
#fi

echo "Starting load generator"
node main_multiclient.js

if [ $isOpen != "false" ]; then
    echo "Don't forget to stop the resource monitors!"
fi

wait
