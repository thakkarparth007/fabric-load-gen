#!/bin/bash

CMD=$1
DEFAULT_CHANNEL="ch1"
DEFAULT_VERSION=0
CH_NAME=$DEFAULT_CHANNEL
CC_NAME="benchmarkercc"

function printHelp () {
	echo "Usage: ./script <install|instantiate|upgrade> [-v <version=$DEFAULT_VERSION>, -C <channel name=$DEFAULT_CHANNEL>]"
}

function install () {
    echo "Installing $CC_NAME:$VERSION on peer"
    peer chaincode install \
        -n $CC_NAME \
        -v $VERSION \
        -p \
        github.com/hyperledger/fabric/examples/chaincode/go/benchmarker
}

function instantiate () {
    echo "Instantiating $CC_NAME:$VERSION on channel $CH_NAME"
    
    pushd $GOPATH/src/github.com/hyperledger/fabric/examples/chaincode/go/benchmarker

    echo "Step[1/3] go build" &&
    go build &&

    echo "Step [2/3] Start chaincode" &&
    CORE_CHAINCODE_LOGLEVEL=debug \
    CORE_PEER_ADDRESS=127.0.0.1:7051 \
    CORE_CHAINCODE_ID_NAME=$CC_NAME:$VERSION \
    $GOPATH/src/github.com/hyperledger/fabric/examples/chaincode/go/benchmarker/benchmarker &

    if [ $? -ne 0 ]; then
        echo "Error compiling/running chaincode. Not installing."
    fi

    sleep 5 &&
    echo "Step [3/3] Instantiate chaincode" &&
    peer chaincode instantiate \
        -n $CC_NAME \
        -v $VERSION \
        -p github.com/hyperledger/fabric/examples/chaincode/go/benchmarker \
        -c '{"Args":["init"]}' \
        -o 127.0.0.1:7050 \
        -C $CH_NAME
    echo "Done. Bringing chaincode to foreground for logs." &&
    #fg
    popd
}

function upgrade () {
    echo "Upgrading $CC_NAME to version $VERSION on channel $CH_NAME"

    pushd $GOPATH/src/github.com/hyperledger/fabric/examples/chaincode/go/benchmarker

    echo "Step[1/4] go build" &&
    go build &&

    echo "Step [2/4] Start chaincode" &&
    CORE_CHAINCODE_LOGLEVEL=debug \
    CORE_PEER_ADDRESS=127.0.0.1:7051 \
    CORE_CHAINCODE_ID_NAME=$CC_NAME:$VERSION \
    $GOPATH/src/github.com/hyperledger/fabric/examples/chaincode/go/benchmarker/benchmarker &

    if [ $? -ne 0 ]; then
        echo "Error compiling/running chaincode. Not installing."
    fi
    sleep 5 &&
    echo "Step [3/4] Install chaincode" &&
    peer chaincode install -n $CC_NAME -v $VERSION -p github.com/hyperledger/fabric/examples/chaincode/go/benchmarker &&

    echo "Step [4/4] Upgrade chaincode" &&
    peer chaincode upgrade -n $CC_NAME -v $VERSION -p github.com/hyperledger/fabric/examples/chaincode/go/benchmarker \
                           -c '{"Args":["init"]}' -o 127.0.0.1:7050 -C $CH_NAME &&

    echo "Done. Bringing chaincode to foreground for logs." &&
    wait
    popd
}

# Validate input command
if [ -z "${CMD}" ]; then
    echo "Option install / instantiate / upgrade not mentioned"
    printHelp
    exit 1
fi

# Parse the options
shift 1
while getopts ":v:C:" opt; do
    case $opt in
        v)
            VERSION=$OPTARG
            ;;
        C)
            CH_NAME=$OPTARG
            ;;
        \?)
            echo "Invalid option -$OPTARG" >&2
            printHelp
            exit 1
            ;;
        :)
            echo "-v requires an argument" >&2
            printHelp
            exit 1
            ;;
    esac
done

if [ "${VERSION}" == "${DEFAULT_VERSION}" ]; then
    echo "Using default version $DEFAULT_VERSION"
fi

if [ "${CH_NAME}" == "${DEFAULT_CHANNEL}" ]; then
    echo "Using default channel $DEFAULT_CHANNEL"
fi


# Install the chaincode
if [ "${CMD}" == "install" ]; then
	install
elif [ "${CMD}" == "instantiate" ]; then ## Instantiate the chaincode
	instantiate
elif [ "${CMD}" == "upgrade" ]; then ## Upgrade the chain code
	upgrade
else
	printHelp
	exit 1
fi
