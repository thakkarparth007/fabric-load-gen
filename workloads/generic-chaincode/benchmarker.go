/*
File: benchmarker.go
Description: A chaincode to used for benchmarking Hyperledger Fabric v1
Author: Parth Thakkar
*/

package main

/*
Functionality required:
1. only read
2. only write
3. read followed by write
amount of read and write would vary..
amount: size of the value, number of <k,v> pairs..
for these we can have differernt chaincode functions...
and need to use GetState, PutState, GetStateByRange, CreateCompositeKey and GetStateByPartialCompositeKeys, etc...
Further, to use ExecuteQuery() for couchDB we might need to use proper JSON as value so that we can use couchDB selector queries..
*/

/*
Functions:
	- [DONE] ReadRandom(seed int, nKeys int, keySizeLo int, keySizeHi int)
				- Uses GetState()
	- [DONE] ReadSequential(start string, end string)
				- Uses GetStateByRange()
	- [DONE] ReadByPartialCompositeKey(indexName, attributes)
				- Uses GetStateByPartialCompositeKey()
	- [DONE] WriteRandom(seed, nKeys, keySizeLo, keySizeHi, vSzLo, vSzHi, indexName, compKeyAttrs)
				- Uses PutState() and CreateCompositeKey()
	- [DONE] WriteAfterReadRandom(seed, nKeys, keySizeLo, keySizeHi, vSzLo, vSzHi, indexName, compKeyAttrs)
				- Uses GetState(), PutState() and CreateCompositeKey()
	- [DONE] WriteAfterReadSequential(seed, start, end, valSizeLo, valSizeHi, indexName, compKeyAttrs)
				- Uses GetStateByRange(), PutState() and CreateCompositeKey()
	- [DONE] GetHistoryForKey(seed, keySizeLo, keySizeHi)
				- Uses GetHistoryForKey()
*/

import (
	"bytes"
	"fmt"
	"math/rand"
	"reflect"
	"strconv"
	"time"

	"strings"

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

	rt := reflect.ValueOf(t)
	theFunc, ok := rt.Type().MethodByName(function)
	if !ok {
		var methods []string
		for i := 0; i < rt.NumMethod(); i++ {
			methodName := rt.Type().Method(i).Name
			if methodName != "Invoke" && methodName != "Init" {
				methods = append(methods, methodName)
			}
		}
		return shim.Error(fmt.Sprintf("Invalid method name. Supported methods: %+v (%d) methods", methods, rt.NumMethod()-2))
	}
	if theFunc.Type.NumIn() != len(args)+2 {
		return shim.Error(fmt.Sprintf("Expected %d arguments. Got %d.", theFunc.Type.NumIn()-2, len(args)))
	}
	in := make([]reflect.Value, theFunc.Type.NumIn())
	in[0] = reflect.ValueOf(t)
	in[1] = reflect.ValueOf(stub)

	for i := 2; i < theFunc.Type.NumIn(); i++ {
		t := theFunc.Type.In(i)
		arg := args[i-2]
		if t.Kind() == reflect.Int {
			x, err := strconv.Atoi(arg)
			if err != nil {
				return shim.Error(fmt.Sprintf("Expected argument#%d to be convertable to Int. Got %s.", i-2, arg))
			}
			in[i] = reflect.ValueOf(x)
		} else if t.Kind() == reflect.Bool {
			x, err := strconv.ParseBool(arg)
			if err != nil {
				return shim.Error(fmt.Sprintf("Expected argument#%d to be convertable to Bool. Got %s.", i-2, arg))
			}
			in[i] = reflect.ValueOf(x)
		} else if t.Kind() == reflect.Float64 {
			x, err := strconv.ParseFloat(arg, 64)
			if err != nil {
				return shim.Error(fmt.Sprintf("Expected argument#%d to be convertable to Float64. Got %s.", i-2, arg))
			}
			in[i] = reflect.ValueOf(x)
		} else if t.Kind() == reflect.String {
			in[i] = reflect.ValueOf(arg)
		} else {
			return shim.Error(fmt.Sprintf("Unsupported type %s in chaincode.", t.Kind()))
		}
	}

	return theFunc.Func.Call(in)[0].Interface().(pb.Response)
}

