'use strict';

const cluster = require('cluster');
const yaml = require('yamljs');

const config = yaml.load("config.yaml");

const requestTimeout = config.requestTimeout;
const endorsementPolicy = +config.endorsementPolicy.split("/")[0];
const ORGS = config.network;
const channelName = config.channelName;
const chaincodeName = config.chaincodeName;
const chaincodeId = config.chaincodeId;
const chaincodeVersion = config.chaincodeVersion;
const globalSeed = config.globalSeed;

if (!config.invokeDelayMs) {
    if (!config.numLocalRequestsPerSec) {
        console.log("Invalid config. Either invokeDelayMs or numLocalRequestsPerSec required.");
        process.exit();
    }
    config.invokeDelayMs = 1000 / config.numLocalRequestsPerSec;
}

var path = require('path');
var os = require('os');
var fs = require('fs');
var util = require('util');
var seedrandom = require('seedrandom');
var prng;

var Client = require('fabric-client');
var EventHub = require('fabric-client/lib/EventHub.js');

var the_user = null;
Client.setConfigSetting('request-timeout', requestTimeout);

var targets = [],
    eventhubs = [];
var pass_results = null;

var client,
    chain,
    orgName,
    cryptoSuite;

var numTxPropSubmitted = 0,
    numTxPropAccepted = 0,
    numTxPropRejected = 0,
    numTxValid = 0,
    numTxInvalid = 0;

const PROPOSAL_LATENCY = 0;
const COMMIT_LATENCY = 1;
const TOTAL_LATENCY = 2;
const BROADCAST_LATENCY = 3;

var txProposalLatencies = {},   // Latency in getting the endorsements
    txCommitLatencies = {};	// Latency between sending endorsements from client to commit time

/* Utility functions */
function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

const tempdir = path.join(os.tmpdir(), 'hfc');
const KVS = path.join(tempdir, 'hfc-test-kvs');
const storePathForOrg = function(org) {
	return KVS + '_' + org;
};

function readAllFiles(dir) {
	var files = fs.readdirSync(dir);
	var certs = [];
	files.forEach((file_name) => {
		let file_path = path.join(dir,file_name);
		console.log(' looking at file ::'+file_path);
		let data = fs.readFileSync(file_path);
		certs.push(data);
	});
	return certs;
}

function getAdmin(client, userOrg) {
	var keyPath = path.join(__dirname, util.format('./fixtures/channel/crypto-config/peerOrganizations/%s/users/Admin@%s/msp/keystore', userOrg, userOrg));
	var keyPEM = Buffer.from(readAllFiles(keyPath)[0]).toString();
	var certPath = path.join(__dirname, util.format('./fixtures/channel/crypto-config/peerOrganizations/%s/users/Admin@%s/msp/signcerts', userOrg, userOrg));
	var certPEM = readAllFiles(certPath)[0];

	var cryptoSuite = client.newCryptoSuite();
	if (userOrg) {
		cryptoSuite.setCryptoKeyStore(client.newCryptoKeyStore({path: storePathForOrg(ORGS[userOrg].name)}));
		client.setCryptoSuite(cryptoSuite);
	}

	return Promise.resolve(client.createUser({
		username: 'peer'+userOrg+'Admin',
		mspid: ORGS[userOrg].mspid,
		cryptoContent: {
			privateKeyPEM: keyPEM.toString(),
			signedCertPEM: certPEM.toString()
		}
	}));
}

/* Utility functions end */

/* initChain and invokeChaincode functions */

