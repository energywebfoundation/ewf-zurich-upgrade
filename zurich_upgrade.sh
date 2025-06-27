#!/bin/bash

# Script version
VERSION="1.0.1"

# EnergyWebChain/Volta Node Upgrade Script for Zurich Hardfork
# Upgrades image versions, downloads chainspec, and restarts containers
# Usage: ./zurich_upgrade.sh [OPTIONS]
# Options:
#  Default            Upgrade (download chainspec, update versions, restart containers) without backups
#   -n, --dry-run     Preview changes without making them
#   -s, --skip-restart Update configs but don't restart containers
#   -b, --backup      Enable backups of modified files (saved in docker-stack/backups)
#   -h, --help        Show this help message
#   -v, --version     Show script version

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_STACK_DIR=""     # Will be detected
ENV_FILE=""            # Will be set after detecting docker-stack
CONFIG_DIR=""          # Will be set based on client type
CHAINSPEC_DIR=""       # Will be set based on client type
CHAINSPEC_FILE=""      # Will be set based on client type and network
DOCKER_COMPOSE_FILE="" # Will be set after finding compose file
DETECTED_NETWORK=""    # Will be set during network detection
BACKUP_ENABLED=false   # Will be set by --backup flag
BACKUP_DIR=""         # Will be set after detecting docker-stack
DOCKER_COMPOSE_CMD=""  # Will store either "docker-compose" or "docker compose"

# Chainspec URLs
VOLTA_CHAINSPEC_URL="https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/refs/heads/master/Volta.json"
ENERGYWEB_CHAINSPEC_URL="https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/refs/heads/master/EnergyWebChain.json"

# Chainspec SHA256 checksums
VOLTA_CHAINSPEC_SHA256="a3703455d145171a33f4ae31ba8b1630a551b0db7fdacd7e685574d5a9fc3afb"
ENERGYWEB_CHAINSPEC_SHA256="7a05ac8da3d3f7192da074dd6987205fdb3300f7dd4970876e5f2ad249bbcd2d"

# New Client Version
NETHERMIND_NEW_VERSION="1.31.12"
OPENETHEREUM_NEW_VERSION="v3.3.5"

# Set log file name based on run mode
get_log_file() {
    local mode="$1"
    # shellcheck disable=SC2155
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_suffix=""

    # Add backup suffix if enabled
    [[ "$BACKUP_ENABLED" == "true" ]] && backup_suffix="_backup"

    case "$mode" in
        "dry-run")
            echo "${SCRIPT_DIR}/zurich_upgrade_dry_run${backup_suffix}_${timestamp}.log"
            ;;
        "skip-restart")
            echo "${SCRIPT_DIR}/zurich_upgrade_skip_restart${backup_suffix}_${timestamp}.log"
            ;;
        *)
            echo "${SCRIPT_DIR}/zurich_upgrade${backup_suffix}_${timestamp}.log"
            ;;
    esac
}

LOG_FILE=""  # Will be set based on run mode