// ReadRandom reads nKeys randomly given keySizeLo and keySizeHi and the seed value.
func (t *BenchmarkerChaincode) ReadRandom(stub shim.ChaincodeStubInterface, seed, nKeys, keySizeLo, keySizeHi int) pb.Response {
	var (
		vals []Value
		km   NoopKeyMapper
	)
	keys := km.GetKeys(seed, nKeys, keySizeLo, keySizeHi)
	for _, key := range keys {
		bval, err := stub.GetState(key)
		if err != nil {
			return shim.Error(err.Error())
		}

		var val RandomStringValue
		val.SetKey(key)
		val.Parse(string(bval))
		vals = append(vals, &val)
	}
	return shim.Success([]byte(MakeJSONArray(vals)))
}

// ReadSequential reads nKeys sequentially between start and end
func (t *BenchmarkerChaincode) ReadSequential(stub shim.ChaincodeStubInterface, start, end string) pb.Response {
	var (
		vals []Value
	)

	resultsIterator, err := stub.GetStateByRange(start, end)
	if err != nil {
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}

		var val RandomStringValue
		val.SetKey(queryResponse.Key)
		val.Parse(string(queryResponse.Value))
		vals = append(vals, &val)
	}

	return shim.Success([]byte(MakeJSONArray(vals)))
}

// ReadByPartialCompositeKey reads all items belonging to a particular partial composite key
func (t *BenchmarkerChaincode) ReadByPartialCompositeKey(stub shim.ChaincodeStubInterface, indexName string, indexValues string) pb.Response {
	var (
		vals []Value
	)

	indexValuesSlice := strings.Split(indexValues, ",")
	resultsIterator, err := stub.GetStateByPartialCompositeKey(indexName+"~id", indexValuesSlice)
	if err != nil {
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	for i := 0; resultsIterator.HasNext(); i++ {
		responseRange, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}

		// get the values from the composite key
		_, compositeKeyParts, err := stub.SplitCompositeKey(responseRange.Key)
		if err != nil {
			return shim.Error(err.Error())
		}
		key := compositeKeyParts[len(compositeKeyParts)-1]

		bval, err := stub.GetState(key)
		if err != nil {
			return shim.Error(err.Error())
		}

		var val RandomStringValue
		val.SetKey(key)
		val.Parse(string(bval))
		vals = append(vals, &val)
	}

	return shim.Success([]byte(MakeJSONArray(vals)))
}

// getIndexValueSpace returns a 2D slice of strings, ith child-slice is a set of valid
// values for the ith index.
// indexValues is expected to be a string with n line for n indexes,
// each line has comma separated list of valid values for that index
func (t *BenchmarkerChaincode) getIndexValueSpace(indexValues string) [][]string {
	values := strings.Split(indexValues, "\n")
	var indexValueSpace [][]string
	for i := range values {
		indexValueSpace = append(indexValueSpace, strings.Split(values[i], ","))
	}
	return indexValueSpace
}

// updateIndex creates a composite key randomly using the indexValueSpace and indexName, and stores it.
// it does not delete previously associated composite key because the keys are generated randomly,
// so there's no way in which we can find them out.
func (t *BenchmarkerChaincode) updateIndex(stub shim.ChaincodeStubInterface, key, indexName string, indexValueSpace [][]string) error {
	if indexName == "" {
		return nil
	}

	var indexValues []string
	for _, validValues := range indexValueSpace {
		choice := rand.Intn(len(validValues))
		indexValues = append(indexValues, validValues[choice])
	}

	indexKey, err := stub.CreateCompositeKey(indexName+"~id", append(indexValues, key))
	if err != nil {
		return err
	}

	value := []byte{0x00}
	if err := stub.PutState(indexKey, value); err != nil {
		return err
	}
	fmt.Printf("Set composite key '%s' to '%s' for key '%s'\n", indexKey, value, key)

	return nil
}

// WriteRandom writes nKeys randomly given keySizeLo, keySizeHi, valSizeLo, valSizeHi and the seed value.
func (t *BenchmarkerChaincode) WriteRandom(stub shim.ChaincodeStubInterface, seed, nKeys, keySizeLo, keySizeHi, valSizeLo, valSizeHi int, indexName, indexValues string) pb.Response {
	var (
		km              NoopKeyMapper
		val             RandomStringValue
		indexValueSpace = t.getIndexValueSpace(indexValues)
	)

	val.Init(seed)
	keys := km.GetKeys(seed, nKeys, keySizeLo, keySizeHi)

	for _, key := range keys {
		val.Generate(key, valSizeLo, valSizeHi)
		fmt.Printf("WriteRandom: Putting '%s':'%s'\n", key, val.SerializeForState())

		err := stub.PutState(key, []byte(val.SerializeForState()))
		if err != nil {
			return shim.Error(err.Error())
		}
		t.updateIndex(stub, key, indexName, indexValueSpace)
	}

	return shim.Success([]byte("OK"))
}