function initChain(userOrg) {
    prng = seedrandom(process.env.seed + '');

    client = new Client();
    chain = client.newChannel(channelName);

    orgName = ORGS[userOrg].name;
    cryptoSuite = client.newCryptoSuite();
    cryptoSuite.setCryptoKeyStore(client.newCryptoKeyStore({path: storePathForOrg(orgName)}));
    client.setCryptoSuite(cryptoSuite);

//    var caRootsPath = ORGS.orderer.tls_cacerts;
//    let data = fs.readFileSync(path.join(__dirname, caRootsPath));
//    let caroots = Buffer.from(data).toString();

    chain.addOrderer(
        client.newOrderer(
            ORGS.orderer.url,
            {
                //pem: caroots,
                //'ssl-target-name-override': ORGS.orderer['server-hostname']
            }
        )
    );

    return Client.newDefaultKeyValueStore({
        path: storePathForOrg(orgName)
    }).then((store) => {

        client.setStateStore(store);
        return getAdmin(client, userOrg);

    }).then((admin) => {

        console.log('Successfully enrolled user \'admin\'');
        the_user = admin;
        let myPeer = process.env.peer;

	var nPeerTotal = endorsementPolicy;
        // set up the chain to use each org's 'peer#{env.peer}' for
        // both requests and events
        for (let key in ORGS) {
            if (ORGS.hasOwnProperty(key) && typeof ORGS[key][myPeer] !== 'undefined') {
//                let data = fs.readFileSync(path.join(__dirname, ORGS[key][myPeer]['tls_cacerts']));
                let peer = client.newPeer(
                    ORGS[key][myPeer].requests,
                    {
//                       pem: Buffer.from(data).toString(),
//                       'ssl-target-name-override': ORGS[key][myPeer]['server-hostname']
                    }
                );
                chain.addPeer(peer);
		if(nPeerTotal-- == 0) break;
            }
        }

        // an event listener can only register with a peer in its own org
//        let data = fs.readFileSync(path.join(__dirname, ORGS[userOrg][myPeer]['tls_cacerts']));
        let eh = new EventHub(client);
        eh.setPeerAddr(
            ORGS[userOrg][myPeer].events,
            {
//                pem: Buffer.from(data).toString(),
//                'ssl-target-name-override': ORGS[userOrg][myPeer]['server-hostname']
            }
        );
        eh.connect();
        eventhubs.push(eh);

        return chain.initialize();

    }, (err) => {
        console.error('Failed to enroll user \'admin\'. ' + err);
        throw new Error('Failed to enroll user \'admin\'. ' + err);
    });
}

