#!/bin/bash

# Modify this to pull whatever branch/commit you want.
# Also modify the remote's address

for i in peer{0..7}; do
    ssh $i 'export http_proxy=http://10.10.1.100:3138
            export https_proxy=http://10.10.1.100:3138
            fabric;
            git pull github_private_https experimental_modifications
            make peer' &
done

ssh orderer0 'export http_proxy=http://10.10.1.100:3138
            export https_proxy=http://10.10.1.100:3138
            fabric;
            git pull github_private_https experimental_modifications
            make orderer' &

wait
echo "Done"
