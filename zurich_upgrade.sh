#!/bin/bash

# Script version
VERSION="1.0.3"

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
VOLTA_CHAINSPEC_SHA256="5f897743eaa1a6d901c377d1b7a8a385ec836c7588cf11a1b6c72172c5fdfc37"
ENERGYWEB_CHAINSPEC_SHA256="2bbdf8758f07cf3f33124dbde8fa66d31c169bcafc71e453e85035ca79ccfb7e"

# New Client Version
NETHERMIND_NEW_VERSION="1.31.13"
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
    log_info "🔍 Detecting client type..."

    local rpc_client=""
    local docker_client=""
    local env_client=""
    local detection_results=()

    # 1. RPC Detection
    local response
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        http://localhost:8545)

    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        if echo "$response" | grep -qi "nethermind"; then
            rpc_client="nethermind"
            detection_results+=("RPC: Nethermind")
        elif echo "$response" | grep -qi "openethereum"; then
            rpc_client="openethereum"
            detection_results+=("RPC: OpenEthereum")
        fi
    fi
    log_info "🔍 RPC detection result: ${rpc_client:-none}"

    # 2. Docker Detection
    local docker_info
    docker_info=$(docker ps --format "table {{.Image}}\t{{.Names}}")

    if echo "$docker_info" | grep -qi "nethermind"; then
        docker_client="nethermind"
        detection_results+=("Docker: Nethermind")
    elif echo "$docker_info" | grep -qi "openethereum"; then
        docker_client="openethereum"
        detection_results+=("Docker: OpenEthereum")
    fi
    log_info "🔍 Docker detection result: ${docker_client:-none}"

    # 3. ENV File Detection
    if [ -f "$ENV_FILE" ]; then
        if grep -q "^NETHERMIND_VERSION=" "$ENV_FILE"; then
            env_client="nethermind"
            detection_results+=("ENV: Nethermind")
        elif grep -q "^PARITY_VERSION=" "$ENV_FILE"; then
            env_client="openethereum"
            detection_results+=("ENV: OpenEthereum")
        fi
    fi
    log_info "🔍 ENV file detection result: ${env_client:-none}"

    # Verify all methods agree
    log_info "🔍 Detection results:"
    printf '%s\n' "${detection_results[@]}" | while IFS= read -r result; do
        log_info "   - $result"
    done

    if [[ -n "$rpc_client" && -n "$docker_client" && -n "$env_client" ]]; then
        if [[ "$rpc_client" == "$docker_client" && "$docker_client" == "$env_client" ]]; then
            CLIENT_TYPE="$rpc_client"

            # Set paths based on verified client type
            if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
                CHAINSPEC_DIR="${DOCKER_STACK_DIR}/chainspec"
                if [[ ! -d "$CHAINSPEC_DIR" ]]; then
                    log_error "❌ Required directory not found: $CHAINSPEC_DIR"
                    exit 1
                fi
            else
                CONFIG_DIR="${DOCKER_STACK_DIR}/config"
                CHAINSPEC_DIR="${CONFIG_DIR}"
                CHAINSPEC_FILE="${CONFIG_DIR}/chainspec.json"
                if [[ ! -d "$CONFIG_DIR" ]]; then
                    log_error "❌ Required directory not found: $CONFIG_DIR"
                    exit 1
                fi
            fi

            log_info "✅ Verified client type: $CLIENT_TYPE"
            return 0
        else
            log_error "❌ Inconsistent client detection results:"
            log_error "   - RPC detected: $rpc_client"
            log_error "   - Docker detected: $docker_client"
            log_error "   - ENV file detected: $env_client"
            exit 1
        fi
    else
        log_error "❌ Could not detect client type using all methods:"
        [[ -z "$rpc_client" ]] && log_error "   - RPC detection failed"
        [[ -z "$docker_client" ]] && log_error "   - Docker detection failed"
        [[ -z "$env_client" ]] && log_error "   - ENV file detection failed"
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
                    echo "NETHERMIND_VERSION=nethermind/nethermind:${NETHERMIND_NEW_VERSION}" >> "$temp_file"
                    log_info "🔄 Updated Nethermind version: $current_ver -> ${NETHERMIND_NEW_VERSION}"
                else
                    echo "$line" >> "$temp_file"
                fi
                ;;
            PARITY_VERSION=*)
                if [[ "$CLIENT_TYPE" == "openethereum" ]]; then
                    echo "PARITY_VERSION=openethereum/openethereum:${OPENETHEREUM_NEW_VERSION}" >> "$temp_file"
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