# Client type (will be detected)
CLIENT_TYPE=""

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    # shellcheck disable=SC2155
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [[ ! -p /dev/stdout ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Detect docker-stack directory
detect_docker_stack() {
    log_info "🔍 Detecting docker-stack directory..."

    # Check current directory and script directory
    local search_paths=(
        "${SCRIPT_DIR}/docker-stack"
        "./docker-stack"
        "/data/docker-stack"
        "/root/docker-stack"
    )

    # User's home directory
    if [[ -n "$SUDO_USER" ]]; then
        search_paths+=("/home/$SUDO_USER/docker-stack")
    else
        search_paths+=("${HOME}/docker-stack")
    fi

    for path in "${search_paths[@]}"; do
        # Resolve to absolute path
        local abs_path
        abs_path=$(readlink -f "$path")

        if [[ -d "$abs_path" ]] && [[ -f "$abs_path/.env" ]]; then
            DOCKER_STACK_DIR="$abs_path"
            ENV_FILE="${DOCKER_STACK_DIR}/.env"
            log_info "✅ Found docker-stack directory: $DOCKER_STACK_DIR"
            return 0
        fi
    done

    log_error "❌ Could not find docker-stack directory with .env file"
    log_error "🔍 Searched locations: ${search_paths[*]}"
    exit 1
}

# Detect client type and set paths
detect_client_type() {
        log_info "🔍 Detecting client type from .env file..."

    local has_nethermind=false
    local has_parity=false

    if grep -q "^NETHERMIND_VERSION=" "$ENV_FILE"; then
        has_nethermind=true
    fi

    if grep -q "^PARITY_VERSION=" "$ENV_FILE"; then
        has_parity=true
    fi

    if [[ "$has_nethermind" == "true" ]] && [[ "$has_parity" == "true" ]]; then
        log_error "❌ Found both NETHERMIND_VERSION and PARITY_VERSION in .env file"
        exit 1
    elif [[ "$has_nethermind" == "true" ]]; then
        CLIENT_TYPE="nethermind"
        CHAINSPEC_DIR="${DOCKER_STACK_DIR}/chainspec"
        log_info "🔍 Debug [detect_client_type]: Set CHAINSPEC_DIR=$CHAINSPEC_DIR"

        # Verify chainspec directory exists and has expected files
        if [[ ! -d "$CHAINSPEC_DIR" ]]; then
            log_error "❌ Nethermind client detected but chainspec directory not found: $CHAINSPEC_DIR"
            exit 1
        fi

        # Check for expected chainspec files
        local has_chainspec_files=false
        if [[ -f "${CHAINSPEC_DIR}/volta.json" ]] || [[ -f "${CHAINSPEC_DIR}/energyweb.json" ]]; then
            has_chainspec_files=true
        fi

        if [[ "$has_chainspec_files" == "false" ]]; then
            log_warn "⚠️  No volta.json or energyweb.json found in chainspec directory"
            log_info "ℹ️  Will download chainspec file based on detected network"
        fi

        log_info "✅ Detected Nethermind client"
    elif [[ "$has_parity" == "true" ]]; then
        CLIENT_TYPE="openethereum"
        CONFIG_DIR="${DOCKER_STACK_DIR}/config"
        CHAINSPEC_DIR="${CONFIG_DIR}"
        CHAINSPEC_FILE="${CONFIG_DIR}/chainspec.json"
        log_info "✅ Detected OpenEthereum client"
    else
        log_error "❌ Could not detect client type - no NETHERMIND_VERSION or PARITY_VERSION found"
        exit 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_info "✅ Validating prerequisites..."

    # Check required tools
    for tool in docker curl jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "❌ Required tool not found: $tool"
            exit 1
        fi
    done

    # Check for docker compose/docker-compose command
    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
        log_info "✅ Using docker-compose command"
    elif docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        log_info "✅ Using docker compose command"
    else
        log_error "❌ Neither docker-compose nor docker compose found"
        exit 1
    fi

    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "❌ Docker daemon is not running"
        exit 1
    fi

    # Detect docker-stack directory
    detect_docker_stack

    # Set backup directory
    BACKUP_DIR="${DOCKER_STACK_DIR}/backups"

    # Detect client type and set paths
    detect_client_type

    # Check required directories exist (for OpenEthereum only, Nethermind is checked in detect_client_type)
    if [[ "$CLIENT_TYPE" == "openethereum" ]]; then
        if [[ ! -d "$CONFIG_DIR" ]]; then
            log_error "❌ Config directory not found: $CONFIG_DIR"
            exit 1
        fi
    fi

    # Check docker-compose file (both .yml and .yaml)
    if [[ -f "${DOCKER_STACK_DIR}/docker-compose.yml" ]]; then
        DOCKER_COMPOSE_FILE="${DOCKER_STACK_DIR}/docker-compose.yml"
    elif [[ -f "${DOCKER_STACK_DIR}/docker-compose.yaml" ]]; then
        DOCKER_COMPOSE_FILE="${DOCKER_STACK_DIR}/docker-compose.yaml"
    else
        log_error "❌ Docker compose file not found in $DOCKER_STACK_DIR (checked .yml and .yaml)"
        exit 1
    fi

    log_info "✅ Prerequisites validation completed"
}

# Query network ID from local node
query_network_id() {
    local rpc_endpoint="http://localhost:8545"
    local max_retries=5

    log_info "🔍 Querying network ID from local validator node..."

    for ((i=1; i<=max_retries; i++)); do
        local response
        local network_id

        # Make RPC call and store full response
        response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
            "$rpc_endpoint" 2>/dev/null)

        if network_id=$(echo "$response" | jq -r '.result // empty' 2>/dev/null); then
            # Extract chain ID
            chain_id=$(echo "$network_id" | grep -o '^[0-9]*$' || echo "$network_id" | grep -o '[0-9]*$')
            if [[ -n "$chain_id" ]]; then
                log_info "✅ Chain ID detected: $chain_id"
                echo "$chain_id"
                return 0
            fi
        fi

        log_warn "⚠️  Failed to query network ID, attempt $i/$max_retries"
        [[ $i -lt $max_retries ]] && sleep 2
    done

    log_error "❌ Failed to query network ID after $max_retries attempts"
    return 1
}

# Detect network and set paths
detect_network() {
    log_info "🔍 Detecting network..."

    local network_id
    if ! network_id=$(query_network_id); then
        log_warn "⚠️  Failed to query network ID from local node"

        # Try to get from existing chainspec
        if [[ -f "$CHAINSPEC_FILE" ]]; then
            if network_id=$(jq -r '.params.networkID // empty' "$CHAINSPEC_FILE" 2>/dev/null); then
                log_info "✅ Network ID from existing chainspec: $network_id"
            fi
        fi

        if [[ -z "${network_id:-}" ]]; then
            log_error "❌ Could not determine network ID"
            exit 1
        fi
    fi

    # Clean up network_id and convert to hex
    if [[ -n "$network_id" ]]; then
        local decimal_id="$network_id"

        # If it's a number, convert to hex
        if [[ "$network_id" =~ ^[0-9]+$ ]]; then
            network_id=$(printf "0x%x" "$network_id")
        fi
        # Convert to lowercase for comparison
        network_id=$(echo "$network_id" | tr '[:upper:]' '[:lower:]')

        log_info "🔍 Detected network ID: ${network_id} | ${decimal_id}"
    else
        log_error "❌ Empty network ID after cleanup"
        return 1
    fi

    # Detect network and set paths
    case "$network_id" in
        "0x12047"|"73799")
            DETECTED_NETWORK="volta"
            log_info "🌐 Detected Volta network"
            ;;
        "0xf6"|"246")
            DETECTED_NETWORK="energyweb"
            log_info "🌐 Detected EnergyWebChain network"
            ;;
        *)
            log_error "❌ Unknown network ID: $network_id"
            exit 1
            ;;
    esac

    # Set chainspec file path based on client type and network
    if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
        if [[ ! -d "$CHAINSPEC_DIR" ]]; then
            log_error "❌ Required directory not found: $CHAINSPEC_DIR"
            exit 1
        fi
        CHAINSPEC_FILE="${CHAINSPEC_DIR}/${DETECTED_NETWORK}.json"
        log_info "🔍 Debug [detect_network]: CHAINSPEC_DIR=$CHAINSPEC_DIR"
        log_info "🔍 Debug [detect_network]: DETECTED_NETWORK=$DETECTED_NETWORK"
        log_info "🔍 Debug [detect_network]: Set CHAINSPEC_FILE=$CHAINSPEC_FILE"
    else
        if [[ ! -d "$CONFIG_DIR" ]]; then
            log_error "❌ Required directory not found: $CONFIG_DIR"
            exit 1
        fi
        CHAINSPEC_FILE="${CONFIG_DIR}/chainspec.json"
        log_info "ℹ️  Using chainspec path: $CHAINSPEC_FILE"
    fi

    echo "$DETECTED_NETWORK"
}

