# Install fabric on all - using Parth's repo
# install couchdb on all
# install fetch-block on all
# 
# update /etc/hosts on all. if ips change, update all places where ips are hardcoded. few places only, afaik
# 
# install screen,zip,nmon,tcpdump,inotify-tools,ntpdate,go-torch on all
# 
# add to path /usr/local/go/bin:/root/git/src/github.com/hyperledger/fabric/build/bin/:$HOME/devenv/node/bin
# add fabric, fabric-sdk commands to bashrc
# 
# install nvm, nodejs, on nagios
# install nmonchart on nagios, add nmonchart to PATH
# 
# create /root/tools/scripts/... -> using IBM Github's repo

cd ~/

apt-get install -y htop

##
## Install fabric
##

# golang
cd $HOME/ && wget https://storage.googleapis.com/golang/go1.7.1.linux-amd64.tar.gz
tar -xvf go1.7.1.linux-amd64.tar.gz
mkdir $HOME/gopath 
echo "export GOPATH=$HOME/gopath" >> ~/.bashrc 
echo "export GOROOT=$HOME/go" >> ~/.bashrc
echo "export PATH=$PATH:$GOROOT/bin" >> ~/.bashrc
source ~/.bashrc

# libltdl
apt-get install libltdl-dev
# docker
wget https://download.docker.com/linux/ubuntu/dists/xenial/pool/stable/amd64/docker-ce_17.06.0~ce-0~ubuntu_amd64.deb
dpkg -i docker-ce_17.06.0~ce-0~ubuntu_amd64.deb
docker run hello-world
# pip
apt-get install -y python-pip
# docker compose
pip install -y docker-compose
# git
apt-get install -y git
# git
apt-get install -y curl
# code
mkdir -p $GOPATH/src/github.com/hyperledger/
cd $GOPATH/src/github.com/hyperledger/
git clone https://github.com/thakkarparth007/fabric.git
git checkout experimental_modifications
make
echo "export PATH=$PATH:$GOPATH/src/github.com/hyperledger/fabric/build/bin/" >> ~/.bashrc
source ~/.bashrc

peerName=$(hostname)
peerNum=$(echo hostname | grep "[0-9]+")
orgName="org"$((peerNum/2))
orgNum=$((peerNum/2))
echo "ulimit -n 1048576
IS_ENABLED=\$1
CORE_PEER_ENDORSER_ENABLED=true \
CORE_PEER_PROFILE_ENABLED=true \
CORE_PEER_ADDRESS=${peerName}:7051 \
CORE_PEER_CHAINCODELISTENADDRESS=${peerName}:7052 \
CORE_PEER_ID=${orgName}-${peerName} \
CORE_PEER_LOCALMSPID=Org${orgNum}MSP \
CORE_PEER_GOSSIP_EXTERNALENDPOINT=${peerName}:7051 \
CORE_PEER_GOSSIP_USELEADERELECTION=true \
CORE_PEER_GOSSIP_ORGLEADER=false \
CORE_PEER_TLS_ENABLED=$IS_ENABLED \
CORE_PEER_TLS_KEY_FILE=/root/bcnetwork/conf/crypto-config/peerOrganizations/${orgName}/peers/${peerName}.${orgName}/tls/server.key \
CORE_PEER_TLS_CERT_FILE=/root/bcnetwork/conf/crypto-config/peerOrganizations/${orgName}/peers/${peerName}.${orgName}/tls/server.crt \
CORE_PEER_TLS_ROOTCERT_FILE=/root/bcnetwork/conf/crypto-config/peerOrganizations/${orgName}/peers/${peerName}.${orgName}/tls/ca.crt \
CORE_PEER_TLS_SERVERHOSTOVERRIDE=${peerName} \
CORE_VM_DOCKER_ATTACHSTDOUT=true \
CORE_PEER_MSPCONFIGPATH=/root/bcnetwork/conf/crypto-config/peerOrganizations/${orgName}/peers/${peerName}.${orgName}/msp \
/root/gocode/src/github.com/hyperledger/fabric/build/bin/peer node start --peer-defaultchain=false
' > ./start-peer.sh
chmod +x ./start-peer.sh

# cd examples/e2e_cli/ && ./network_setup.sh up

##
## Install couchdb
##
mkdir temp
cd temp
wget https://raw.githubusercontent.com/afiskon/install-couchdb/master/install-couchdb.sh
sh install-couchdb.sh
# then see http://localhost:5984/_utils/

##
## Install fetch-block
##
cd $GOPATH/src
git clone https://github.com/cendhu/fetch-block
cd fetch-block/src
make

## Install utilities
apt-get install -y screen zip nmon tcpdump inotify-tools ntpdate iperf
go get github.com/uber/go-torch

