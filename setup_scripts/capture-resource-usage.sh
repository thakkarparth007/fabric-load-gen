ssh s8 'ntpdate nagios; nmon -f -s 1 -c 5000' &
ssh s9 'ntpdate nagios; nmon -f -s 1 -c 5000' &

for ((i=0; i<8; i++))
do
    ssh peer$i 'nmon -f -s 1 -c 5000;
		inotifywait -d --timefmt "%d/%m/%y %H:%M:%S" -o ~/inotify.log --format "%T %w %f" -e modify /var/hyperledger/production/ledgersData/chains/chains;
		nohup go-torch --seconds 210 -r http://localhost:6060/debug/pprof/profile > profile.prof 2>profile.error &' &

#    ssh peer$i 'nmon -f -s 1 -c 5000' &
#    ssh peer$i '(nohup tcpdump -i any -q tcp and not port 22 -w tcpdump.pcap >/dev/null 2>&1) &' &
#    ssh peer$i 'inotifywait -d --timefmt "%d/%m/%y %H:%M:%S" -o ~/inotify.log --format "%T %w %f" -e modify /var/hyperledger/production/ledgersData/chains/chains/ch1' &
done

otherNodes=('orderer0' 'kafka-zookeeper')
notherNodes=2

for ((i=0; i<notherNodes; i++))
do
   ssh ${otherNodes[$i]} 'nmon -f -s 1 -c 5000' &
#   ssh ${otherNodes[$i]} 'export http_proxy=http://10.10.1.100:3138; export https_proxy=http://10.10.1.100:3138; ntpdate nagios' &
#   ssh ${otherNodes[$i]} '(nohup tcpdump -i any -q tcp and not port 22 -w tcpdump.pcap >/dev/null 2>&1) &' &
done

ssh orderer0 "inotifywait -d --timefmt '%d/%m/%y %H:%M:%S' -o ~/inotify.log --format '%T %w %f' -e modify /var/hyperledger/production/orderer/chains/;
              nohup go-torch --seconds 210 http://localhost:6060/debug/pprof/profile > profile.prof 2>profile.error &" &

wait
