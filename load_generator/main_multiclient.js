'use strict';

process.on('unhandledRejection', r => console.log(r));

const cluster = require('cluster');
const yaml = require('yamljs');
const seedrandom = require('seedrandom');
const path = require('path');
const fs = require('fs');

const config = yaml.load("config.yaml");
const TinyClient = require("./TinyClient");

// Get the configured workload
let workloadPath = config.workloadPath; // config.workloadPath = path to the class implementing the Load interface
if (!path.isAbsolute(workloadPath)) {
    workloadPath = path.join(__dirname, workloadPath);
}
const load = require(workloadPath);

// general config
const requestTimeout = config.requestTimeout;
const endorsementPolicy = +config.endorsementPolicy.split("/")[0];
const ORGS = config.network;
const chaincodeName = config.chaincodeName;
const chaincodeId = config.chaincodeId;
const chaincodeVersion = config.chaincodeVersion;
const globalSeed = config.globalSeed;
const orgs = Object.keys(ORGS).filter(k => k.indexOf("org") === 0);
const numPeers = Object.keys(ORGS.org1).filter(k => k.indexOf("peer") === 0).length;
const channels = config.channels.split(",");
const numChannels = channels.length;
const invokeDelayMs = 1000 / config.numLocalRequestsPerSec;

//Client.setConfigSetting('request-timeout', requestTimeout);

// Constants used for message passing
const PROPOSAL_LATENCY = 0;
const COMMIT_LATENCY = 1;
const TOTAL_LATENCY = 2;
const BROADCAST_LATENCY = 3;

/* Utility functions end */

function cleanUpWorkers() {
    for(let i in cluster.workers) {
        cluster.workers[i].send("stop");
    }
}

function startPumpingGloballyOrderedTx(loadInstance) {
    let workers = [];
    let currWorker = 0;
    for(let i in cluster.workers)
        workers.push(cluster.workers[i]);

    let timesUp = false;
    setTimeout(() => { timesUp = true; }, config.loadDurationMs);

    const period = 1000/(config.numClientsPerProcess*config.numLocalRequestsPerSec);
    function doStuff() {
        if (timesUp) {
            cleanUpWorkers();
            return;
        }

        let start = Date.now();
        for(let z = 0; z < workers.length; z++) {
            let tx = loadInstance.getNextTxProp();
            workers[z].send(tx);
        }

        let now = Date.now();
        let origDiff = period-(now-start);
        if (origDiff <= 10) {
//            process.stderr.write("WARNING: NUMBER OF CLIENTS PER PROCESS TOO HIGH. DIFF=" + origDiff + ". REDUCE NUMBER OF CLIENTS PER PROCESS!\n");
        }
        let diff = Math.max(0, origDiff);
        setTimeout(doStuff, diff);
    }
    doStuff();
}

