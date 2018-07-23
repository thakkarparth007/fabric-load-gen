#!/bin/bash
#PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -xa

npeers=8
norderers=1
nkafkazookeeper=2
echo 3 /proc/sys/vm/drop_caches

stopKafka () {
#    ssh peer0 '/root/bcnetwork/bin/rm-service.sh'
     #ssh kafka-zookeeper 'reboot'
     ssh s8 'virsh reset kafka-zookeeper'
     sleep 20
     ssh kafka-zookeeper 'docker rm -f $(docker ps -aq)';
}

startPeers () {
    for ((i=0; i<npeers; i++))
    do
        ssh peer$i '
            source ~/.bashrc;
            pkill screen;
            docker stop $(docker ps -q);
            docker rm $(docker ps -all -q);
            docker rmi $(docker images  | grep dev- | awk "{print $3}");
            rm -rf /var/hyperledger/production;
	    echo 3 > /proc/sys/vm/drop_caches;
            fabric && screen -S peer -dm ./start-peer.sh false' &
    done
    for ((i=1; i<=npeers; i++))
    do
        wait %$i
    done
}


isKafkaStopped () {
    paitence=20
    while true
    do
        running=`ssh kafka-zookeeper 'docker ps -q'`
        if [ "$running" == "" ]
        then
            echo "all services are stopped"
            break
	elif [ $paitence -le 0 ]
	then
	    ssh kafka-zookeeper reboot
	    sleep 15
	    ssh kafka-zookeeper 'docker rm -f $(docker ps -aq)' # Because docker is acting weirdly. Containers run even after reboot. ?_?
	else
	    paitence=$((paitence-1))
        fi
        sleep 1
    done
}

stopOrderer () {
    for ((i=0; i<norderers; i++))
    do
        ssh orderer$i '
            pkill screen;
            rm -rf /var/hyperledger/production;
	    echo 3 > /proc/sys/vm/drop_caches;' &
    done
    for ((i=1; i<=norderers; i++))
    do
        wait %$i
    done
}

startKafka () {
#    ssh peer0 '/root/bcnetwork/bin/multihost_launcher.sh'
     ssh kafka-zookeeper 'cd /root/gocode/src/github.com/hyperledger/fabric; docker-compose -f kafka-zookeeper.yaml up -d'
#    ssh peer0 'PS4='"'"'+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'"'"' /root/bcnetwork/bin/multihost_launcher.sh'
}

isKafkaStarted () {
    while true
    do
        nkafka=`ssh kafka-zookeeper 'docker ps -q | wc -l'`
        if [ "$nkafka" == "$nkafkazookeeper" ]
        then
            echo "all kafka services are started"
            break
        fi
        sleep 1
    done
}

startOrderer () {
    for ((i=0; i<norderers; i++))
    do
        ssh orderer$i '
            source ~/.bashrc;
            pkill screen;
            docker stop $(docker ps -q);
            docker rm $(docker ps -all -q);
            rm -rf /var/hyperledger/production;
	    echo 3 > /proc/sys/vm/drop_caches;
            fabric && screen -S orderer -dm ./start-orderer.sh false' &
    done
    for ((i=1; i<=norderers; i++))
    do
        wait %$i
    done
}
echo stopKafka
stopKafka

echo startPeers
startPeers

echo isKafkaStopped
isKafkaStopped

echo stopOrderer
stopOrderer

echo startKafka
startKafka

echo isKafkaStarted
isKafkaStarted

echo startOrderer
startOrderer