# Backup file - Creates backup in designated backup directory if enabled
backup_file() {
    local file_path="$1"

    # Skip if backups not enabled
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ -f "$file_path" ]]; then
        # shellcheck disable=SC2155
        local filename=$(basename "$file_path")
        # shellcheck disable=SC2155
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="${BACKUP_DIR}/${filename}.${timestamp}"

        # Ensure backup directory exists
        mkdir -p "$BACKUP_DIR"

        cp "$file_path" "$backup_path"
        log_info "💾 Created backup: $backup_path"
    fi
}

# Update image versions in .env file
update_image_version() {
    log_info "🔍 Checking image versions..."

    local needs_update=false
    local current_ver=""

    # Check if update is needed
    if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
        current_version=$(grep "^NETHERMIND_VERSION=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
        current_ver=$(echo "$current_version" | cut -d':' -f2)
        if [[ "$current_ver" != "$NETHERMIND_NEW_VERSION" ]]; then
            needs_update=true
        fi
    else
        current_version=$(grep "^PARITY_VERSION=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
        current_ver=$(echo "$current_version" | cut -d':' -f2)
        if [[ "$current_ver" != "$OPENETHEREUM_NEW_VERSION" ]]; then
            needs_update=true
        fi
    fi

    # If no update needed, return early
    if [[ "$needs_update" == "false" ]]; then
        if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
            log_info "✅ Nethermind version $current_ver already at target version"
        else
            log_info "✅ OpenEthereum version $current_ver already at target version"
        fi
        return 0
    fi

    # Proceed with update
    log_info "🔄 Updating image versions in $ENV_FILE..."
    backup_file "$ENV_FILE"

    local temp_file
    temp_file=$(mktemp)

    while IFS= read -r line; do
        case "$line" in
            NETHERMIND_VERSION=*)
                if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
                    echo "NETHERMIND_VERSION=\"nethermind/nethermind:${NETHERMIND_NEW_VERSION}\"" >> "$temp_file"
                    log_info "🔄 Updated Nethermind version: $current_ver -> ${NETHERMIND_NEW_VERSION}"
                else
                    echo "$line" >> "$temp_file"
                fi
                ;;
            PARITY_VERSION=*)
                if [[ "$CLIENT_TYPE" == "openethereum" ]]; then
                    echo "PARITY_VERSION=\"openethereum/openethereum:${OPENETHEREUM_NEW_VERSION}\"" >> "$temp_file"
                    log_info "🔄 Updated OpenEthereum version: $current_ver -> ${OPENETHEREUM_NEW_VERSION}"
                else
                    echo "$line" >> "$temp_file"
                fi
                ;;
            *)
                echo "$line" >> "$temp_file"
                ;;
        esac
    done < "$ENV_FILE"

    mv "$temp_file" "$ENV_FILE"
    log_info "✅ Image version updated successfully"
}