function startWorkers(loadInstance) {
    console.log(`Spinning up ${config.numClients} clients`);
    console.log(`${invokeDelayMs}`);
    
    let deadWorkers = 0;
    let stats = [];
    let commitQueueLen = 0;
    let broadcastQueueLen = 0;
    
    let numTxPropSubmitted = 0;
    let numTxPropAccepted = 0;
    let numTxPropRejected = 0;
    let numTxValid = 0;
    let numTxInvalid = 0;

    let pendingClientReadies = config.numProcesses*config.numClientsPerProcess;
    
    const finalStatsFile = fs.createWriteStream('finalStats.txt');
    const proposalLatencyFile = fs.createWriteStream('proposalLatencies.txt');
    const broadcastLatencyFile = fs.createWriteStream('broadcastLatencies.txt');
    const commitLatencyFile = fs.createWriteStream('commitLatencies.txt');
    const totalLatencyFile = fs.createWriteStream('totalLatencies.txt');
    const broadQueueLenFile = fs.createWriteStream('broadQueueLen.txt');
    const commitQueueLenFile = fs.createWriteStream('commitQueueLen.txt');

    for(let i = 0, peerId = 0, orgId = 0, chanId = 0; i < config.numProcesses; i++) {
        console.log(`Alloting (PeerId=${peerId}) to worker#${i}`);
        let endorserOrgs = [];
        for(let j = 0; j < endorsementPolicy; j++) {
            endorserOrgs.push(orgs[(orgId+j)%orgs.length]);
        }
        cluster.fork({
            id: i,
            seed: globalSeed*(i+1),
            peerName: 'peer' + (peerId),
            orgName: endorserOrgs[0],
        ordererName: 'orderer',
            endorserOrgs: endorserOrgs,
            numPeers: numPeers,
            numClients: config.numClientsPerProcess,
            channelName: channels[chanId],
        })
        .on('message', (msg) => {
            if(load.isGloballyOrdered() && msg == "ready") {
                if(--pendingClientReadies == 0) {
                    startPumpingGloballyOrderedTx(loadInstance);
                }
                return;
            }

            let d; //= (new Date()).toString();
            switch(msg.t) {
            case PROPOSAL_LATENCY:
                proposalLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${msg.S}\n`);
                d = (new Date()).toString();
                broadQueueLenFile.write(`${d} ${++broadcastQueueLen}\n`);
                commitQueueLenFile.write(`${d} ${++commitQueueLen}\n`);
                return;
            case BROADCAST_LATENCY:
                broadcastLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${msg.S}\n`);
                broadQueueLenFile.write(`${new Date()} ${--broadcastQueueLen}\n`);
                return;
            case COMMIT_LATENCY:
                commitLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${msg.S}\n`);
                commitQueueLenFile.write(`${new Date()} ${--commitQueueLen}\n`);
                return;
            case TOTAL_LATENCY:
                totalLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${msg.S}\n`);
                return;
            default: // fallthrough
            }
            stats.push([i, msg]);
        
            numTxPropSubmitted += msg.numTxPropSubmitted;
            numTxPropAccepted += msg.numTxPropAccepted;
            numTxPropRejected += msg.numTxPropRejected;
            numTxValid += msg.numTxValid;
            numTxInvalid += msg.numTxInvalid;
        })
        .on('exit', (code, signal) => {
            deadWorkers++;
            console.log(`Worker #${i} (PeerId=${peerId}) died.`)
            
            finalStatsFile.write("Worker NumTxPropSubmitted NumTxPropAccepted NumTxPropRejected NumTxValid NumTxInvalid\n");
            if (deadWorkers == config.numProcesses) {
                stats.forEach(val => {
                    let workerId = val[0];
                    let stat = val[1];
                    
                    finalStatsFile.write(`#${workerId} ${stat.numTxPropSubmitted} ${stat.numTxPropAccepted} ${stat.numTxPropRejected} ${stat.numTxValid} ${stat.numTxInvalid}\n`)
                });
                
                finalStatsFile.write(`#Total ${numTxPropSubmitted} ${numTxPropAccepted} ${numTxPropRejected} ${numTxValid} ${numTxInvalid}\n`)
            }
        });
        
        peerId = (peerId+1) % numPeers;
        orgId = (orgId+1) % orgs.length;
        chanId = (chanId+1) % numChannels;
    } 
}