# Check and fix docker-compose image references
check_fix_docker_compose() {
    log_info "🔍 Checking docker-compose.yml for hardcoded image versions..."

    # Skip if docker-compose file not found
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log_error "❌ Docker compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi

    backup_file "$DOCKER_COMPOSE_FILE"

    local needs_update=false
    # shellcheck disable=SC2155
    local temp_file=$(mktemp)

    # For Nethermind
    if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
        # Check if nethermind image is hardcoded (not using ${NETHERMIND_VERSION})
        # Fix: Use better grep pattern with proper command structure
        if grep -q "image:.*nethermind/nethermind:.*" "$DOCKER_COMPOSE_FILE" && ! grep -q "image:.*\${NETHERMIND_VERSION}" "$DOCKER_COMPOSE_FILE"; then
            needs_update=true
            log_info "🔍 Found hardcoded Nethermind image in docker-compose.yml"

            # Replace hardcoded image with variable reference
            awk '{
                if ($0 ~ /image:.*nethermind\/nethermind:/) {
                    gsub(/image:.*nethermind\/nethermind:[^ ]*/, "image: ${NETHERMIND_VERSION}")
                }
                print $0
            }' "$DOCKER_COMPOSE_FILE" > "$temp_file"

            mv "$temp_file" "$DOCKER_COMPOSE_FILE"
            log_info "✅ Updated docker-compose.yml to use \${NETHERMIND_VERSION} variable"
        else
            log_info "✅ docker-compose.yml already using \${NETHERMIND_VERSION} variable"
        fi
    # For OpenEthereum
    elif [[ "$CLIENT_TYPE" == "openethereum" ]]; then
        # Check if openethereum image is hardcoded (not using ${PARITY_VERSION})
        # Fix: Use better grep pattern with proper command structure
        if grep -q "image:.*openethereum/openethereum:.*" "$DOCKER_COMPOSE_FILE" && ! grep -q "image:.*\${PARITY_VERSION}" "$DOCKER_COMPOSE_FILE"; then
            needs_update=true
            log_info "🔍 Found hardcoded OpenEthereum image in docker-compose.yml"

            # Replace hardcoded image with variable reference
            awk '{
                if ($0 ~ /image:.*openethereum\/openethereum:/) {
                    gsub(/image:.*openethereum\/openethereum:[^ ]*/, "image: ${PARITY_VERSION}")
                }
                print $0
            }' "$DOCKER_COMPOSE_FILE" > "$temp_file"

            mv "$temp_file" "$DOCKER_COMPOSE_FILE"
            log_info "✅ Updated docker-compose.yml to use \${PARITY_VERSION} variable"
        else
            log_info "✅ docker-compose.yml already using \${PARITY_VERSION} variable"
        fi
    fi

    if [[ "$needs_update" == "true" ]]; then
        log_info "🔄 Updated docker-compose.yml file to use environment variables for image versions"
    fi
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

# Verify running container image version
verify_container_version() {
    log_info "🔍 Verifying container image versions..."
    local expected_image=""
    local found_correct_version=false

    # Set expected image based on client type
    if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
        expected_image="nethermind/nethermind:${NETHERMIND_NEW_VERSION}"
    else
        expected_image="openethereum/openethereum:${OPENETHEREUM_NEW_VERSION}"
    fi

    log_info "🔍 Checking running containers for expected image: $expected_image"

    # Get running containers with their images, removing header line
    local containers_info
    containers_info=$(docker ps --format "{{.Image}}" | grep -i "nethermind\|openethereum")

    if [[ -z "$containers_info" ]]; then
        log_error "❌ No ethereum client containers found running"
        return 1
    fi

    log_info "🔍 Found running ethereum clients:"
    while IFS= read -r image; do
        log_info "   - Image: $image"
        if [[ "$image" == "$expected_image" ]]; then
            found_correct_version=true
            log_info "✅ Found container running correct version"
        fi
    done <<< "$containers_info"

    if [[ "$found_correct_version" != "true" ]]; then
        log_error "❌ No containers found running expected image: $expected_image"
        log_error "🔍 Current running images:"
        echo "$containers_info"
        return 1
    fi

    # Verify RPC endpoint is responding
    local response
    response=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        http://localhost:8545)

    if ! echo "$response" | grep -q "result"; then
        log_error "❌ RPC endpoint not responding after restart"
        return 1
    fi

    # Verify client type in RPC response
    if [[ "$CLIENT_TYPE" == "nethermind" ]] && ! echo "$response" | grep -qi "nethermind"; then
        log_error "❌ RPC endpoint reports wrong client type (expected Nethermind)"
        return 1
    elif [[ "$CLIENT_TYPE" == "openethereum" ]] && ! echo "$response" | grep -qi "openethereum"; then
        log_error "❌ RPC endpoint reports wrong client type (expected OpenEthereum)"
        return 1
    fi

    log_info "✅ Found container running correct image version"
    log_info "✅ RPC endpoint is responding with correct client type"
    return 0
}

