(
ssh s8 'pkill nmon; zip -r data.zip *.nmon';
rm -rf logs/s8.zip;
scp s8:data.zip logs/s8.zip;
ssh s8 'rm *.nmon; rm data.zip'
) &

(
ssh s9 'pkill nmon; zip -r data.zip *.nmon';
rm -rf logs/s9.zip;
scp s9:data.zip logs/s9.zip;
ssh s9 'rm *.nmon; rm data.zip'
) &

for ((i=0; i<8; i++))
do
    ssh peer$i 'pkill nmon'
    ssh peer$i 'pkill tcpdump'
    ssh peer$i 'pkill inotifywait'
    rm -rf logs/peer$i
    mkdir -p logs/peer$i
    (ssh peer$i 'zip -r data.zip *.nmon *.pcap *.log torch.svg profile.prof' &&
     scp peer$i:data.zip logs/peer$i && 
     ssh peer$i 'rm -rf *.nmon *.pcap *.log torch.svg data.zip profile.prof') &
done

otherNodes=('orderer0' 'kafka-zookeeper')
notherNodes=2

for ((i=0; i<notherNodes; i++))
do
    ssh ${otherNodes[$i]} 'pkill nmon'
    ssh ${otherNodes[$i]} 'pkill inotifywait'
    rm -rf logs/${otherNodes[$i]}
    mkdir -p logs/${otherNodes[$i]}
    (ssh ${otherNodes[$i]} 'zip -r data.zip *.nmon *.pcap *.log torch.svg profile.prof' &&
     scp ${otherNodes[$i]}:data.zip logs/${otherNodes[$i]} &&
     ssh ${otherNodes[$i]} 'rm -rf *.nmon *.pcap *.log torch.svg data.zip profile.prof') &
done

wait
