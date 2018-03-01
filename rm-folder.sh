start=$1
end=$2

for ((i=start; i<=end; i++))
do
	rm -rf exp_good_$i.zip
done
