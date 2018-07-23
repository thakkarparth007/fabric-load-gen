'use strict';

/*
    The code is brittle, meant for only one time use.
    Basically it reads channel config from config.yaml,
    instantiates a transaction. Org and Peer is hardcoded.
    Endorsement policy is also hardcoded.

    To upgrade, modify the 'version' in config.yaml, and
    pass '--upgrade'
*/

const cluster = require('cluster');
const yaml = require('yamljs');

const config = yaml.load(__dirname + "/config.yaml");

const requestTimeout = config.requestTimeout;
const ORGS = config.network;
const channelName = config.channelName;
const chaincodeName = config.chaincodeName;
const chaincodeId = config.chaincodeId;
const chaincodeVersion = config.chaincodeVersion;
const chaincodePath = "github.com/benchmarker";

var path = require('path');
var os = require('os');
var fs = require('fs');
var util = require('util');

var Client = require('fabric-client');
var EventHub = require('fabric-client/lib/EventHub.js');

var tx_id = null;
var the_user = null;
Client.setConfigSetting('request-timeout', requestTimeout);

var targets = [],
    eventhubs = [];
var pass_results = null;

var client,
    chain,
    orgName,
    cryptoSuite;

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
	var keyPath = path.join(__dirname, util.format('./fixtures/channel/crypto-config/peerOrganizations/%s.example.com/users/Admin@%s.example.com/keystore', userOrg, userOrg));
	var keyPEM = Buffer.from(readAllFiles(keyPath)[0]).toString();
	var certPath = path.join(__dirname, util.format('./fixtures/channel/crypto-config/peerOrganizations/%s.example.com/users/Admin@%s.example.com/signcerts', userOrg, userOrg));
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
    client = new Client();
    chain = client.newChannel(channelName);

    orgName = ORGS[userOrg].name;
    cryptoSuite = client.newCryptoSuite();
    cryptoSuite.setCryptoKeyStore(client.newCryptoKeyStore({path: storePathForOrg(orgName)}));
    client.setCryptoSuite(cryptoSuite);

    var caRootsPath = ORGS.orderer.tls_cacerts;
    let data = fs.readFileSync(path.join(__dirname, caRootsPath));
    let caroots = Buffer.from(data).toString();

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

        // set up the chain to use each org's 'peer#{env.peer}' for
        // both requests and events
        for (let key in ORGS) {
            if (ORGS.hasOwnProperty(key) && typeof ORGS[key][myPeer] !== 'undefined') {
                let data = fs.readFileSync(path.join(__dirname, ORGS[key][myPeer]['tls_cacerts']));
                let peer = client.newPeer(
                    ORGS[key][myPeer].requests,
                    {
                       //pem: Buffer.from(data).toString(),
                       //'ssl-target-name-override': ORGS[key][myPeer]['server-hostname']
                    }
                );
                chain.addPeer(peer);
            }
        }

        // an event listener can only register with a peer in its own org
        //let data = fs.readFileSync(path.join(__dirname, ORGS[userOrg][myPeer]['tls_cacerts']));
        let eh = new EventHub(client);
        eh.setPeerAddr(
            ORGS[userOrg][myPeer].events,
            {
                //pem: Buffer.from(data).toString(),
                //'ssl-target-name-override': ORGS[userOrg][myPeer]['server-hostname']
            }
        );
        eh.connect();
        //eventhubs.push(eh);

        return chain.initialize();

    }, (err) => {
        console.error('Failed to enroll user \'admin\'. ' + err);
        throw new Error('Failed to enroll user \'admin\'. ' + err);
    });
}

