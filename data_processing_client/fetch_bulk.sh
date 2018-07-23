#!/bin/bash

# https://github.com/tests-always-included/wick/blob/master/doc/bash-strict-mode.md
set -eEu -o pipefail

theStart=$1
theEnd=$2

nCores=$(grep 'cpu cores' /proc/cpuinfo | awk '{s+=$4;}END{print s}')
nParallel=$((nCores*2))
for i in $(seq $theStart $nParallel $theEnd); do
    for j in $(seq $i $((i+nParallel-1))); do
        ./fetch_new_data.sh -e $j &
    done
    wait;
    #./fetch_new_data.sh -e $((i+1)); 
done

(for j in $(seq $theStart $theEnd); do i=exp${j}_good; echo -n $i' '; awk '{ if(NR==1 || NR==3 || NR==8) printf $0" " }' $i/exp_desc.txt; grep brief $i/config.yaml; done) | sort -k10n -k6

for i in $(seq $theStart $theEnd); do
    ./fetch_new_data.sh -e $i -x;
done
