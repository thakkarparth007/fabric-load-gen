A couple of random points that come to my head that'll help you:
1. We have two peers per org assumed in the setup scripts. You'll need to modify those if you want to have more peers per org.
2. Important files:

**Important files (In decreasing order of importance):**

**Load generator execution:**

1. **run_batch.sh**  -> runs a group of experiments by reading through 'batch_experiments/experiments.txt' file. You'll mostly be dealing with this.
2. **batch_experiments/experiments.txt** -> specifies one experiment per line. Super useful once you're used to the setup. Last column (can have spaces, because it isn't parsed) in the row is like a tag/comments for the experiment. Useful way to identify experiments. You can also specify bash commands to be run in it. This is useful when you want to checkout some version of Fabric. Or do anything you'd like before running an experiment or a group of them.
3. **batch_experiments/log.txt** -> run_batch.sh writes logs to this file. Will be useful if you want to see if an experiment failed.
4. **run.sh** -> runs a single experiment, reading config from config.yaml. You won't deal with it directly after a point.

**Load generator code:**
1. **main_multiclient.js**: The orchestrator. Reads config.yaml, fires up a bunch of processes, each having a bunch of workers. Relevant config params are "numProcesses", "numClientsPerProcess" and "numLocalRequestsPerSec". Keep the last one as "1" unless you want to modify that. Your total load per second will be "numProcesses * numClientsPerProcess * numLocalRequestsPerSec transactions/sec". Each worker is a TinyClient.
2. **TinyClient.js**: Used be main_multiclient.js. Handles sending of transaction to peer, orderer and listens for events from committer. This guy gets assigned a main peer and orderer by main_multiclient.js. Based on the endorsement policy (say 3/4) it'll use the next 3 peers to send endorsement-requests to. It'll listen to the allotted peer only for transaction events.
3. **Load.js** -> the interface every load should implement.
4. **loads folder** (or something like that, not sure of the name) -> contains WriteRandom and ReadWrite workloads, client side. Useful to see how they work.

**Setup scripts**:
1. **start-network-parallel.sh:** Starts the network, launches peer processes, orderer processes, and the kafka
2. **create-join-install-parallel.sh:** Creates the channels, joins peers to them, installs chaincode, instantiates chaincode.
3. **create-channel-conf.sh** and **create-genesis-block.sh**: uses configtxgen to generate channel configs and gensis block. They use some .conf file, I forgot the name of that. But that'll have stuff for block size configuration etc. You'll probably want to play with that. The experiments.txt has a parameter that lets you set the "number of transactions in a block" setting of this conf file, but if you want to play with "recommended block size in MB", then you'll have to do that manually, or modify run_batch.sh to do that for you.

Results:
Each experiment when completed will have an exp_desc.txt file. It'll be a summary of the entire experiment. Don't rely on the "throughput" section mentioned here if you're using CouchDB as the database. For leveldb the numbers here should be good. Other files have the full details.

In the data_processing folder, there are two scripts: macronumbers.sh and micronumbers.sh. These files look at the logs obtained from peers and processes the logs for information. Macronumbers are numbers by focusing on the network as a whole. Micronumbers are numbers within the peer. You'll mostly not be interested in these, unless you're processing the priority in the peer. In that case you'll have to add the logs yourself.
These files use a lot of text processing using awk/sed/grep.