// Returns promise that is resolved when the bootstrap is done.
// uses multiple clients to speed up bootstrap
function parallelBootstrapMaster(loadInstance) {
    let resolve, reject;
    let promise = new Promise((_resolve, _reject) => {
        resolve = _resolve;
        reject = _reject;
    });

    let sent = 0;
    let rcvd = 0;
    let aliveWorkers = config[load.getName()].numBootstrapProcesses;
    function oneDone() {
        rcvd++;
        if(rcvd == sent && loadInstance.isBootstrapDone) {
            for(let i in cluster.workers) {
                cluster.workers[i].on('exit', () => {
                    console.log("Child Exited. %d left", aliveWorkers-1);
                    if (--aliveWorkers == 0) {
                        resolve();
                    }
                }).kill();
            }
        }
    }

    function startBootstrapping() {
        console.log("Starting bootstrapping");
        loadInstance.startBootstrapping(config[load.getName()].keyHigh)
        .then(() => {
            let workers = [];
            let currWorker = 0;
            for(let i in cluster.workers)
                workers.push(cluster.workers[i]);
            
            const period = 1000/(config[load.getName()].numBootstrapClientsPerProcess*config[load.getName()].numLocalBootstrapRequestsPerSec);
            function doStuff() {
                if (loadInstance.isBootstrapDone) {
                    return;
                }
            
                let start = Date.now();
                for(let z = 0; z < workers.length; z++) {
                    let tx = loadInstance.getNextBootstrapTxProp();
                    workers[z].send(tx);
                    sent++;
                }
                let now = Date.now();
                let origDiff = period-(now-start);
                if (origDiff <= 10) {
//                    process.stderr.write("WARNING: NUMBER OF CLIENTS PER PROCESS TOO HIGH. DIFF=" + origDiff + ". REDUCE NUMBER OF CLIENTS PER PROCESS!\n");
                }
                let diff = Math.max(0, period-(now-start));
                setTimeout(doStuff, diff);
            }
            doStuff();
        });
    }

    let pendingClientReadies = config[load.getName()].numBootstrapProcesses*config[load.getName()].numBootstrapClientsPerProcess;

    for(let i = 0, peerId = 0, orgId = 0, chanId = 0; i < config[load.getName()].numBootstrapProcesses; i++) {
        console.log(`Alloting (PeerId=${peerId}) to worker#${i}`);
        let endorserOrgs = [];
        for(let j = 0; j < endorsementPolicy; j++) {
            endorserOrgs.push(orgs[(orgId+j)%orgs.length]);
        }
        cluster.fork({
            id: i,
            seed: globalSeed*(i+1),
            peerName: 'peer' + (peerId),
            orgName: endorserOrgs[0],
        ordererName: 'orderer',
            endorserOrgs: endorserOrgs,
            numPeers: numPeers,
            numClients: config[load.getName()].numBootstrapClientsPerProcess,
            channelName: channels[chanId],
            bootstrap: true,
        })
        .on('message', msg => {
            if(msg == "ready") {
                if(--pendingClientReadies == 0) {
                    startBootstrapping();
                }
            } else {
                oneDone();
            }
        });
        
        peerId = (peerId+1) % numPeers;
        orgId = (orgId+1) % orgs.length;
        chanId = (chanId+1) % numChannels;
    } 

    return promise;
}

function initWorker() {
    console.log(`Worker ${process.env.id} (${process.env.orgName}, ${process.env.peerName}) started`);
     
    var oldlog = console.log.bind(console);
    var olderror = console.error.bind(console);
    var oldinfo = console.info.bind(console);
    console.debug = console.log = function() {
        //        return;
        var args = Array.prototype.slice.apply(arguments);
        oldlog.apply(console, [`[Worker #${process.env.id}]: `].concat(args));
    };
    console.error = function() {
        //        return;
        var args = Array.prototype.slice.apply(arguments);
        olderror.apply(console, [`[Worker #${process.env.id}]: `].concat(args));
    };
    console.info = function() {
        //        return;
        var args = Array.prototype.slice.apply(arguments);
        oldinfo.apply(console, [`[Worker #${process.env.id}]: `].concat(args));
    };
    
    /*
        id: i,
        seed: globalSeed*(i+1),
        peer: 'peer' + (peerId),
        org: endorserOrgs[0],
        endorserOrgs: endorserOrgs.join(","),
        numPeers: numPeers,
        numClients: config[load.getName()].numBootstrapClientsPerProcess,
        channel: channels[chanId],
    */

    let onProposalResponse  = msg => { msg.t = PROPOSAL_LATENCY; process.send(msg); }
    let onBroadcastResponse = msg => { msg.t = BROADCAST_LATENCY; process.send(msg); }
    let onCommitResponse    = msg => { msg.t = COMMIT_LATENCY; process.send(msg); }
    let onTxResponse        = msg => { msg.t = TOTAL_LATENCY; process.send(msg); }

    let clients = [];
    let initPromises = []; // for WriteRandom workload, invokeChaincode won't automatically be called after init is over.
    for(let i = 0; i < process.env.numClients; i++) {
        let client = new TinyClient({
            channelName: process.env.channelName,
            peerName: process.env.peerName,
            ordererName: process.env.ordererName,
            ORGS: ORGS,
            endorserOrgs: process.env.endorserOrgs,
            chaincodeId: chaincodeId,
            chaincodeVersion: chaincodeVersion,
        });
        let p = client.initChain().then(() => process.send("ready"));
        initPromises.push(p);

        client.onProposalResponse = onProposalResponse;
        client.onBroadcastResponse = onBroadcastResponse;
        client.onCommitResponse = onCommitResponse;
        client.onTxResponse = onTxResponse;

        clients.push(client);
    }

    return {
        clients: clients,
        initPromises: initPromises,
    };
}

