/*
The abstract class Load

class Load:
    constructor(options{seed, isOpen, ...})
    static getName()            -> name of the load. Used to pass the relevant section from the config file
    static isGloballyOrdered()  -> returns bool. Indicates if only the master should be used for bootstrapping
    static requiresBootstrap()  -> returns bool. Indicates if this load type requires bootstrapping.
    startBootstrapping()        -> Promise resolves when it's okay to call getNextBootstrapTxProp()
    getNextBootstrapTxProp()    -> returns the proposal request to be sent in bootstrap stage
    isBootstrapDone             -> bool. whether bootstrap is over
    getNextTxProp(prevFailed)   -> prevFailed == (bool) did previous tx fail? not passed for open systems
                                   returns proposal request to be sent in regular phase
*/

class WriteRandomWorkload {
    constructor(config) {
        this.seed = config.seed;
        this.isOpenSystem = config.isOpenSystem;
        this.isBootstrapDone = false;
    }
    static getName() {
        return "WriteRandomWorkload";
    }
    static requiresBootstrap() {
        return false;
    }
    static isGloballyOrdered() {
        return false;
    }
    getNextTxProp() {
        return {
            fcn: 'WriteRandom',
            // WriteRandom(seed, nKeys, keySizeLo, keySizeHi, valSizeLo, valSizeHi, indexName, compKeyAttrs)
            args: [prng().toString().substr(2,4), '1', '0'.repeat(5), '9'.repeat(9), '8', '20', '',''],
        };
    }
}

module.exports = Load;
