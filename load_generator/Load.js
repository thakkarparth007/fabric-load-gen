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

class Load {
    constructor(config) {
        this.seed = config.seed;
        this.isOpenSystem = config.isOpenSystem;
        this.isBootstrapDone = false;
    }
    static getName() {
        return "Load"; // override. Will be used to pass the relevant config section here.
    }
    static requiresBootstrap() {
        return false;
    }
    static isGloballyOrdered() {
        return false;
    }
    startBootstrapping() {
        throw new Error("Not implemented. Using abstract class Load.");
    }
    getNextBootstrapTxProp() {
        throw new Error("Not implemented. Using abstract class Load.");
    }
    getNextTxProp() {
        throw new Error("Not implemented. Using abstract class Load.");
    }
}

module.exports = Load;