function invokeChaincode(userOrg){
    let tx_id = client.newTransactionID(the_user);
    let tx_id_str = tx_id.getTransactionID();
    //utils.setConfigSetting('E2E_TX_ID', tx_id.getTransactionID());
    //console.info('setConfigSetting("E2E_TX_ID") = ', tx_id.getTransactionID());
    //console.log(util.format('Sending transaction "%s"', tx_id.getTransactionID()));

    // send proposal to endorser
    var request = {
        chaincodeId : chaincodeId,
        chaincodeVersion : chaincodeVersion,
        fcn: 'WriteRandom',
        // WriteRandom(seed, nKeys, keySizeLo, keySizeHi, valSizeLo, valSizeHi, indexName, compKeyAttrs)
        args: [prng().toString().substr(2,4), '1', '0'.repeat(5), '9'.repeat(9), '8', '20', '',''],
        txId: tx_id,
    };
    
    txProposalLatencies[tx_id_str] = new Date();
    return chain.sendTransactionProposal(request)
        .then(pass_results => {
	process.send({
	    't': PROPOSAL_LATENCY,
	    'v': Date.now() - txProposalLatencies[tx_id_str],
	    'tId': tx_id_str.substr(0,6),
	    'st': txProposalLatencies[tx_id_str], // sendtime
	});

        numTxPropSubmitted++;
        var proposalResponses = pass_results[0];

        var proposal = pass_results[1];
        var header   = pass_results[2];
        var goodCount = 0;
        for(var i in proposalResponses) {
            let one_good = false;
            let proposal_response = proposalResponses[i];
            if( proposal_response.response && proposal_response.response.status === 200) {
                //console.log('transaction proposal has response status of good');
                one_good = true;//chain.verifyProposalResponse(proposal_response);
                if(one_good) {
                    //console.log(' transaction proposal signature and endorser are valid');
                    goodCount++;
                }
            } else {
                //console.error('transaction proposal was bad');
            }
            //all_good = all_good & one_good;
        }

        var all_good = goodCount >= endorsementPolicy;//+config.endorsementPolicy.split("/")[0];        
        if (all_good) {
            // check all the read/write sets to see if the same, verify that each peer
            // got the same results on the proposal
            all_good = chain.compareProposalResponseResults(proposalResponses);
            //console.log('compareProposalResponseResults exection did not throw an error');
            if(all_good){
                //console.log(' All proposals have a matching read/writes sets');
            }
            else {
                numTxPropRejected++;
                //console.error(' All proposals do not have matching read/write sets');
            }
        }
        if (all_good) {
            numTxPropAccepted++;
            // check to see if all the results match
            //console.log(util.format('Successfully sent Proposal and received ProposalResponse: Status - %s, message - "%s", metadata - "%s", endorsement signature: %s', proposalResponses[0].response.status));//, proposalResponses[0].response.message, proposalResponses[0].response.payload, proposalResponses[0].endorsement.signature));
            var request = {
                proposalResponses: proposalResponses,
                proposal: proposal,
                header: header
            };

            // set the transaction listener and set a timeout of 30sec
            // if the transaction did not get committed within the timeout period,
            // fail the test
            var deployId = tx_id.getTransactionID();

            var eventPromises = [];
            eventhubs.forEach((eh) => {
                let txPromise = new Promise((resolve, reject) => {
                    let handle = setTimeout(reject.bind(null, '120s timeout'), 120000);

                    eh.registerTxEvent(deployId.toString(),
                        (tx, code) => {
                            clearTimeout(handle);
                            eh.unregisterTxEvent(deployId);

                            if (code !== 'VALID') {
                                //console.error('The balance transfer transaction was invalid, code = ' + code);
                                reject('Invalid transaction');
                            } else {
                                //console.log('The balance transfer transaction has been committed on peer '+ eh.ep._endpoint.addr);
                                resolve();
                            }
                        },
                        (err) => {
                            clearTimeout(handle);
                            //console.log('Successfully received notification of the event call back being cancelled for '+ deployId);
                            resolve();
                        }
                    );
                });

                eventPromises.push(txPromise);
            });

	    txCommitLatencies[tx_id_str] = new Date();
            var sendPromise = chain.sendTransaction(request).then(data => {
		process.send({
		    't': BROADCAST_LATENCY,
		    'v': Date.now() - txCommitLatencies[tx_id_str],
		    'tId': tx_id_str.substr(0,6),
		    'st': txCommitLatencies[tx_id_str], // sendtime
		});
		return data;
	    });
            return Promise.all([sendPromise].concat(eventPromises))
            .then((results) => {
		process.send({
		    't': COMMIT_LATENCY,
		    'v': Date.now() - txCommitLatencies[tx_id_str],
		    'tId': tx_id_str.substr(0,6),
		    'st': txCommitLatencies[tx_id_str], // sendtime
		});
		process.send({
		    't': TOTAL_LATENCY,
		    'v': Date.now() - txProposalLatencies[tx_id_str],
		    'tId': tx_id_str.substr(0,6),
		    'st': txProposalLatencies[tx_id_str], // sendtime
		});
		delete txCommitLatencies[tx_id_str];
		delete txProposalLatencies[tx_id_str];
                //console.debug(' event promise all complete and testing complete');
                return results[0]; // the first returned value is from the 'sendPromise' which is from the 'sendTransaction()' call

            })/*.catch((err) => {

                //console.error('Failed to send transaction and get notifications within the timeout period.');
                throw new Error('Failed to send transaction and get notifications within the timeout period.');

            })*/;

        } else {
            //console.error('Failed to send Proposal or receive valid response. Response null or status is not 200. exiting...');
            throw new Error('Failed to send Proposal or receive valid response. Response null or status is not 200. exiting...');
        }
    }, (err) => {

        //console.error('Failed to send proposal due to error: ' + err.stack ? err.stack : err);
        throw new Error('Failed to send proposal due to error: ');// + err.stack ? err.stack : err);

    }).then((response) => {
        if (response.status === 'SUCCESS') {
            numTxValid++;
            //console.log('Successfully sent transaction to the orderer.');
            //console.log('******************************************************************');
            //console.log('To manually run /test/integration/query.js, set the following environment variables:');
            //console.log('export E2E_TX_ID='+'\''+tx_id.getTransactionID()+'\'');
            //console.log('******************************************************************');
            return true;
        } else {
            //console.error('Failed to order the transaction. Error code: ' + response.status);
            throw new Error('Failed to order the transaction. Error code: ');// + response.status);
        }
    }, (err) => {
        numTxInvalid++;
        //console.error('Failed to send transaction due to error: ' + err.stack ? err.stack : err);
	process.stderr.write((err)+"\n");
        throw new Error('Failed to send transaction due to error: ');// + err.stack ? err.stack : err);

    });
};