function instantiateChaincode(userOrg, upgrade){
    tx_id = client.newTransactionID(the_user);
    
    var request = {
		chaincodePath: chaincodePath,
		chaincodeId: chaincodeId,
		chaincodeVersion: chaincodeVersion,
		fcn: 'init',
		args: [],//['a', '100', 'b', '200'],
		txId: tx_id,
		// use this to demonstrate the following policy:
		// 'if signed by org1 admin, then that's the only signature required,
		// but if that signature is missing, then the policy can also be fulfilled
		// when members (non-admin) from both orgs signed'
		'endorsement-policy': {
			identities: [
				{ role: { name: 'member', mspId: ORGS['org1'].mspid }},
				{ role: { name: 'member', mspId: ORGS['org2'].mspid }},
				{ role: { name: 'admin', mspId: ORGS['org1'].mspid }}
			],
			policy: {
				'1-of': [
					{ 'signed-by': 2},
					{ '2-of': [{ 'signed-by': 0}, { 'signed-by': 1 }]}
				]
			}
		}
	};

    let promise;
	if(upgrade) {
		// use this call to test the transient map support during chaincode instantiation
		request.transientMap = { 'test': 'transientValue' };
        promise = chain.sendUpgradeProposal(request);
	} else {
        promise = chain.sendInstantiateProposal(request);
    }
    
    return promise.then(pass_results => {
        var proposalResponses = pass_results[0];

        var proposal = pass_results[1];
        var header   = pass_results[2];
        var goodCount = 0;
        for(var i in proposalResponses) {
            let one_good = false;
            let proposal_response = proposalResponses[i];
            if( proposal_response.response && proposal_response.response.status === 200) {
                console.log('transaction proposal has response status of good');
                one_good = chain.verifyProposalResponse(proposal_response);
                if(one_good) {
                    console.log(' transaction proposal signature and endorser are valid');
                    goodCount++;
                }
            } else {
                //console.error('transaction proposal was bad');
            }
            //all_good = all_good & one_good;
        }

        var all_good = goodCount >= +config.endorsementPolicy.split("/")[0];        
        if (all_good) {
            // check all the read/write sets to see if the same, verify that each peer
            // got the same results on the proposal
            all_good = chain.compareProposalResponseResults(proposalResponses);
            console.log('compareProposalResponseResults exection did not throw an error');
            if(all_good){
                console.log(' All proposals have a matching read/writes sets');
            }
            else {
                console.error(' All proposals do not have matching read/write sets');
            }
        }
        if (all_good) {
            // check to see if all the results match
            console.log(util.format('Successfully sent Proposal and received ProposalResponse: Status - %s, message - "%s", metadata - "%s", endorsement signature: %s', proposalResponses[0].response.status));//, proposalResponses[0].response.message, proposalResponses[0].response.payload, proposalResponses[0].endorsement.signature));
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
                    let handle = setTimeout(reject, 120000);

                    eh.registerTxEvent(deployId.toString(),
                        (tx, code) => {
                            clearTimeout(handle);
                            eh.unregisterTxEvent(deployId);

                            if (code !== 'VALID') {
                                console.error('The balance transfer transaction was invalid, code = ' + code);
                                reject();
                            } else {
                                console.log('The balance transfer transaction has been committed on peer '+ eh.ep._endpoint.addr);
                                resolve();
                            }
                        },
                        (err) => {
                            clearTimeout(handle);
                            console.log('Successfully received notification of the event call back being cancelled for '+ deployId);
                            resolve();
                        }
                    );
                });

                eventPromises.push(txPromise);
            });

            var sendPromise = chain.sendTransaction(request);
            return Promise.all([sendPromise].concat(eventPromises))
            .then((results) => {

                console.debug(' event promise all complete and testing complete');
                return results[0]; // the first returned value is from the 'sendPromise' which is from the 'sendTransaction()' call

            }).catch((err) => {

                console.log(err);
                console.error('Failed to send transaction and get notifications within the timeout period.');
                throw new Error('Failed to send transaction and get notifications within the timeout period.');

            });

        } else {
            console.error('Failed to send Proposal or receive valid response. Response null or status is not 200. exiting...');
            throw new Error('Failed to send Proposal or receive valid response. Response null or status is not 200. exiting...');
        }
    }, (err) => {

        console.error('Failed to send proposal due to error: ' + err.stack ? err.stack : err);
        throw new Error('Failed to send proposal due to error: ' + err.stack ? err.stack : err);

    }).then((response) => {

        if (response.status === 'SUCCESS') {
            console.log('Successfully sent transaction to the orderer.');
            console.log('******************************************************************');
            console.log('To manually run /test/integration/query.js, set the following environment variables:');
            console.log('export E2E_TX_ID='+'\''+tx_id.getTransactionID()+'\'');
            console.log('******************************************************************');
            return true;
        } else {
            console.error('Failed to order the transaction. Error code: ' + response.status);
            throw new Error('Failed to order the transaction. Error code: ' + response.status);
        }
    }, (err) => {
        console.error('Failed to send transaction due to error: ' + err.stack ? err.stack : err);
        throw new Error('Failed to send transaction due to error: ' + err.stack ? err.stack : err);

    });
};

/* Main */
var upgrade = process.argv.indexOf('--upgrade') != -1;
process.env.peer = 'peer1';
initChain('org1').then(() => instantiateChaincode('org1', upgrade));
