#!/bin/bash

# Generates 3 useful files other than throughput.txt
# maxLatencies.txt      - is the same is blockDuration
# validTx.txt           - Number of valid transactions per block
# blockArrivalTimes.txt - Arrival times of each block

echo "Use this from the directory that has the raw data"

#grep "BlockDuration" perf* | sed 's/perf_ch1_blk#//' | sort -n | egrep -o "[0-9]+," | sed -r 's/[0-9]{9},//' > maxLatencies.txt
#nl --number-format=rz --number-width=4 maxLatencies.txt > maxLatencies_blkNum.txt
#mv maxLatencies_blkNum.txt maxLatencies.txt
#grep -r "Valid" perf_* | sed 's/perf_ch1_blk#//' | sort -n > validTx.txt
#grep -r "TxCommit" perf* | uniq | sed 's/perf_ch1_blk#//' | sort -n > blockArrivalTimes.txt

grep "BlockDuration" perf* | sed -r 's/perf_ch([0-9]+)_blk#([0-9]+).json/\2-\1/' | sort -n | awk '{printf "%s %d\n", $1,($3/1000000)}' > maxLatencies.txt

echo "Blk-Ch #Valid #Invalid" > validTx.txt
(for i in perf*; do echo $i | sed -r 's/perf_ch([0-9]+)_blk#([0-9]+).json/\2-\1/g' | tr '\n' ' '; awk '/Num(Inv|V)alid/{printf "%d ", $2}' $i; echo ""; done) | sort -n >> validTx.txt

grep -r "TxCommit" perf* | uniq | sed -r 's/perf_ch([0-9]+)_blk#([0-9]+).json/\2-\1/' | tr '"' ' ' | less | awk '{print $1,$4}' | cut -f1 -d. | sort -n  > blockArrivalTimes.txt