# Download chainspec
download_chainspec() {
    local network="$1"
    local chainspec_url
    local expected_sha256

    log_info "🔍 Debug [download_chainspec]: Start with CHAINSPEC_FILE=$CHAINSPEC_FILE"
    log_info "🔍 Debug [download_chainspec]: CHAINSPEC_DIR=$CHAINSPEC_DIR"
    log_info "🔍 Debug [download_chainspec]: network=$network"

    case "$network" in
        "volta")
            chainspec_url="$VOLTA_CHAINSPEC_URL"
            expected_sha256="$VOLTA_CHAINSPEC_SHA256"
            ;;
        "energyweb")
            chainspec_url="$ENERGYWEB_CHAINSPEC_URL"
            expected_sha256="$ENERGYWEB_CHAINSPEC_SHA256"
            ;;
        *)
            log_error "Invalid network: $network"
            exit 1
            ;;
    esac

    log_info "📥 Downloading chainspec for $network network to: $CHAINSPEC_FILE"
    log_info "🔍 Debug: CHAINSPEC_FILE=$CHAINSPEC_FILE"
    log_info "🔍 Debug: CHAINSPEC_DIR=$CHAINSPEC_DIR"
    log_info "🔍 Debug: Current directory=$(pwd)"

    # Backup existing chainspec if it exists
    backup_file "$CHAINSPEC_FILE"

    # Download chainspec directly to target file
    if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
        "$chainspec_url" -o "$CHAINSPEC_FILE"; then
        log_error "❌ Failed to download chainspec from $chainspec_url"
        exit 1
    fi

    # Validate JSON
    if ! jq empty "$CHAINSPEC_FILE" 2>/dev/null; then
        log_error "❌ Downloaded chainspec is not valid JSON"
        exit 1
    fi

    # Verify SHA256 checksum
    local actual_sha256
    actual_sha256=$(sha256sum "$CHAINSPEC_FILE" | cut -d' ' -f1)
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        log_error "❌ Chainspec SHA256 checksum verification failed"
        log_error "Expected: $expected_sha256"
        log_error "Got:      $actual_sha256"
        exit 1
    fi
    log_info "✅ Chainspec SHA256 checksum verified"
    log_info "✅ Downloaded chainspec SHA256: $actual_sha256"

    log_info "✅ Chainspec downloaded and saved to: $CHAINSPEC_FILE"
}