/*
Main Logic: 

    if isBootstrap (always globallyOrdered, always open)
        - master sends getNextBootstrapTxProp() via message
        - client calls invokeChaincode()
        - sends to master the result
    
    if isGloballyOrdered (always open)
        - master sends getNextTxProp via message
        - client calls invokeChaincode()
        - sends to master the result and stats
    
    [ above two same from the worker's perspective, except for stats in first]
    
    if !isGloballyOrdered but isOpen:
        - each client calls invokeChaincode according to a timer
        - sends to master the stats
    
    if isClosed (never globallyOrdered)
        - each client calls invokeChaincode once previous invoke resolves.
        - sends to master the stats

    [ for the master, there are only three cases. master doesn't differentiate between 3rd and 4th]
*/
if(cluster.isMaster) {
    let loadInstance = new load(config[load.getName()]);

    let bootstrapPromise = Promise.resolve();
    if (load.requiresBootstrap()) {
        bootstrapPromise = parallelBootstrapMaster(loadInstance);
    }

    bootstrapPromise.then(() => startWorkers(loadInstance));

} else {
    let tmp = initWorker();
    let clients = tmp.clients;
    let initPromises = tmp.initPromises;

    if (load.requiresBootstrap() || load.isGloballyOrdered()) {
        let currClient = 0;
        process.on("message", (msg) => {
            if(msg == "stop") {
                for(let c of clients)
                    process.send(c.stats);
                process.exit();
            }
            
            clients[currClient].invokeChaincode(msg)
                               .catch(()=>{})  // ignore errors. Shouldn't happen normally.
            
            currClient = (currClient+1)%process.env.numClients;
        });
    } else if (config.openSystem) {
        Promise.all(initPromises).then(() => {
            let currClient = 0;

            let loadInstances = [];
            for (let i = 0; i < clients.length; i++) {
                loadInstances.push(new load(config[load.getName()]));
            }

            let prev = -invokeDelayMs;
            function doStuff() {
                let start = Date.now();
                for(let z = 0; z < clients.length; z++) {
                    let txProp = loadInstances[z].getNextTxProp();
                    clients[z].invokeChaincode(txProp);
                }

                let now = Date.now();
                let origDiff = invokeDelayMs - (now - prev);
                if(origDiff <= 10) {
//                    process.stderr.write("WARNING: NUMBER OF CLIENTS PER PROCESS TOO HIGH. DIFF=" + origDiff + ". REDUCE NUMBER OF CLIENTS PER PROCESS!\n");
                }
                let diff = Math.max(0, origDiff);
                prev = now;
                setTimeout(doStuff, diff); 
            }
            doStuff();
        });
    } else { // closed system, no global order
        Promise.all(initPromises).then(() => {
            for (let i = 0; i < clients.length; i++) {
                let loadInstance = new load(config[load.getName()]); // loadInstance for current client
                let client = clients[i];
                
                let doStuff = (err) => {
                    client.invokeChaincode(loadInstance.getNextTxProp(!!err))
                          .then(_ => doStuff()) // don't pass any error. getNextTxProp will get undefined
                          .catch(err => doStuff(err)); // if there was an error, pass it. Will be passed to getNextTxProp
                }
                doStuff();
            }
        });
    }
}
