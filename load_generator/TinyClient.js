const path = require('path');
const os = require('os');
const util = require('util');
const fs = require('fs');

const Client = require('fabric-client');
const EventHub = require('fabric-client/lib/EventHub.js');

/* Utility functions */
const tempdir = path.join(os.tmpdir(), 'hfc');
const KVS = path.join(tempdir, 'hfc-test-kvs');
const storePathForOrg = function(org) {
    return KVS + '_' + org;
};

let ORGS = {};

function readAllFiles(dir) {
    var files = fs.readdirSync(dir);
    var certs = [];
    files.forEach((file_name) => {
        let file_path = path.join(dir,file_name);
        //console.log(' looking at file ::'+file_path);
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
    
    var cryptoSuite = Client.newCryptoSuite();
    if (userOrg) {
        cryptoSuite.setCryptoKeyStore(Client.newCryptoKeyStore({path: storePathForOrg(ORGS[userOrg].name)}));
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

// reuse event hubs per process.
// with too many clients (300-400) a lot of gRPC
// connections start getting dropped.
let eventHubs = {};

class TinyClient {
    /*
        options: {
            channelName
            peerName
            ordererName
            ORGS
            endorserOrgs
            chaincodeId
            chaincodeVersion
        }
    */
    constructor(options) {
        this.peerName = options.peerName;
        this.ORGS = ORGS = options.ORGS;
        this.endorserOrgs = options.endorserOrgs.split(",");
        this.orgName = this.endorserOrgs[0]
        this.chaincodeId = options.chaincodeId;
        this.chaincodeVersion = options.chaincodeVersion;

        this.client = new Client();
        this.chain = this.client.newChannel(options.channelName);
        
        let cryptoSuite = Client.newCryptoSuite();
        cryptoSuite.setCryptoKeyStore(Client.newCryptoKeyStore({
            path: storePathForOrg(this.orgName)
        }));
        this.client.setCryptoSuite(cryptoSuite);
        
        this.chain.addOrderer(this.client.newOrderer(this.ORGS[options.ordererName].url, {})); 
        
        this.stats = {
            numTxPropSubmitted : 0,
            numTxPropAccepted : 0,
            numTxPropRejected : 0,
            numTxValid : 0,
            numTxInvalid : 0,
        };        
    }
    initChain() {
        return Client.newDefaultKeyValueStore({
            path: storePathForOrg(this.orgName)
        })
        .then(store => {
            this.client.setStateStore(store);
            return getAdmin(this.client, this.orgName);
        })
        .then(admin => {
            console.log('Successfully enrolled user \'admin\'');
        
            this.user = admin;
            let myPeer = this.peerName;
            
            let nPeerTotal = this.endorserOrgs.length;
            // set up the chain to use each endorserOrg's 'peer#{env.peer}' for
            // both requests and events
            let endorserOrgs = this.endorserOrgs;
            for (let key of endorserOrgs) {
                if (this.ORGS.hasOwnProperty(key) && typeof this.ORGS[key][myPeer] !== 'undefined') {
                    let peer = this.client.newPeer(this.ORGS[key][myPeer].requests,{});
                    this.chain.addPeer(peer);
                    if(nPeerTotal-- == 0) break;
                }
            }
            
            if(eventHubs[this.orgName] && eventHubs[this.orgName][myPeer]) {
                this.eventhub = eventHubs[this.orgName][myPeer];
            } else {
                this.eventhub = new EventHub(this.client);
                this.eventhub.setPeerAddr(this.ORGS[this.orgName][myPeer].events, {});
                this.eventhub.connect();
                eventHubs[this.orgName] = eventHubs[this.orgName] || {};
                eventHubs[this.orgName][myPeer] = this.eventhub;
            }
            
            return this.chain.initialize();

        }, err => {
            console.error('Failed to enroll user \'admin\'. ' + err);
            throw new Error('Failed to enroll user \'admin\'. ' + err);
        });
    }

    onProposalResponse() {
        // to be overridden by the class user if interested
    }

    onBroadcastResponse() {
        // to be overridden by the class user if interested
    }

    onCommitResponse() {
        // to be overridden by the class user if interested
    }

    onTxResponse() {
        // to be overridden by the class user if interested
    }

    _sendProposalStatus(startTime, txIdStr, status) {
        this.onProposalResponse({
            v: Date.now() - startTime,
            tId: txIdStr,
            st: startTime,
            S: status,
        });
    }

    _sendBroadcastStatus(startTime, txIdStr, status) {
        this.onBroadcastResponse({
            v: Date.now() - startTime,
            tId: txIdStr,
            st: startTime,
            S: status,
        });
    }
    
    _sendCommitStatus(startTime, txIdStr, status) {
        this.onCommitResponse({
            v: Date.now() - startTime,
            tId: txIdStr,
            st: startTime,
            S: status,
        });
    }
    
    _sendTxStatus(startTime, txIdStr, status) {
        this.onTxResponse({
            v: Date.now() - startTime,
            tId: txIdStr,
            st: startTime,
            S: status,
        });
    }

    _getTxEventPromise(txId) {
        let resolve, reject;
        let promise = new Promise((res, rej) => {
            resolve = res;
            reject = rej;
        });

        let deployId = txId.getTransactionID();
        let handle = setTimeout(() => reject('120s timeout'), 120000);
        
        this.eventhub.registerTxEvent(deployId.toString(),
            (tx, code) => {
                clearTimeout(handle);
                this.eventhub.unregisterTxEvent(deployId);
                
                if (code !== 'VALID') {
                    reject('Invalid transaction');
                } else {
                    resolve(); // tx committed on peer
                }
            },
            err => {
                clearTimeout(handle);
                //console.log('Successfully received notification of the event call back being cancelled for '+ deployId);
                resolve();
            }
        );
    }

    invokeChaincode(proposalRequest, customTxId) {
        let txId = this.client.newTransactionID(this.user);
        let txIdStr = txId.getTransactionID().substr(0,6);
        
        proposalRequest.chaincodeId = this.chaincodeId;
        proposalRequest.chaincodeVersion = this.chaincodeVersion;
        proposalRequest.txId = txId;

        if(customTxId) {
            txIdStr = customTxId;
        }

        let txStartDate = new Date();
        let broadStartTime; // will be set later
        let commitStartTime; // will be set later
        
        /*
            FLOW (high level)
            ===================================

            1. Send the transaction proposal
                - if there's an error in sending the proposal throw 'Failed to send proposal due to error: ${err}', and thus rejecting promise returned by invokeChaincode
            
            2. THEN once that is received, check the endorsements, did everyone endorse correctly?
                - if enough proposals are not obtained, throw 'Not enough endorsements', and thus rejecting promise returned by invokeChaincode
            
            3. THEN:
                3.1 register to the event hub for checking the transaction's status (along with 120s timeout) - getTxEventPromise()
                3.2 send the transaction to the orderer (sendPromise)
            
            4. THEN (once both sendPromise and txPromise resolve via Promise.all()):
                4.1 chillax.
        */
        return this.chain.sendTransactionProposal(proposalRequest)
        .then(passResults => {
            this.stats.numTxPropSubmitted++;
            
            let proposalResponses = passResults[0];
            let proposal = passResults[1];
            let header = passResults[2];
            let goodCount = 0;
            for(let i = 0; i < proposalResponses.length; i++) {
                let proposalResponse = proposalResponses[i];
                goodCount += (proposalResponse && proposalResponse.response.status === 200);
            }
            
            if (goodCount < this.endorserOrgs.length) {
                this.stats.numTxPropRejected++;
                this._sendProposalStatus(txStartDate, txIdStr, -1)
                throw new Error("Not enough endorsements");
            }

            this._sendProposalStatus(txStartDate, txIdStr, 0)
            this.stats.numTxPropAccepted++;

            return {
                proposalResponses: proposalResponses,
                proposal: proposal,
                header: header
            };
        }, err => {
            // proposal failed
            this._sendProposalStatus(txStartDate, txIdStr, -1)
            throw new Error('Failed to send proposal due to error: ', err);
        })
        .then(request => {
            let txPromise = this._getTxEventPromise(txId);

            broadStartTime = new Date();
            commitStartTime = new Date();
            let sendPromise = this.chain.sendTransaction(request).then(data => {
                this._sendBroadcastStatus(broadStartTime, txIdStr, 0);
                return data;
            }, err => {
                this._sendBroadcastStatus(broadStartTime, txIdStr, -1)
                throw err;
            });

            return txPromise;
        })
        .then(results => {
            this._sendCommitStatus(commitStartTime, txIdStr, 0);
            this._sendTxStatus(txStartDate, txIdStr, 0);
            this.stats.numTxValid++;
        }, err => {
            this._sendCommitStatus(commitStartTime, txIdStr, -1);
            this._sendTxStatus(txStartDate, txIdStr, 0);
            this.stats.numTxInvalid++;
            //console.error('Failed to send transaction and get notifications within the timeout period.');
            throw new Error(err);
        });
    }
}

module.exports = TinyClient;