/* Main */
if(cluster.isMaster) {
    console.log(`Spinning up ${config.numClients} clients`);
    console.log(`${config.invokeDelayMs}`);

    const orgs = Object.keys(ORGS).filter(k => k.indexOf("org") === 0);
    const numPeers = Object.keys(ORGS.org1).filter(k => k.indexOf("peer") === 0).length;

    let deadWorkers = 0;
    let stats = [];
    let commitQueueLen = 0;
    let broadcastQueueLen = 0;

    const proposalLatencyFile = fs.createWriteStream('proposalLatencies.txt');
    const broadcastLatencyFile = fs.createWriteStream('broadcastLatencies.txt');
    const commitLatencyFile = fs.createWriteStream('commitLatencies.txt');
    const totalLatencyFile = fs.createWriteStream('totalLatencies.txt');
    const queueLenFile = fs.createWriteStream('queueLen.txt');

    for(let i = 0, peerId = 0, orgId = 0; i < config.numClients; i++) {
        console.log(`Alloting (PeerId=${peerId}) to worker#${i}`);
        cluster.fork({
            id: i,
            seed: globalSeed*(i+1),
            peer: 'peer' + (peerId),
            org: orgs[orgId],
            numPeers: numPeers,
        }).on('message', (msg) => {
	    switch(msg.t) {
		case PROPOSAL_LATENCY:
		    proposalLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${i}\n`);
		    queueLenFile.write(`${new Date()} ${++commitQueueLen} ${++broadcastQueueLen} ++\n`);
		    return;
		case BROADCAST_LATENCY:
		    broadcastLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${i}\n`);
		    queueLenFile.write(`${new Date()} ${commitQueueLen} ${--broadcastQueueLen} _-\n`);
		    return;
	        case COMMIT_LATENCY:
		    commitLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${i}\n`);
		    queueLenFile.write(`${new Date()} ${--commitQueueLen} ${broadcastQueueLen} -_\n`);
		    return;
	        case TOTAL_LATENCY:
		    totalLatencyFile.write(`${msg.st} ${msg.v} ${msg.tId} ${i}\n`);
		    return;
		default: // fallthrough
	    }
            stats.push([i, msg]);

            numTxPropSubmitted += msg.NumTxPropSubmitted;
            numTxPropAccepted += msg.NumTxPropAccepted;
            numTxPropRejected += msg.NumTxPropRejected;
            numTxValid += msg.NumTxValid;
            numTxInvalid += msg.NumTxInvalid;
        }).on('exit', (code, signal) => {
            deadWorkers++;
            console.log(`Worker #${i} (PeerId=${peerId}) died.`)

            if (deadWorkers == config.numClients) {
                stats.forEach(val => {
                    let workerId = val[0];
                    let stat = val[1];

                    console.log(`Worker #${workerId} stats:`)
                    console.log("NumTxPropSubmitted: ", stat.NumTxPropSubmitted);
                    console.log("NumTxPropAccepted: ", stat.NumTxPropAccepted);
                    console.log("NumTxPropRejected: ", stat.NumTxPropRejected);
                    console.log("NumTxValid: ", stat.NumTxValid);
                    console.log("NumTxInvalid: ", stat.NumTxInvalid);
                    console.log("\n");
                });

                console.log("Overall stats:");
                console.log("NumTxPropSubmitted: ", numTxPropSubmitted);
                console.log("NumTxPropAccepted: ", numTxPropAccepted);
                console.log("NumTxPropRejected: ", numTxPropRejected);
                console.log("NumTxValid: ", numTxValid);
                console.log("NumTxInvalid: ", numTxInvalid);
            }
        });

        peerId= (peerId+1) % numPeers;
        orgId = (orgId+1) % orgs.length;
    }
} else {
    //process.exit();
    console.log(`Worker ${process.env.id} (${process.env.org}, ${process.env.peer}) started`);

    var oldlog = console.log.bind(console);
    var olderror = console.error.bind(console);
    var oldinfo = console.info.bind(console);
    console.debug = console.log = function() {
        return;
        var args = Array.prototype.slice.apply(arguments);
        oldlog.apply(console, [`[Worker #${process.env.id}]: `].concat(args));
    };
    console.error = function() {
        return;
        var args = Array.prototype.slice.apply(arguments);
        olderror.apply(console, [`[Worker #${process.env.id}]: `].concat(args));
    };
    console.info = function() {
        return;
        var args = Array.prototype.slice.apply(arguments);
        oldinfo.apply(console, [`[Worker #${process.env.id}]: `].concat(args));
    };
    
    var stopNow = false;

    initChain(process.env.org).then(() => {
        setTimeout(() => {
            console.log("Time's up. Cleaning up.");
            stopNow = true;
        }, config.loadDurationMs);

        function foo() {
            if (stopNow) {
	        if( numTxValid + numTxInvalid < numTxPropAccepted ) {
		    return setTimeout(foo, config.invokeDelayMs);
		}
                // console.log("I'm done. Quitting.");
                // console.log("Stats:");
                const stats = {
                    NumTxPropSubmitted: numTxPropSubmitted,
                    NumTxPropAccepted: numTxPropAccepted,
                    NumTxPropRejected: numTxPropRejected,
                    NumTxValid: numTxValid,
                    NumTxInvalid: numTxInvalid,
                };
                process.send(stats);
                process.exit();
            } else {
                // if system is open, don't wait for response
                if (config.openSystem) {
                    setTimeout(foo, config.invokeDelayMs);
                    invokeChaincode(process.env.org);
                } else {
                    invokeChaincode(process.env.org).then(foo);//() => setTimeout(foo, config.invokeDelayMs));;
                }
            }
        }
        foo();
    });
}
