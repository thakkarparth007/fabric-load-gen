/*
A read-write workload defines a continuous range of keys - keyLow (1) and keyHigh (depends)
Also defines length of a key. Keys are padded by zeros if numerical value is too small.  

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

const cp = require("child_process");
const readline = require("readline");
const LineByLineReader = require('line-by-line');
const fs = require("fs");

class ReadWriteWorkload {
	constructor(config) {
		this.dataFileName = config.dataFileName;
		this.keyLow = 1;
		this.keyHigh = 0; // to be set in doneBootstrapping
		this.maxKey = config.keyHigh;
		
		this.keyLength = config.keyLength;
		this.nKeysPerTx = config.nKeysPerTx;     // nKeys in a readset and writeset of a Tx. ( |readSet| = |writeSet| )
		this.deltaPercent = config.deltaPercent; // percentage of mean value size of this workload
		this.conflictRate = config.conflictRate; // in percentage
		this.blockSize = config.blockSize;       // in Tx/s
		this.nJSONPropsToUpdate = config.nJSONPropsToUpdate;
		
		this.nextKeySetState = "original";       // original/repeat
		this.lastKeySetMilestone = 0;
		this.currentKeySetStart = 0;
		this.txId = 0;
	}
	static getName() { return "ReadWrite"; }
	static isGloballyOrdered() { return true; }
	static requiresBootstrap() { return true; }

	startBootstrapping(maxLines) {
		let resolved = false;
		return new Promise((resolve, reject) => {
			this.isDone = false;
			// calculate mean of size of documents. Shell scripts rock.
			this.meanDocumentSize = +cp.execSync("awk '{s += length; nr++} END { print s/nr }' " + this.dataFileName, { encoding: "utf8" });
			this.perDocDeltaBytes = Math.round(this.meanDocumentSize * this.deltaPercent / 100 / this.nKeysPerTx);
			
			this._rl = new LineByLineReader(this.dataFileName);
			this._rl.on("line", line => {
				this._rl.pause();
				this._nextLine = line;
				if(maxLines <= this.keyHigh) { this._rl.close(); this._rl.pause(); this.isDone = true; }
				if(!resolved) { resolve(this); resolved = true; }
			}).on("close", () => {
				console.log("idk y but i'm closing");
				this.doneBootstrapping();
			}).on("error", err => {
				console.error(err);
				process.exit();
			});
		});
	}
	getNextBootstrapTxProp() {
		let obj = JSON.parse(this._nextLine);
		this.keyHigh++;
		
		for(let i = 0; i < this.nJSONPropsToUpdate; i++) {
			obj["specialJSONProp"+i] = Math.random().toString(35).substr(2, this.perDocDeltaBytes);
		}

		if (this.keyHigh < this.maxKey) this._rl.resume();
		else                            this.doneBootstrapping();
		
		return {
		   fcn: 'BootstrapInsert',
		   args: [ this._keyToString(this.keyHigh), JSON.stringify(obj) }
		};
	}
	doneBootstrapping() {
		this.isDone = true;
		this._rl.close();
	}
	getNextTxProp() {
		let data = {};
		let keySetStart = this._getNextKeySetStart();
		for(let i = 0; i < this.nKeysPerTx; i++) {
			let key = (this.currentKeySetStart+i)%this.keyHigh+1;
			data[this._keyToString(key)] = this._createUpdateCommandForKey(key);
		}
		data["_txId"] = this.txId++;
		data["_txPropStart"] = (new Date()).toString()

		return {
                    fcn: "Update",
		    args: [JSON.stringify(data)],
		};
	}
	
	//
	// private methods
	//
	
	_keyToString(key) {
		var strKey = ""+key;
		var padding = "0".repeat(this.keyLength-strKey.length);
		return padding+strKey;
	}
	_createUpdateCommandForKey(key) {
		let cmds = [];
		for(let i = 0; i < this.nJSONPropsToUpdate; i++) {
			cmds.push({
				//"cmd": "update",
				"propName": "specialJSONProp"+i,
				"propValue": Math.random().toString(35).substr(2, this.perDocDeltaBytes),
			});
		}
		return cmds;
	}
	_getNextKeySetStart() {
		if(this.nextKeySetState == "original") {
			this.currentKeySetStart += this.nKeysPerTx;
			let diff = (this.currentKeySetStart - this.lastKeySetMilestone + this.keyHigh) % this.keyHigh + 1;
			if(diff >= (1-this.conflictRate/100)*this.blockSize && this.conflictRate) {
				console.log("Original -> Duplicate", this.currentKeySetStart, this.lastKeySetMilestone);
				this.nextKeySetState = "repeat";
				this.currentKeySetStart = this.lastKeySetMilestone;
			}
			if(this.currentKeySetStart > this.keyHigh) {
				this.currentKeySetStart -= this.keyHigh;
			}
			return this.currentKeySetStart;
		} else {
			this.currentKeySetStart += this.nKeysPerTx;
			let diff = (this.currentKeySetStart - this.lastKeySetMilestone + this.keyHigh) % this.keyHigh + 1;
			if(diff >= this.conflictRate/100*this.blockSize) {
				console.log("Duplicate -> Original", this.currentKeySetStart, this.lastKeySetMilestone);
				this.nextKeySetState = "original";
				this.currentKeySetStart = (this.lastKeySetMilestone+(1-this.conflictRate/100)*this.blockSize+this.nKeysPerTx+1)%this.keyHigh + 1;
				this.lastKeySetMilestone = this.currentKeySetStart;
			}
			if(this.currentKeySetStart > this.keyHigh) {
				this.currentKeySetStart -= this.keyHigh;
			}
			return this.currentKeySetStart;
		}
	}
}

exports.ReadWriteWorkload = ReadWriteWorkload;
