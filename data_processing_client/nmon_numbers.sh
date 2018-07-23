#!/bin/bash

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

expNumStart=$1
expNumEnd=$2

echo "ExpNum" \
     "CPU_Usage"\
     "CPU_Idle"\
     "RunnableProcess"\
     "BlockedProcesses"\
     "PSwitch"\
     "Eth1-Read(KB/s)"\
     "Eth1-Write(KB/s)"\
     "DiskBusy%" \

for expNum in $(seq $expNumStart $expNumEnd); do

  pushd exp${expNum}_good;
  
  pushd ./logs/peer0;
  
  ##############################
  # validation starts
  ##############################

  cpuStats=$(grep CPU_ALL *.nmon | awk -F, 'NR>1{s+= $6;n++}END{printf "%.1f %.1f", 100-s/n, s/n}');

  processStats=$(grep PROC *.nmon | awk -F, 'NR>1{runnable+=$3;blocked+=$4;pswitch+=$5;n++}END{printf "%.1f %.1f %.1f",runnable/n,blocked/n,pswitch/n}');

  eth1Stats=$(grep NET, *.nmon | awk -F, 'NR>1{read+=$6;write+=$15;n++}END{printf "%0.1f %0.1f",read/n,write/n}');

  diskBusy=$(grep DISKBUSY *.nmon | awk -F, 'NR>1{s+=$3;n++}END{printf "%.1f\n",s/n}');
  
  
  echo $expNum $cpuStats $processStats $eth1Stats $diskBusy

  popd
  popd

done