# Restart Docker containers
restart_docker_containers() {
    log_info "🔄 Restarting Docker containers..."

    cd "$DOCKER_STACK_DIR"

    # Stop containers gracefully
    log_info "⏹️  Stopping containers..."
    if ! $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" down --timeout 60; then
        log_error "❌ Failed to stop containers gracefully"
        exit 1
    fi

    # Pull updated images
    log_info "📥 Pulling updated images..."
    $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" pull

    # Start containers
    log_info "🚀 Starting containers..."
    $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" up -d --force-recreate

    # Wait and verify
    log_info "⏳ Waiting for containers to start..."
    sleep 15

    if $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
        log_info "✅ Containers started successfully"
        $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps
    else
        log_error "❌ Some containers failed to start"
        $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" logs --tail=20
        exit 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Zurich upgrade script for EnergyWebChain/Volta nodes.
Version: $VERSION

MODES:
    Default             Upgrade (download chainspec, update versions, restart containers) without backups
    -n, --dry-run       Preview changes without making them
    -s, --skip-restart  Update configs but don't restart containers

OPTIONS:
    -h, --help        Show this help message
    -b, --backup      Enable backups of modified files (saved in docker-stack/backups)
    -v, --version     Show script version

EXAMPLES:
    $(basename "$0")                    # Upgrade (no backups)
    $(basename "$0") -b                 # Upgrade with backups enabled
    $(basename "$0") -n                 # Preview changes
    $(basename "$0") -s                 # Update configs only (no backups)
    $(basename "$0") -s -b              # Update configs with backups, no restart

LOGGING:
    All output is logged to a timestamped file in the script directory.
    Log file names include the run mode (dry-run, skip-restart, etc.) and a timestamp.
    Example: zurich_upgrade_dry_run_backup_20231001_123456.log
EOF
}

