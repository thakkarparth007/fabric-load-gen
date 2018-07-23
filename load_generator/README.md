# Load Generator for Fabric Performance Testing and Optimization

Will add more info later, for now, keep in mind to replace `./node_modules/fabric-client` with the version on Github.

Usage info about the LoadGenerator:

## Config
The load generator (the NodeJS application) reads the config.yaml for generating the load.
The following properties affect the load generation:

```
numProcesses: 10                # Number of processes to spawn
numClientsPerProcess: 8         # Number of Fabric-SDK clients per process
loadDurationMs: 240000          # Load will last 4 minutes
numLocalRequestsPerSec: 1       # Make 1 requests a second per client (in each process)
openSystem: true                # Open system = a client shouldn't wait for previous reponse before sending another request

## Information about the deployed chaincode
channels: ch1,ch2               # Don't put spaces between commas! - load will be equally distributed between ch1, ch2
chaincodeVersion: "1.0"
chaincodeName: generic-chaincode
chaincodeId: generic-chaincode

workloadPath: WriteRandom       # Path of the file exporting the Load subclass to be used for the current experiment

## Misc config
batchSize: 30                   # Block cutout size 
requestTimeout: 60000           # Number of milliseconds after which a request times out
endorsementPolicy: "4/4"        # The endorsement policy to follow. n/N means n out of N signatures required.
enableTls: true                 # Ignored. Not used currently. TLS is always off.
```

## Writing custom Load type

You can write custom workloads by implementing the Load interface. Take a look at abstract class' definition, and define the methods.

```
class Load:
    constructor(options{seed, isOpen, ...})
    static getName()            -> name of the load. Used to pass the relevant section from the config file
    isGloballyOrdered()         -> returns bool. Indicates if only the master should be used for bootstrapping
    requiresBootstrap()         -> returns bool. Indicates if this load type requires bootstrapping.
    startBootstrapping()        -> Promise resolves when it's okay to call getNextBootstrapTxProp()
    getNextBootstrapTxProp()    -> returns the proposal request to be sent in bootstrap stage
    isBootstrapDone             -> bool. whether bootstrap is over
    getNextTxProp(prevFailed)   -> prevFailed == (bool) did previous tx fail? not passed for open systems
                                   returns proposal request to be sent in regular phase
```

A couple of terms before continuing:

1. Global Ordering: [Expand]
2. Bootstrap: [Expand]
3. Stateful transactions/Cycled transactions: [Expand]

This definition allows you to write Loads that involve cycles of transactions. For example, if you want to call the following chaincode functions in the given orderer, then you can do that:

``` createCar() -> changeOwner() -> destroyCar() -> createCar() ... ```

For this you must:
    1. Set ```openSystem = false``` in the `config.yaml` file.
    2. isGloballyOrdered() should return `false`.

If these two conditions aren't met, bad things will happen.

## Running an experiment

You can run experiments individually, or in batch mode. Batch mode is simpler to config, so you'd mostly want to run experiments in batch. But I'll describe how the system works anyway:

There are four important files:
1. `batch_experiments_config/experiments.txt` - This file describes one experiment on every line. Any line having `#` is ignored. (Yes. Even if the line doesn't start with `#`. It's weird. - you can fix this by fixing the regex in `run_batch.sh` if it annoys you.)
2. `batch_experiments_config/log.txt` - This file contains the log of batch experiments. Very useful.
3. `run_batch.sh` - This file reads the `experiments.txt` file, sets variables in `config.yaml` accordingly, and also does the following:
    - According to the Database Type column in current row in `experiments.txt`, it'll set each peer to use the appropriate db, either GoLevelDB or CouchDB
    - According to the vCPU field, it'll set the vCPUs on the peer VMs and restart them if required. (Works only for 2 and 4 vCPUs. It's been hardcoded in `set_vcpu.sh`).
    - It changes the `create-join-install-parallel.sh` file to use either WriteRandom (generic-chaincode) or ReadWrite (readwrite-chaincode).
    - Calls `run.sh`
4. `run.sh` - This works on an individual experiment level. It's pretty old, don't use this directly unless you're figuring out what it does. It does the following:
    - Creates genesis block and crypto material and sends to all peers _if_ the batch size setting has changed.
    - Restarts the network (restart peers etc, create all channels, install chaincode, instantiate, query to pull up containers etc)
    - Starts capturing resource usage, and profile of peers
    - Starts fetch-block
    - Starts load generator
    - Kills load generator after `loadDurationMs` setting of the config. (Keep the bootstrap time in mind while setting `loadDurationMs`)
    - Stops resource monitoring, gets all the data from all hosts, packs all the data into a zip file of correct name (e.g. `exp_good_314.zip`), and pushes off to s5. (see what `stopAndPack.sh` does)

Other files are described below. A lot of these assume that there are 4 orgs, 2 peers in each org, single orderer, single kafka-zookeeper etc. So basically if you want to modify the 'infrastructure', you've to definitely modify these. You'll also have to modify other scripts that ssh into the peers and/or orderer:
1. **Setup Scripts**
    - `create-gensis-block.sh`: create the gensis block
    - `start-network-parallel.sh`: restarts the peer, orderer etc
    - `create-channel-conf.sh`: creates channel.tx file for a given channel config
    - `create-join-install-parallel.sh`: creates a channel with given name and endorsement policy
    - `capture-resource-usage.sh`: starts nmon and inotify on all VMs, and profile on all peers and maybe a bunch of other things.
    - `stop-capture-resource-usage.sh`: stops the monitoring, gets all the data to nagios
2. **Data Processing scripts**
    - `fetch_new_data.sh`: [Expand]
    - `micronumbers.sh`: [Expand]
    - `nmon_numbers.sh`: [Expand]
