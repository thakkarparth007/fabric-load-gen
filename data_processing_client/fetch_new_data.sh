#!/bin/bash

### WARNINGS TO NEW USER!
# 1. MODIFY THE PATHS!
# 2. For histogram.py to run, do `pip install data_hacks` (https://github.com/bitly/data_hacks)
# 3. Throughput measurement isn't correctly done for ReadWrite experiments. Won't work for experiments where there is a bootstrap portion in the experiment. To calculate the correct throughput number, you could do something like avg of last 100-120s of the experiment. Do `cut -f2 -d= throughput.txt | cut -f1 -d' ' | tail -n120 | histogram.py`
### WARNING ENDS


# https://github.com/tests-always-included/wick/blob/master/doc/bash-strict-mode.md
#set -eEu -o pipefail

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

function fetch() {
    #if [ -e exp${EXP_NUM}_good.zip ]
    #then
    #    echo "exp${EXP_NUM}_good.zip exists. Won't overwrite."
    #    exit 1
    #fi
    
    if [ -d exp${EXP_NUM}_good ]
    then
        echo "exp${EXP_NUM}_good folder exists. Won't overwrite."
        exit 1
    fi
    
    #scp root@irldxph005.irl.in.ibm.com:exp_good_${EXP_NUM}.zip exp${EXP_NUM}_good.zip
    #scp root@9.126.108.106:/root/cendhu/experiment_data/exp_good_${EXP_NUM}.zip exp${EXP_NUM}_good.zip
    #cp /root/cendhu/experiment_data/exp_good_${EXP_NUM}.zip exp${EXP_NUM}_good.zip
    mkdir exp${EXP_NUM}_good
    unzip /root/cendhu/experiment_data/exp_good_${EXP_NUM}.zip -d exp${EXP_NUM}_good/

    pushd exp${EXP_NUM}_good/
    
    mv logs/*.txt .
    mv logs/config.yaml .

    #for j in peer{0..7} orderer0; do
    #    pushd logs/$j;
    #    rm ledgerLocksCommits.log;
    #    popd;
    #done

    popd
}

function get_stats_from_summary() {
    summary=$1
    mean=$(echo "$summary" | awk '/Mean /{printf "%0.1f", $4}')
    #stddev=$(echo "$summary" | awk '/Median/{printf "%0.1f", $10}')
    max=$(echo "$summary" | awk '/Max/{printf "%0.1f", $10}')
    min=$(echo "$summary" | awk '/Min/{printf "%0.1f", $7}')
    #median=$(echo "$summary" | awk '/Median/{printf "%0.1f", $12}')
    #summary=$mean" "$stddev" "$median
    summary=$mean" "$min" "$max
}

function generate_excel_row() {
    pushd exp${EXP_NUM}_good/

    exp_name=exp${EXP_NUM}_good
    input_rate=$(awk '/brief/{printf $2}' ./config.yaml)
    effective_input=""
    batch_size=$(awk '/brief/{printf $3}' ./config.yaml)
    num_endorsers=$(awk '/brief/{printf $6}' ./config.yaml)
    num_channels=$(awk '/brief/{print $7}' ./config.yaml)
    writer_waiting_time=""
    blocking_readers=""
    acquiring_lock_per_min=""
    acquiring_lock_duration=""
    avg_throughput=""
    proposal_latency=""
    broadcast_latency=""
    commit_latency=""
    commit_queue_length=""
    broadcast_queue_length=""

    ##   
    ## Writer waiting times
    ##

    # Get number of lines in tmp.txt during endorsement period. Bash is awesome. :')
    duringEndorsementLines=$(awk -v x="$(tail -n1 proposalLatencies.txt | cut -f1 -d' ')" '$1 < x' tmp.txt | wc -l)
    afterEndorsementLines=$(awk -v x="$(tail -n1 proposalLatencies.txt | cut -f1 -d' ')" '$1 > x' tmp.txt | wc -l)

    #get_stats_from_summary "$(cut -f3 -d' ' tmp.txt | head -n$duringEndorsementLines | histogram.py)"
    get_stats_from_summary "$(grep -C18 'Writer waiting times' exp_desc.txt | tail -n14)"
    writer_waiting_times=$summary

    ##
    ## Blocking readers
    ##
    #get_stats_from_summary "$(cut -f2 -d' ' tmp.txt | head -n$duringEndorsementLines | histogram.py)"
    maxblocking_readers=$(cut -f2 -d' ' tmp.txt | head -n$duringEndorsementLines | sort -rn | head -n1)
    blocking_readers=$maxblocking_readers

    ##
    ## 'Acquiring Lock' attempts
    ##
    
    lock_stuff=$(grep -r "Acquiring Loc" logs/peer2/ledgerLocksCommits.log | cut -f 2 -d':' | uniq -c | awk 'NR>2{print $1}')
    get_stats_from_summary "$(echo $lock_stuff | tr ' ' '\n' | histogram.py)"
    acquiring_lock_per_min=$summary

    ##
    ## 'Acquiring Lock' minutes
    ##
    
    acquiring_lock_duration=$(echo "$lock_stuff" | wc -l | awk '{$1=$1;print}')"min"

    ##
    ## Throughputs
    ##
    
    proposalStartTimeUTC=$(head -n1 proposalLatencies.txt | cut -f1 -d' ')
    proposalEndTimeUTC=$(tail -n1 proposalLatencies.txt | cut -f1 -d' ')
    
    # throughput.txt stuff is in IST
    proposalStartTimeIST=$(TZ="Asia/Kolkata" date --rfc-3339='s' -d $proposalStartTimeUTC | tr ' ' 'T')
    proposalEndTimeIST=$(TZ="Asia/Kolkata" date --rfc-3339='s' -d $proposalEndTimeUTC | tr ' ' 'T')
    
    duringEndorsementLines=$(awk -v s="$proposalStartTimeIST" -v e="$proposalEndTimeIST" 's <= $1 && $1 <= e' throughput.txt | wc -l)
    afterEndorsementLines=$(awk -v e="$proposalEndTimeIST" 'e <= $1' throughput.txt | wc -l)

    numProposals=$(wc -l proposalLatencies.txt | awk '{print $1}')
    effective_input=$((numProposals/(duringEndorsementLines+1)))
    
    # During endorsement:
    get_stats_from_summary "$(cut -f2 -d'=' throughput.txt | cut -f1 -d' ' | head -n$duringEndorsementLines | tail -n +7 | histogram.py)" # exclude starting zeros
    throughput=$summary

    ##
    ## 'Proposal Latency'
    ##
    
    #get_stats_from_summary "$(cut -f2 -d' ' proposalLatencies.txt  | histogram.py)"
    get_stats_from_summary "$(grep -C14 'Proposal Latencies' exp_desc.txt| tail -n13)"
    proposal_latency=$summary

    ##
    ## 'Broadcast Latency'
    ##
    
    #get_stats_from_summary "$(cut -f2 -d' ' broadcastLatencies.txt  | histogram.py)"
    get_stats_from_summary "$(grep -C14 'Broadcast Latencies' exp_desc.txt| tail -n13)"
    broadcast_latency=$summary 

    ##
    ## 'Commit Latency'
    ##
    
    #get_stats_from_summary "$(cut -f2 -d' ' commitLatencies.txt  | histogram.py)"
    get_stats_from_summary "$(grep -C14 'Commit Latencies' exp_desc.txt| tail -n13)"
    commit_latency=$summary 

    ##
    ## 'Commit queue'
    ##
    commit_queue_length="$(cut -f8 -d' ' commitQueueLen.txt | sort -rn | head -n1)" 

    ##
    ## 'Broadcast queue'
    ##
   broadcast_queue_length="$(cut -f8 -d' ' broadQueueLen.txt | sort -rn | head -n1)" 

    ##
    ## Output it finally
    ##
    echo $exp_name, \
    $input_rate \
    $effective_input, \
    $batch_size \
    $num_endorsers \
    $num_channels, \
    $writer_waiting_times, \
    $blocking_readers, \
    $acquiring_lock_per_min, \
    $acquiring_lock_duration, \
    $throughput, \
    $proposal_latency, \
    $broadcast_latency, \
    $commit_latency, \
    $commit_queue_length, \
    $broadcast_queue_length

    popd # exp${EXP_NUM}_good/
}

function generate_report() {
    pushd exp${EXP_NUM}_good/
    
    pushd logs/
    for i in peer{0..7} orderer0 kafka-zookeeper; do
        pushd $i
        unzip -o data.zip
        popd
    done
    popd # logs/

cat >> exp_desc.txt <<- ENDORSEMENT_TIMES
Endorsement times:
-------------------------------------------------------------------------------

Start time: $(head -n1 proposalLatencies.txt | cut -f1 -d' ')
Time time: $(tail -n1 proposalLatencies.txt | cut -f1 -d' ')

ENDORSEMENT_TIMES
    
    grep -v "Rlock" logs/peer2/ledgerLocksCommits.log > tmp.csv
    cp ../getWaitingTimes.js .
    nodejs getWaitingTimes.js > tmp.txt
    cp tmp.txt Time-ActiveReaders-WriterWaitingTimes.txt
    
    ##
    ## Writer Waiting Times
    ##
    
    # Get number of lines in tmp.txt during endorsement period. Bash is awesome. :')
    duringEndorsementLines=$(awk -v x="$(tail -n1 proposalLatencies.txt | cut -f1 -d' ')" '$1 < x' tmp.txt | wc -l)
    afterEndorsementLines=$(awk -v x="$(tail -n1 proposalLatencies.txt | cut -f1 -d' ')" '$1 > x' tmp.txt | wc -l)
    cat >> exp_desc.txt <<- WRITER_WAITING_TIMES
Writer waiting times:
-------------------------------------------------------------------------------

1. During endorsement:

$(cut -f3 -d' ' tmp.txt | head -n$duringEndorsementLines | histogram.py)

2. After endorsement:

$(cut -f3 -d' ' tmp.txt | tail -n$afterEndorsementLines | histogram.py)
    
WRITER_WAITING_TIMES
    
    ##
    ## 'Acquiring Lock' vs Minute
    ##
    
    cat >> exp_desc.txt <<-ACQUIRING_LOCK_ATTEMPTS
    
Acquiring Lock vs Minute
-------------------------------------------------------------------------------

$(grep -r "Acquiring Loc" logs/peer2/ledgerLocksCommits.log | cut -f 2 -d':' | uniq -c | awk 'BEGIN{printf "MINUTE | ATTEMPS\n----------------\n"};{printf "%6s | %s\n",$2,$1}')
    
ACQUIRING_LOCK_ATTEMPTS
    
    ##
    ## Throughputs
    ##
    
    proposalStartTimeUTC=$(head -n1 proposalLatencies.txt | cut -f1 -d' ')
    proposalEndTimeUTC=$(tail -n1 proposalLatencies.txt | cut -f1 -d' ')
    
    # throughput.txt stuff is in IST
    proposalStartTimeIST=$(TZ="Asia/Kolkata" date --rfc-3339='s' -d $proposalStartTimeUTC | tr ' ' 'T')
    proposalEndTimeIST=$(TZ="Asia/Kolkata" date --rfc-3339='s' -d $proposalEndTimeUTC | tr ' ' 'T')
    
    duringEndorsementLines=$(awk -v s="$proposalStartTimeIST" -v e="$proposalEndTimeIST" 's <= $1 && $1 <= e' throughput.txt | wc -l)
    afterEndorsementLines=$(awk -v e="$proposalEndTimeIST" 'e <= $1' throughput.txt | wc -l)

    numProposals=$(wc -l proposalLatencies.txt | awk '{print $1}')
    numBroadcasts=$(wc -l broadcastLatencies.txt | awk '{print $1}')

    effectiveProposalRate=$((numProposals/(duringEndorsementLines+1)))
    effectiveBroadcastRate=$((numBroadcasts/(duringEndorsementLines+1)))
    
cat >> exp_desc.txt <<- THROUGHPUTS
Throughputs:
-------------------------------------------------------------------------------

0. Effective Input:

Proposals: $effectiveProposalRate
Broadcasts: $effectiveBroadcastRate

1. During endorsement:

$(cut -f2 -d'=' throughput.txt | cut -f1 -d' ' | head -n$duringEndorsementLines | histogram.py)

2. After endorsement:

$(cut -f2 -d'=' throughput.txt | cut -f1 -d' ' | tail -n$afterEndorsementLines | histogram.py)
    
THROUGHPUTS

##
## 'Proposal Latency'
##

cat >> exp_desc.txt <<-PROPOSAL_LATENCIES

Proposal Latencies
-------------------------------------------------------------------------------
$(grep -v "1$" proposalLatencies.txt | cut -f2 -d' ' | histogram.py)
    
PROPOSAL_LATENCIES

##
## 'Broadcast Latency'
##

cat >> exp_desc.txt <<-BROADCAST_LATENCIES

Broadcast Latencies
-------------------------------------------------------------------------------
$(grep -v "1$" broadcastLatencies.txt | cut -f2 -d' ' | histogram.py)
    
BROADCAST_LATENCIES

##
## 'Commit Latency'
##

cat >> exp_desc.txt <<-COMMIT_LATENCIES

Commit Latencies
-------------------------------------------------------------------------------
$(grep -v "1$" commitLatencies.txt | cut -f2 -d' ' | histogram.py)
    
COMMIT_LATENCIES

awk '$8 > a[$1" "$2" "$3" "$4" "$5" "$6" "$7] { a[$1" "$2" "$3" "$4" "$5" "$6" "$7]=$8 } END { for(k in a) print k" "a[k]}' commitQueueLen.txt| sort -n -k5 > commitQueueLenPerSec.txt
awk '$8 > a[$1" "$2" "$3" "$4" "$5" "$6" "$7] { a[$1" "$2" "$3" "$4" "$5" "$6" "$7]=$9 } END { for(k in a) print k" "a[k]}' broadQueueLen.txt| sort -n -k5 > broadcastQueueLenPerSec.txt

    popd # exp${EXP_NUM}_good/
}

GENERATE_EXCEL=0
ONLY_GENERATE=0
EXP_NUM=NULL
OPTARG=0
while getopts ":e:gx" opt; do
    case $opt in
    	e)
#	  echo "-e was triggered! $OPTARG" >&2
          EXP_NUM=$OPTARG
	  ;;
	x)
	  GENERATE_EXCEL=1
	  ;;
        g)
          ONLY_GENERATE=1
          ;;
	\?)
	  echo "Invalid option: -$OPTARG" >&2
          exit 1
	  ;;
        :)
          echo "Option -$OPTARG requires a paramter" >&2
          exit 1
          ;;
    esac
done

if [ $GENERATE_EXCEL -eq 1 ]; then
    generate_excel_row
elif [ $ONLY_GENERATE -eq 0 ]; then
    fetch
    generate_report
else
    generate_report
fi


# Max queue length per second - $8 is for commit queuelength, $9 for broadcast queuelength
# awk '$8 > a[$1" "$2" "$3" "$4" "$5" "$6" "$7] { a[$1" "$2" "$3" "$4" "$5" "$6" "$7]=$8 } END { for(k in a) print k" "a[k]}' queueLen.txt| sort -n -k5
#