// WriteAfterReadRandom reads nKeys randomly given keySizeLo and keySizeHi and the seed value, and updates them.
func (t *BenchmarkerChaincode) WriteAfterReadRandom(stub shim.ChaincodeStubInterface, seed, nKeys, keySizeLo, keySizeHi, valSizeLo, valSizeHi int, indexName string, indexValues string) pb.Response {
	var (
		km              NoopKeyMapper
		val             RandomStringValue
		indexValueSpace = t.getIndexValueSpace(indexValues)
	)

	val.Init(seed)
	keys := km.GetKeys(seed, nKeys, keySizeLo, keySizeHi)

	for _, key := range keys {
		// ignore the old value. We just want to call GetState
		oldVal, err := stub.GetState(key)
		if err != nil {
			return shim.Error(err.Error())
		}

		val.Generate(key, valSizeLo, valSizeHi)
		fmt.Printf("WriterAfterReadRandom: Updating '%s' from '%s' to '%s'\n", key, oldVal, val.SerializeForState())

		err = stub.PutState(key, []byte(val.SerializeForState()))
		if err != nil {
			return shim.Error(err.Error())
		}

		t.updateIndex(stub, key, indexName, indexValueSpace)
	}
	return shim.Success([]byte("OK"))
}

// WriteAfterReadSequential reads nKeys sequentially between start and end
func (t *BenchmarkerChaincode) WriteAfterReadSequential(stub shim.ChaincodeStubInterface, seed int, start, end string, valSizeLo, valSizeHi int, indexName string, indexValues string) pb.Response {
	var (
		val             RandomStringValue
		indexValueSpace = t.getIndexValueSpace(indexValues)
	)

	resultsIterator, err := stub.GetStateByRange(start, end)
	if err != nil {
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	val.Init(seed)
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}

		val.Generate(queryResponse.Key, valSizeLo, valSizeHi)
		fmt.Printf("WriterAfterReadSequential: Updating '%s' from '%s' to '%s'\n",
			queryResponse.Key,
			queryResponse.Value,
			val.SerializeForState(),
		)

		err = stub.PutState(queryResponse.Key, []byte(val.SerializeForState()))
		if err != nil {
			return shim.Error(err.Error())
		}

		t.updateIndex(stub, queryResponse.Key, indexName, indexValueSpace)
	}

	return shim.Success([]byte("OK"))
}

// GetHistoryForKey gets history of a random key given keySizeLo and keySizeHi and the seed value.
func (t *BenchmarkerChaincode) GetHistoryForKey(stub shim.ChaincodeStubInterface, seed, keySizeLo, keySizeHi int) pb.Response {
	var (
		km NoopKeyMapper
	)

	key := km.GetKeys(seed, 1, keySizeLo, keySizeHi)[0]

	resultsIterator, err := stub.GetHistoryForKey(key)
	if err != nil {
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	fmt.Printf("GetHistoryForKey: Getting history for key '%s'\n", key)

	// buffer is a JSON array containing historic values for the marble
	var buffer bytes.Buffer
	buffer.WriteString("[")

	bArrayMemberAlreadyWritten := false
	for resultsIterator.HasNext() {
		response, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}
		// Add a comma before array members, suppress it for the first array member
		if bArrayMemberAlreadyWritten == true {
			buffer.WriteString(",")
		}
		buffer.WriteString("{\"TxId\":")
		buffer.WriteString("\"")
		buffer.WriteString(response.TxId)
		buffer.WriteString("\"")

		buffer.WriteString(", \"Value\":")
		// if it was a delete operation on given key, then we need to set the
		//corresponding value null. Else, we will write the response.Value
		//as-is (as the Value itself a JSON marble)
		if response.IsDelete {
			buffer.WriteString("null")
		} else {
			buffer.WriteString(string(response.Value))
		}

		buffer.WriteString(", \"Timestamp\":")
		buffer.WriteString("\"")
		buffer.WriteString(time.Unix(response.Timestamp.Seconds, int64(response.Timestamp.Nanos)).String())
		buffer.WriteString("\"")

		buffer.WriteString(", \"IsDelete\":")
		buffer.WriteString("\"")
		buffer.WriteString(strconv.FormatBool(response.IsDelete))
		buffer.WriteString("\"")

		buffer.WriteString("}")
		bArrayMemberAlreadyWritten = true
	}
	buffer.WriteString("]")

	return shim.Success(buffer.Bytes())
}

func main() {
	err := shim.Start(new(BenchmarkerChaincode))
	if err != nil {
		fmt.Printf("Error starting Sleeper chaincode: %s", err)
	}
}
