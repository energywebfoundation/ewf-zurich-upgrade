# Zurich Hardfork Upgrade — Manual Procedure 🔧

⚠️ **WARNING**: Read All steps before proceeding.

*This guide provides step-by-step instructions for manually upgrading of Volta or EnergyWebChain node for the Zurich hardfork.*

*The upgrade process involves updating the EVM client version, downloading the new chainspec, and restarting the node.*

*This guide is intended for users who prefer manual upgrades.*

## 1. Pre-upgrade Checks 📋

### 1.1 Check client version

Identifiying EVM client can be done by multiple ways. choose one of the following methods or use all of them to be sure.

### 1.1.1 Query the validator node 🔍

```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
  http://localhost:8545
```

```bash
# Response for OpenEthereum
{"jsonrpc":"2.0","result":"OpenEthereum//v3.3.5-stable/x86_64-linux-musl/rustc1.59.0","id":1}

# Response for Nethermind
{"jsonrpc":"2.0","result":"Nethermind/v1.31.10+f62cfede/linux-x64/dotnet9.0.4","id":1}

```

### 1.1.2 Check the Docker images of running containers ☸️

```bash
docker ps --format "table {{.Image}}\t{{.Names}}"
```

```bash
# Example output for OpenEthereum
IMAGE                              NAMES
openethereum/openethereum:v3.3.3   docker-stack_parity_1

# Example output for Nethermind
IMAGE                                      NAMES
nethermind/nethermind:1.31.10              docker-stack_nethermind_1
```

### 1.1.2 Check the `.env` file ✏️

```bash
cat docker-stack/.env
```

If you see `NETHERMIND_VERSION`, your node is running Nethermind. If you see `PARITY_VERSION`, it is running OpenEthereum.

### 1.2 Verify network 🌐

```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  http://localhost:8545
```

```bash
# Response for Volta.
# Volta Network ID: 73799
{"jsonrpc":"2.0","result":"73799","id":1}

# Response for EnergyWebChain
# EnergyWebChain Network ID: 246
{"jsonrpc":"2.0","result":"246","id":1}
```

## 2. Update Client Version 🔄

Edit your `.env` file:

For Nethermind:

```bash
# Update NETHERMIND_VERSION in .env
NETHERMIND_VERSION="nethermind/nethermind:1.31.12"
```

For OpenEthereum:

```bash
# Update PARITY_VERSION in .env
PARITY_VERSION="openethereum/openethereum:v3.3.5"
```

## 3. Download New Chainspec 📥

### 3.1 For Volta validator node running with OpenEthereum client

```bash
cd docker-stack
curl -o config/chainspec.json https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/Volta.json

# Verify SHA256 checksum ✔️
echo "a3703455d145171a33f4ae31ba8b1630a551b0db7fdacd7e685574d5a9fc3afb config/chainspec.json" | sha256sum -c
```

### 3.2 For Volta validator node running with Nethermind client

```bash
cd docker-stack
curl -o chainspec/volta.json https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/Volta.json

# Verify SHA256 checksum ✔️
echo "a3703455d145171a33f4ae31ba8b1630a551b0db7fdacd7e685574d5a9fc3afb chainspec/volta.json" | sha256sum -c
```

### 3.3 For EnergyWebChain validator node running OpenEthereum client

```bash
cd docker-stack
curl -o config/chainspec.json https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/EnergyWebChain.json

# Verify SHA256 checksum ✔️
echo "7a05ac8da3d3f7192da074dd6987205fdb3300f7dd4970876e5f2ad249bbcd2d config/chainspec.json" | sha256sum -c
```

### 3.4 For EnergyWebChain validator node running Nethermind client

```bash
cd docker-stack
curl -o chainspec/energyweb.json https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/EnergyWebChain.json

# Verify SHA256 checksum ✔️
echo "7a05ac8da3d3f7192da074dd6987205fdb3300f7dd4970876e5f2ad249bbcd2d chainspec/energyweb.json" | sha256sum -c
```

## 5. Restart Node 🚀

```bash
cd docker-stack
docker-compose up -d --force-recreate
```

## 6. Verify Upgrade ✅

### 6.1 Check Container Status

```bash
docker-compose ps
```

### 6.2 Check Client Version on running node

```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
  http://localhost:8545
```

```bash
# Resoinse of running node of OpenEthereum
{"jsonrpc":"2.0","result":"OpenEthereum//v3.3.5-stable/x86_64-linux-musl/rustc1.59.0","id":1}

# Resoinse of running node of Nethermind
{"jsonrpc":"2.0","result":"Nethermind/v1.31.10+f62cfede/linux-x64/dotnet9.0.4","id":1}

```

### 6.3 Check Logs 🔍

```bash
# For Nethermind
docker-compose logs -f --tail 100 nethermind
docker-compose logs -f --tail 100 nethermind-telemetry

# For OpenEthereum
docker-compose logs -f --tail 100 parity
docker-compose logs -f --tail 100 parity-telemetry
```

### 6.4 Network Sync Status ♾️

```bash
# Check sync status
curl -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://localhost:8545
```

If the response is `false`, the node is fully synced.
If it returns an object with `startingBlock`, `currentBlock`, and `highestBlock`, the node is still syncing.

### Support 💬

For issues or questions:

- Contact EWF NetOps team [📧](mailto:netops@energyweb.org)
