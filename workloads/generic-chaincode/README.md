# Generic Chaincode Workload

The following functions are supported:

## Functions:
	- [x] ReadRandom(seed int, nKeys int, keySizeLo int, keySizeHi int)
				- Uses GetState()
	- [x] ReadSequential(start string, end string)
				- Uses GetStateByRange()
	- [x] ReadByPartialCompositeKey(indexName, attributes)
				- Uses GetStateByPartialCompositeKey()
	- [x] WriteRandom(seed, nKeys, keySizeLo, keySizeHi, valSizeLo, valSizeHi, indexName, compKeyAttrs)
				- Uses PutState() and CreateCompositeKey()
	- [x] WriteAfterReadRandom(seed, nKeys, keySizeLo, keySizeHi, valSizeLo, valSizeHi, indexName, compKeyAttrs)
				- Uses GetState(), PutState() and CreateCompositeKey()
	- [x] WriteAfterReadSequential(start, end, valSizeLo, valSizeHi, indexName, compKeyAttrs)
				- Uses GetStateByRange(), PutState() and CreateCompositeKey()
	- [x] GetHistoryForKey(seed, keySizeLo, keySizeHi)
				- Uses GetHistoryForKey()

## Useful script
The `script.sh` file handles installing, instantiating and upgrading chaincode very simple.
Directions for usage:

1. Setup the devenv mode as shown [http://blockchain-fabric.blogspot.in/2017/05/setting-up-chaincode-development.html](here)
2. Copy the files under `workloads/generic-chaincode` to `$GOROOT/src/github.com/hyperledger/fabric/examples/benchmarker`
3. Run `./script.sh install`
4. Run `./script.sh instantiate`
5. Run `./script.sh upgrade -v 1` where 1 is the new version. 

You can pass `-v` (version - required for upgrade; Defaults to 0 for install, instantiate.) and `-C` (channel name - defaults to `ch1`) options to `./script.sh`.


## A note about Invoke()
The code for `Invoke()` makes writing functions for invoke easier. You do not need to worry about argument parsing in each of the functions you write. That is handled in `Invoke()` using reflection. As of now, parameters of type `string`, `int`, `bool` and `float64` are automatically parsed. If you need special formatting, you can accept the parameter as string and parse in the function on your own. Look at any of `ReadRandom`, `ReadSequential` etc for an example.

If reflection turns out to slow down the benchmark, I'll remove it in future.
