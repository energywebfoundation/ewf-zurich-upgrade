# Zurich Hardfork Upgrade - Automated Procedure 🚀

⚠️ **WARNING**: Read All steps before proceeding.

*The upgrade process involves updating the EVM client version, downloading the new chainspec, and restarting the node.*
*This script automates the upgrade process for Volta or EnergyWebChain nodes for the Zurich hardfork.*

## Features ✨

- 🔍 Auto-detects node configuration (Volta or EnergyWebChain network)
- 🛠️ Supports both Nethermind and OpenEthereum clients
- 📥 Downloads correct chainspec
- 🔄 Updates client versions ♦
  - Nethermind: → `1.31.12`
  - OpenEthereum: → `v3.3.5`
- 💾 Creates backups before any changes [Optional]
- 🚀 Handles container restart

## Operating System 🖥️

This script is compatible with systems running a Volta or EnergyWebChain node.

Tested on Linux distributions:

- Ubuntu
- Debian
- CentOS
- Red Hat

## Prerequisites 📋

- Script Placement 📍
  - Place the script in the same directory as your docker-stack folder
  - Example structure:

    ```bash
    /your/path/
    ├── docker-stack/    # Your existing docker-stack directory
    └── zurich_upgrade.sh  # Place the script here
    ```

- Directory Structure 📁
  - The script expects the following structure:

```bash
# Node running with OpenEthereum client
docker-stack/
├── .env
├── chain-data
│   ├── cache
│   ├── chains
│   ├── keys
│   ├── network
│   └── signer
├── config
│   ├── chainspec.json
│   ├── nc-lastblock.txt
│   ├── parity-non-signing.toml
│   ├── parity-signing.toml
│   └── peers
└── docker-compose.yml

# Node running with Nethermind client
docker-stack/
├── .env
├── chainspec
│   └── energyweb.json [`volta.json` if `Volta` network]
├── configs
│   └── energyweb.cfg [`volta.cfg` if `Volta` network]
├── database
│   └── energyweb [`volta` if `Volta` network]
├── docker-compose.yml
├── keystore
│   ├── node.key.plain
│   ├── protection_keys
│   ├── UTC--2025-06-20T15-18-00.581563000Z--XXXXXX
│   └── UTC--2025-06-20T15-18-44.701058000Z--YYYYYY
├── logs
│   └── energyweb.logs.txt [`volta.logs.txt` if `Volta` network]
└── NLog.config
```

## Usage 🔧

1. Download the script:

   ```bash
   curl -O https://raw.githubusercontent.com/energywebfoundation/zurich_upgrade.sh
   chmod +x zurich_upgrade.sh
   ```

2. Run in dry-run mode first (recommended):

   ```bash
   sudo ./zurich_upgrade.sh --dry-run
   ```

3. Perform the actual upgrade:

   ```bash
   sudo ./zurich_upgrade.sh
   ```

## Options 🎛️

- `-v, --version`: Show script version
- `default`: Run the script in normal mode
- `-b, --backup`: Create a backup of the modified files
- `-n, --dry-run`: Preview changes without applying them
- `-s, --skip-restart`: Update configs without restarting containers
- `-h, --help`: Show help message

### Issues user may encounter ⚠️

1. **Docker-stack not found**
   - The script searches for docker-stack directory in:
     - Same directory as the script
     - Current working directory (`./docker-stack`)
     - Data directory (`/data/docker-stack`)
     - User's home directory (`$HOME/docker-stack` or `/home/$USER/docker-stack`)
   - Solution: Place the script in the same directory as docker-stack or use one of the expected locations

2. **Client detection fails**
   - Verify `.env` file contains either:
     - `NETHERMIND_VERSION=...`
     - `PARITY_VERSION=...`

3. **Network detection fails**
   - Ensure node is running and accessible at `http://localhost:8545`

### Logs 📜

- All output is logged to a timestamped file in the script directory.
- Log file names include the run mode (dry-run, skip-restart, etc.) and a timestamp.
- Example: `zurich_upgrade_dry_run_backup_20231001_123456.log`

## Support 💬

For issues or questions:

- Open an issue 📋 in the [repository](https://github.com/energywebfoundation/ewf-zurich-upgrade)
- Contact EWF NetOps team [📧](mailto:netops@energyweb.org)
