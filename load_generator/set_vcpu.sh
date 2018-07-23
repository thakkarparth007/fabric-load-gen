#!/bin/bash

# s8 -> peer{2,3,6,7} kafka-zookeeper
# s9 -> peer{0,1,4,5} orderer0

DESIRED_VCPU=$1
if [[ -z "${DESIRED_VCPU// }" ]]; then
    echo "Expected single argument - number of desired vCPUs on the peers"
    exit 1;
fi

if [ $DESIRED_VCPU != "2" -a $DESIRED_VCPU != "4" ]; then
    echo "Invalid vCPU count '$DESIRED_VCPU'. Expected 2 or 4";
    exit 1;
fi

restart_required=false
for i in peer{2,3,6,7}; do
    existing_count=$(ssh s8 'virsh dumpxml '$i 2>/dev/null | egrep "<vcpu placement='static'>[0-9]+" | egrep -o "[0-9]+")
    if [ $existing_count != $DESIRED_VCPU ]; then
        restart_required=true;
	ssh s8 "virsh dumpxml $i 2>/dev/null | sed \"s/<vcpu placement='static'>$existing_count/<vcpu placement='static'>$DESIRED_VCPU/\" > ~/virsh_dump_$i.xml;
	        virsh define ~/virsh_dump_$i.xml;
		virsh shutdown $i;
		sleep 20;
		virsh start $i;
		sleep 20;" &
    fi
done

for i in peer{0,1,4,5}; do
    existing_count=$(ssh s9 'virsh dumpxml '$i 2>/dev/null | egrep "<vcpu placement='static'>[0-9]+" | egrep -o "[0-9]+")
    if [ $existing_count != $DESIRED_VCPU ]; then
        restart_required=true;
	ssh s9 "virsh dumpxml $i 2>/dev/null | sed \"s/<vcpu placement='static'>$existing_count/<vcpu placement='static'>$DESIRED_VCPU/\" > ~/virsh_dump_$i.xml;
	        virsh define ~/virsh_dump_$i.xml;
		virsh shutdown $i;
		sleep 20;
		virsh start $i;
		sleep 20;" &
    fi
done

wait;

if [ $restart_required != "true" ]; then
    echo "No changes to vCPU";
    exit 0;
fi

ssh s8 'virsh list';
ssh s9 'virsh list';

