#!/bin/bash

for i in peer{0..7} orderer0 kafka-zookeeper;
do
    ssh $i 'pkill nmon; pkill tcpdump; pkill inotifywait; rm -rf *.nmon *.pcap *inotify.log data.zip' &
    rm -rf logs/$i
    mkdir -p logs/$i
done

wait