# Restart telegraf service
restart_telegraf_service() {
    log_info "🔄 Attempting to restart telegraf service..."
    local service_restarted=false

    if command -v systemctl &>/dev/null; then
        if systemctl restart telegraf &>/dev/null; then
            log_info "✅ Telegraf service restarted successfully"
            service_restarted=true
        elif [ -f "/lib/systemd/system/telegraf.service" ] || [ -f "/etc/systemd/system/telegraf.service" ]; then
            log_warn "⚠️  Failed to restart telegraf service via systemctl, but service file exists"
            log_info "📋 Telegraf service status:"
            systemctl status telegraf --no-pager || true
        fi
    fi

    # Try service command as fallback
    if [[ "$service_restarted" == "false" ]] && command -v service &>/dev/null; then
        if service telegraf restart &>/dev/null; then
            log_info "✅ Telegraf service restarted successfully with service command"
            service_restarted=true
        fi
    fi

    # Final status message
    if [[ "$service_restarted" == "false" ]]; then
        log_info "ℹ️  No telegraf service found or restart failed - monitoring may need manual restart"
    fi
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

    if ! $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
        log_error "❌ Some containers failed to start"
        $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" logs --tail=20
        exit 1
    fi

    # Add version verification
    if ! verify_container_version; then
        log_error "❌ Container version verification failed"
        log_error "❌ Container might be running wrong version"
        log_error "📋 Container status:"
        $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps
        log_error "📋 Container logs:"
        $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" logs --tail=20
        exit 1
    fi

    # Restart telegraf service after successful container restart
    restart_telegraf_service

    log_info "✅ Containers started and verified successfully"
    $DOCKER_COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps
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

            # Add check for docker-compose.yml references - fix the same grep issue here
            if [[ "$CLIENT_TYPE" == "nethermind" ]]; then
                if grep -q "image:.*nethermind/nethermind:.*" "$DOCKER_COMPOSE_FILE" && ! grep -q "image:.*\${NETHERMIND_VERSION}" "$DOCKER_COMPOSE_FILE"; then
                    log_info "🔍 DRY RUN: Would update docker-compose.yml to use \${NETHERMIND_VERSION} instead of hardcoded image"
                else
                    log_info "✅ DRY RUN: docker-compose.yml already using \${NETHERMIND_VERSION} variable"
                fi
            elif [[ "$CLIENT_TYPE" == "openethereum" ]]; then
                if grep -q "image:.*openethereum/openethereum:.*" "$DOCKER_COMPOSE_FILE" && ! grep -q "image:.*\${PARITY_VERSION}" "$DOCKER_COMPOSE_FILE"; then
                    log_info "🔍 DRY RUN: Would update docker-compose.yml to use \${PARITY_VERSION} instead of hardcoded image"
                else
                    log_info "✅ DRY RUN: docker-compose.yml already using \${PARITY_VERSION} variable"
                fi
            fi

            # Fix telegraf service detection logging
            local has_telegraf=false
            if command -v systemctl &>/dev/null; then
                if systemctl list-unit-files 2>/dev/null | grep -q "telegraf.service" || [ -f "/lib/systemd/system/telegraf.service" ] || [ -f "/etc/systemd/system/telegraf.service" ]; then
                    has_telegraf=true
                    log_info "🔍 DRY RUN: Would restart telegraf service via systemctl"
                fi
            fi

            # Replace the problematic service detection with a more reliable check
            if [[ "$has_telegraf" == "false" ]] && command -v service &>/dev/null; then
                # Try direct service status check instead of service --status-all
                if service telegraf status &>/dev/null || pgrep -f telegraf &>/dev/null; then
                    log_info "🔍 DRY RUN: Would restart telegraf service via service command"
                    has_telegraf=true
                fi
            fi

            if [[ "$has_telegraf" == "false" ]]; then
                log_info "🔍 DRY RUN: No telegraf service detected, would skip telegraf restart"
            fi

    else
        # Confirmation
        echo
        read -p "🤔 Continue with node upgrade for $network network? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "❌ Upgrade cancelled by user"
            exit 0
        fi

        update_image_version

        # Add check_fix_docker_compose call here, before downloading chainspec
        check_fix_docker_compose

        download_chainspec "$network"

        if [[ "$skip_restart" != "true" ]]; then
            restart_docker_containers
        else
            log_info "⏭️  Skipping Docker container restart"
            log_info "⏭️  Skipping telegraf service restart"
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
