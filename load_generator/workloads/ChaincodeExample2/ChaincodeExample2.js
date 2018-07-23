/*
The ChaincodeExpample2Load class

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
*/

const seedrandom = require("seedrandom");

class ChaincodeExample2Load {
    constructor(config) {
        this.seed = config.seed;
        this.isOpenSystem = config.isOpenSystem;
        this.isBootstrapDone = false;
        this.prng = seedrandom(this.seed + '');
    this.config = config;
    }
    static getName() {
        return "chaincodeExample2Load";
    }
    static requiresBootstrap() {
        return false;
    }
    static isGloballyOrdered() {
        return false;
    }
    startBootstrapping() {
        throw new Error("Not implemented.");
    }
    getNextBootstrapTxProp() {
        throw new Error("Not implemented.");
    }
    getNextTxProp(prevFailed) {
        let txProp = {
            fcn: 'invoke',
            args: [this.config.accountA, this.config.accountB, '' + Math.floor(100*this.prng())],
        };
        return txProp;
    }
}

module.exports = ChaincodeExample2Load;
