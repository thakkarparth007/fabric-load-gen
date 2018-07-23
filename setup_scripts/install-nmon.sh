for ((i=0; i<8; i++))
do
	ssh peer$i 'apt-get install nmon -y'
done
