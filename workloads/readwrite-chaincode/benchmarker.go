/*
File: benchmarker.go
Description: A chaincode to used for benchmarking Hyperledger Fabric v1
Author: Parth Thakkar
*/

package main

/*
Functions:
	- [DONE] BootstrapInsert(key, value string)
				- Uses PutState()
	- [DONE] Update(tx string)
				- Uses GetState and PutState()
*/

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
)

// BenchmarkerChaincode example simple Chaincode implementation
type BenchmarkerChaincode struct {
}

// Init initializes chaincode...NOOP as of now.
func (t *BenchmarkerChaincode) Init(stub shim.ChaincodeStubInterface) pb.Response {
	args := stub.GetStringArgs()

	if len(args) != 1 {
		return shim.Error(fmt.Sprintf("Incorrect number of arguments. Expecting 1. You gave %+v", args))
	}

	return shim.Success(nil)
}

// Invoke sets key/value and sleeps a bit
func (t *BenchmarkerChaincode) Invoke(stub shim.ChaincodeStubInterface) pb.Response {
	function, args := stub.GetFunctionAndParameters()

	switch function {
	case "Update":
		if len(args) != 1 {
			return shim.Error(fmt.Sprintf("Expected one argument for Update. Got %d", len(args)))
		}
		return t.Update(stub, args[0])
	case "BootstrapInsert":
		if len(args) != 2 {
			return shim.Error(fmt.Sprintf("Expected 2 arguments for BootstrapInsert. Got %d", len(args)))
		}
		return t.BootstrapInsert(stub, args[0], args[1])
	}

	return shim.Error("Invalid method name. 'BootstrapInsert' and 'Update' only valid.")
}

// BootstrapInsert inserts a key-value pair into the state database. Used for initialization.
func (t *BenchmarkerChaincode) BootstrapInsert(stub shim.ChaincodeStubInterface, key, value string) pb.Response {
	stub.PutState(key, []byte(value))
	return shim.Success([]byte("OK"))
}

// Update performs GetState and PutState according to readset, writeset
func (t *BenchmarkerChaincode) Update(stub shim.ChaincodeStubInterface, tx string) pb.Response {
	simStart := time.Now()
	myTx := make(map[string][]struct {
		PropName  string `json:"propName"`
		PropValue string `json:"propValue"`
	})

	json.Unmarshal([]byte(tx), &myTx)

	for key, cmds := range myTx {
		bval, err := stub.GetState(key)
		if err != nil {
			return shim.Error("Failed to perform GetState on key `" + key + "`")
		}
		kvpair := make(map[string]interface{})
		json.Unmarshal(bval, &kvpair)

		for _, cmd := range cmds {
			kvpair[cmd.PropName] = cmd.PropValue
		}
		endTime := time.Now()
		kvpair["_simTime"] = simStart.String()
		kvpair["_simDur"] = endTime.Sub(simStart).Nanoseconds()

		myJson, err := json.Marshal(kvpair)
		if err != nil {
			return shim.Error("Failed to marshal into json after update of key `" + key + "`")
		}
		err = stub.PutState(key, myJson)
		if err != nil {
			return shim.Error("Error in PutState of key `" + key + "`")
		}
	}

	return shim.Success([]byte("OK"))
}

func main() {
	err := shim.Start(new(BenchmarkerChaincode))
	if err != nil {
		fmt.Printf("Error starting Sleeper chaincode: %s", err)
	}
}