# Main function
main() {
    local dry_run=false
    local skip_restart=false

    # Parse arguments
    local run_mode="upgrade"  # Default mode is upgrade
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                echo "$(basename "$0") version $VERSION"
                exit 0
                ;;
            -n|--dry-run)
                if [[ "$run_mode" != "upgrade" ]]; then
                    log_error "❌ Cannot combine --dry-run with other modes"
                    exit 1
                fi
                dry_run=true
                run_mode="dry-run"
                ;;
            -s|--skip-restart)
                if [[ "$run_mode" != "upgrade" ]]; then
                    log_error "❌ Cannot combine --skip-restart with other modes"
                    exit 1
                fi
                skip_restart=true
                run_mode="skip-restart"
                ;;
            -b|--backup)
                BACKUP_ENABLED=true
                ;;
            *)
                log_error "❌ Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done

    # Set log file based on run mode
    LOG_FILE=$(get_log_file "$run_mode")

            log_info "=========================================="
    if [[ "$dry_run" == "true" ]]; then
        log_info "🔍 Node Upgrade Script Started (DRY RUN MODE)"
    else
        log_info "🚀 Node Upgrade Script Started"
    fi
    log_info "=========================================="
    log_info "📝 Log file: $LOG_FILE"

    # Execute validation steps regardless of dry run
    validate_prerequisites

    # Detect network and set paths
    if ! detect_network; then
        log_error "❌ Network detection failed"
        exit 1
    fi
    # log_info "🔍 Debug [main]: After detect_network: CHAINSPEC_FILE=$CHAINSPEC_FILE"
    # log_info "🔍 Debug [main]: After detect_network: DETECTED_NETWORK=$DETECTED_NETWORK"
    local network="$DETECTED_NETWORK"

    if [[ "$dry_run" == "true" ]]; then
        log_info "🔍 Starting dry run validation..."
    fi

    # Show network-specific title
    case "$network" in
        "volta")
            log_info "🌐 Volta Node Upgrade"
            ;;
        "energyweb")
            log_info "🌐 EnergyWebChain Node Upgrade"
            ;;
    esac

        if [[ "$dry_run" == "true" ]]; then
            # Check and show version changes if needed
            if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
                current_version=$(grep "^NETHERMIND_VERSION=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
                current_ver=$(echo "$current_version" | cut -d':' -f2)
                if [[ "$current_ver" == "$NETHERMIND_NEW_VERSION" ]]; then
                    log_info "✅ DRY RUN: Nethermind version $current_ver already at target version"
                else
                    log_info "🔍 DRY RUN: Would update Nethermind version from $current_ver to ${NETHERMIND_NEW_VERSION}"
                fi
            else
                current_version=$(grep "^PARITY_VERSION=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
                current_ver=$(echo "$current_version" | cut -d':' -f2)
                if [[ "$current_ver" == "$OPENETHEREUM_NEW_VERSION" ]]; then
                    log_info "✅ DRY RUN: OpenEthereum version $current_ver already at target version"
                else
                    log_info "🔍 DRY RUN: Would update OpenEthereum version from $current_ver to ${OPENETHEREUM_NEW_VERSION}"
                fi
            fi

            # Show chainspec changes and expected SHA256
            log_info "🔍 DRY RUN: Would download new chainspec for $network network to: $CHAINSPEC_FILE"
            case "$network" in
                "volta")
                    log_info "🔍 DRY RUN: Expected chainspec SHA256: $VOLTA_CHAINSPEC_SHA256"
                    ;;
                "energyweb")
                    log_info "🔍 DRY RUN: Expected chainspec SHA256: $ENERGYWEB_CHAINSPEC_SHA256"
                    ;;
            esac

            # Show container changes
            containers=$($DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps --services)
            log_info "🔍 DRY RUN: Would restart the following containers:"
            for container in $containers; do
                log_info "           - $container"
            done
    else
        # Confirmation
        echo
        read -p "🤔 Continue with node upgrade for $network network? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "❌ Upgrade cancelled by user"
            exit 0
        fi

        update_image_version
        download_chainspec "$network"

        if [[ "$skip_restart" != "true" ]]; then
            restart_docker_containers
        else
            log_info "⏭️  Skipping Docker container restart"
        fi
    fi

    log_info "=========================================="
    if [[ "$dry_run" == "true" ]]; then
        log_info "✅ Dry run validation completed - no changes were made"
    else
        case "$network" in
            "volta")
                log_info "🎉 🌐 Volta Node Upgrade Completed Successfully 🎉"
                ;;
            "energyweb")
                log_info "🎉 🌐 EnergyWebChain Node Upgrade Completed Successfully 🎉"
                ;;
        esac
    fi
    log_info "=========================================="
    log_info "📝 Log file saved: $LOG_FILE"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
