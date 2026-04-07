#!/bin/bash
#
# Heltec V3 Companion Radio WiFi + TCP Serial Builder
# Automates: clone, patch, configure, build, erase, upload
#

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'

BLUE='\033[0;34m'
NC='\033[0m' # No Color

set_platformio_env_option() {
    local ini_file="$1"
    local env_name="$2"
    local option_key="$3"
    local option_value="$4"

    if [ -z "$option_value" ]; then
        return
    fi

    python3 - "$ini_file" "$env_name" "$option_key" "$option_value" <<'PY'
import re
import sys
from pathlib import Path

ini_path = Path(sys.argv[1])
env_name = sys.argv[2]
key = sys.argv[3]
value = sys.argv[4]

if not ini_path.exists():
    raise SystemExit(f"INI file not found: {ini_path}")

text = ini_path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines(keepends=True)

header = f"[env:{env_name}]"

try:
    start = next(i for i, ln in enumerate(lines) if ln.strip() == header)
except StopIteration:
    raise SystemExit(f"Environment section not found: {header}")

end = None
for i in range(start + 1, len(lines)):
    if lines[i].lstrip().startswith("[") and lines[i].strip().endswith("]"):
        end = i
        break
if end is None:
    end = len(lines)

key_re = re.compile(rf"^\s*{re.escape(key)}\s*=.*$")
replacement = f"{key} = {value}\n"

replaced = False
for i in range(start + 1, end):
    if key_re.match(lines[i]):
        lines[i] = replacement
        replaced = True
        break

if not replaced:
    insert_at = end
    if insert_at > 0 and not lines[insert_at - 1].endswith("\n"):
        lines[insert_at - 1] = lines[insert_at - 1] + "\n"
    lines.insert(insert_at, replacement)

ini_path.write_text("".join(lines), encoding="utf-8")
PY

}


# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
PATCHES_DIR="${SCRIPT_DIR}/patches"
DEFAULT_WORK_DIR="${SCRIPT_DIR}/build"
DEFAULT_COMPANION_BRANCH="companion-v1.14.0"
DEFAULT_REPEATER_BRANCH="repeater-v1.14.0"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}[!] Configuration file not found: ${CONFIG_FILE}${NC}"
    echo -e "${YELLOW}[*] Creating default config.env...${NC}"
    cat > "$CONFIG_FILE" << 'EOF'
# WiFi credentials (DHCP only)
WIFI_SSID="YourNetwork"
WIFI_PASSWORD="YourPassword"
TCP_PORT=5002
CONSOLE_PORT=5001
WIFI_DEBUG_LOGGING=1

# LoRa radio flags
LORA_FREQ=869.618
LORA_BW=62.5
LORA_SF=8
LORA_CR=5
LORA_TX_POWER=22

# Memory / queues / contacts
MAX_CONTACTS=350
MAX_GROUP_CHANNELS=40
OFFLINE_QUEUE_SIZE=256
MAX_UNREAD_MSGS=32
MAX_BLOBRECS=100

# Display
DISPLAY_CLASS=SSD1306Display
AUTO_OFF_MILLIS=15000
UI_RECENT_LIST_SIZE=4

# Debug (0=off,1=on)
MESH_PACKET_LOGGING=1
MESH_DEBUG=1
BRIDGE_DEBUG=0
BLE_DEBUG_LOGGING=0

# Build orchestration
FIRMWARE_VERSION="dev"
EXTRA_BUILD_FLAGS=""
ENABLE_CONSOLE_MIRROR_PATCH=0

# Identity / advertising
ADVERT_NAME="Heltec V3 WiFi"
ADVERT_LAT=0.0
ADVERT_LON=0.0
ADMIN_PASSWORD="password"
GUEST_PASSWORD="${GUEST_PASSWORD:-guest}"

# Build role (companion or repeater)
BUILD_ROLE="companion"

# Upload port (leave empty to auto-detect)
UPLOAD_PORT=""

# Upload speed (PlatformIO/esptool). Some USB-UART adapters/boards are unstable at high baud.
# Common stable values: 115200, 230400, 460800
UPLOAD_SPEED=""

# PlatformIO environment
PIO_ENV="Heltec_v3_companion_radio_wifi"

# Git repository
REPO_URL="https://github.com/meshcore-dev/MeshCore"
REPO_BRANCH="companion-v1.14.0"

# Optional: override build directory (default: ./build)
# WORK_DIR="/absolute/path/to/workdir"
EOF
    echo -e "${GREEN}[✓] Created config.env - please edit it and run again${NC}"
    exit 0
fi

source "$CONFIG_FILE"

# Defaults for configurable build flags
WIFI_SSID="${WIFI_SSID:-YourNetwork}"
WIFI_PASSWORD="${WIFI_PASSWORD:-YourPassword}"
TCP_PORT=${TCP_PORT:-5002}
CONSOLE_PORT=${CONSOLE_PORT:-5001}
WIFI_DEBUG_LOGGING=${WIFI_DEBUG_LOGGING:-1}

# Defaults for repository source
REPO_URL="${REPO_URL:-https://github.com/meshcore-dev/MeshCore}"
REPO_BRANCH="${REPO_BRANCH:-$DEFAULT_COMPANION_BRANCH}"

LORA_FREQ=${LORA_FREQ:-869.618}
LORA_BW=${LORA_BW:-62.5}
LORA_SF=${LORA_SF:-8}
LORA_CR=${LORA_CR:-5}
LORA_TX_POWER=${LORA_TX_POWER:-22}

MAX_CONTACTS=${MAX_CONTACTS:-350}
MAX_GROUP_CHANNELS=${MAX_GROUP_CHANNELS:-40}
OFFLINE_QUEUE_SIZE=${OFFLINE_QUEUE_SIZE:-256}
MAX_UNREAD_MSGS=${MAX_UNREAD_MSGS:-32}
MAX_BLOBRECS=${MAX_BLOBRECS:-100}

DISPLAY_CLASS="${DISPLAY_CLASS:-SSD1306Display}"
AUTO_OFF_MILLIS=${AUTO_OFF_MILLIS:-15000}
UI_RECENT_LIST_SIZE=${UI_RECENT_LIST_SIZE:-4}

MESH_PACKET_LOGGING=${MESH_PACKET_LOGGING:-1}
MESH_DEBUG=${MESH_DEBUG:-1}
BRIDGE_DEBUG=${BRIDGE_DEBUG:-0}
BLE_DEBUG_LOGGING=${BLE_DEBUG_LOGGING:-0}
FIRMWARE_VERSION="${FIRMWARE_VERSION:-dev}"
EXTRA_BUILD_FLAGS="${EXTRA_BUILD_FLAGS:-}"
ENABLE_CONSOLE_MIRROR_PATCH=${ENABLE_CONSOLE_MIRROR_PATCH:-0}

ADVERT_NAME="${ADVERT_NAME:-Heltec V3 WiFi}"
ADVERT_LAT=${ADVERT_LAT:-0.0}
ADVERT_LON=${ADVERT_LON:-0.0}
ADMIN_PASSWORD="${ADMIN_PASSWORD:-password}"

UPLOAD_SPEED="${UPLOAD_SPEED:-115200}"

# PlatformIO environment (ensure correct default after config load)
PIO_ENV="${PIO_ENV:-Heltec_v3_companion_radio_wifi}"

# Allow overriding work directory via env or config
WORK_DIR="${WORK_DIR:-$DEFAULT_WORK_DIR}"
REPO_DIR="${REPO_DIR:-${WORK_DIR}/meshcore-firmware}"
ESPTOOL_REPO_URL="${ESPTOOL_REPO_URL:-https://github.com/espressif/esptool.git}"
ESPTOOL_DIR="${ESPTOOL_DIR:-${WORK_DIR}/tools/esptool}"
ESPTOOL_VENV_DIR="${ESPTOOL_VENV_DIR:-${WORK_DIR}/tools/esptool-venv}"

# Functions
log_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

enforce_repeater_profile() {
    if [ "${BUILD_ROLE}" != "repeater" ]; then
        return
    fi

    MESH_PACKET_LOGGING=1
    log_info "Repeater profile active: forcing MESH_PACKET_LOGGING=1"
}

validate_config() {
    log_info "Validating configuration for role: ${BUILD_ROLE}..."
    
    local missing=0
    
    if [ -z "$WIFI_SSID" ]; then
        log_error "WIFI_SSID is required"
        missing=1
    fi
    if [ -z "$WIFI_PASSWORD" ]; then
        log_error "WIFI_PASSWORD is required"
        missing=1
    fi

    if [ -z "$PIO_ENV" ]; then
        log_error "PIO_ENV is required (expected Heltec_v3_companion_radio_wifi or Heltec_v3_repeater)"
        missing=1
    fi

    # Guardrail: this repo is Heltec V3 specific. If a Xiao env is selected via config.env,
    # PlatformIO will happily build it, but the resulting firmware will not work on Heltec.
    if [[ "$PIO_ENV" == *"Xiao"* ]] || [[ "$PIO_ENV" == *"xiao"* ]]; then
        log_error "PIO_ENV points to a Xiao environment (${PIO_ENV}). Set PIO_ENV=Heltec_v3_companion_radio_wifi (or Heltec_v3_repeater)."
        missing=1
    fi

    if [ "$BUILD_ROLE" = "repeater" ]; then
        if [[ "$PIO_ENV" != "Heltec_v3_repeater"* ]]; then
            log_error "BUILD_ROLE=repeater but PIO_ENV=${PIO_ENV}. Expected Heltec_v3_repeater*"
            missing=1
        fi
    else
        if [[ "$PIO_ENV" != "Heltec_v3_companion_radio_wifi"* ]]; then
            log_warn "BUILD_ROLE=companion but PIO_ENV=${PIO_ENV}. Expected Heltec_v3_companion_radio_wifi*"
        fi
    fi
    
    if [ "$BUILD_ROLE" = "repeater" ]; then
        if [ -z "$ADMIN_PASSWORD" ]; then
            log_error "ADMIN_PASSWORD is required for repeater"
            missing=1
        fi
        if [ -z "$GUEST_PASSWORD" ]; then
            log_error "GUEST_PASSWORD is required for repeater"
            missing=1
        fi
        if [ -z "$ADVERT_NAME" ]; then
            log_error "ADVERT_NAME is required for repeater"
            missing=1
        fi
    fi
    
    if [ $missing -eq 1 ]; then
        log_error "Configuration incomplete. Edit config.env and try again."
        exit 1
    fi
    
    log_success "Configuration valid"
}

detect_upload_port() {
    # If UPLOAD_PORT is set and exists, use it
    if [ -n "$UPLOAD_PORT" ] && [ -e "$UPLOAD_PORT" ]; then
        echo "$UPLOAD_PORT"
        return
    fi

    # Priority 1: usbserial devices (CH340, CP210x, FTDI)
    local port
    port=$(ls /dev/cu.usbserial* 2>/dev/null | head -n1)

    if [ -n "$port" ]; then
        echo "$port"
        return
    fi

    # Priority 2: usbmodem devices (native USB CDC)
    port=$(pio device list | grep -Eo '/dev/cu\.usbmodem[^ ]+' | head -n1)

    if [ -n "$port" ]; then
        echo "$port"
        return
    fi

    # Priority 3: Any other cu device except Bluetooth and debug-console
    port=$(pio device list | grep -Eo '/dev/cu\.[^ ]+' | grep -v -E '(debug-console|Bluetooth)' | head -n1)

    if [ -n "$port" ]; then
        echo "$port"
        return
    fi

    # Last fallback: empty
    echo ""
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

sync_firmware_metadata_headers() {
    local build_date
    local firmware_version
    local esc_build_date
    local esc_firmware_version
    local header
    local headers

    build_date="$(date '+%d %b %Y')"
    firmware_version="${FIRMWARE_VERSION}"
    esc_build_date="$(escape_sed_replacement "$build_date")"
    esc_firmware_version="$(escape_sed_replacement "$firmware_version")"

    headers=(
        "${REPO_DIR}/examples/simple_repeater/MyMesh.h"
        "${REPO_DIR}/examples/companion_radio/MyMesh.h"
        "${REPO_DIR}/examples/simple_room_server/MyMesh.h"
        "${REPO_DIR}/examples/simple_sensor/SensorMesh.h"
    )

    for header in "${headers[@]}"; do
        if [ ! -f "$header" ]; then
            continue
        fi

        sed -i.bak -E "s|^([[:space:]]*#define[[:space:]]+FIRMWARE_BUILD_DATE[[:space:]]+).*$|\\1\"${esc_build_date}\"|" "$header"
        sed -i.bak -E "s|^([[:space:]]*#define[[:space:]]+FIRMWARE_VERSION[[:space:]]+).*$|\\1\"${esc_firmware_version}\"|" "$header"
        rm -f "${header}.bak"
    done
}

find_bootstrap_python() {
    local candidates=()
    local py

    if command -v python3 >/dev/null 2>&1; then
        candidates+=("$(command -v python3)")
    fi
    [ -x /usr/local/bin/python3 ] && candidates+=("/usr/local/bin/python3")
    [ -x /opt/homebrew/bin/python3 ] && candidates+=("/opt/homebrew/bin/python3")
    [ -x /usr/bin/python3 ] && candidates+=("/usr/bin/python3")

    for py in "${candidates[@]}"; do
        if "$py" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
            echo "$py"
            return 0
        fi
    done

    return 1
}

ensure_latest_github_esptool() {
    local tools_parent
    local pybin
    tools_parent="$(dirname "$ESPTOOL_DIR")"

    pybin="$(find_bootstrap_python)" || {
        log_error "Python >= 3.10 is required to bootstrap esptool from GitHub"
        return 1
    }

    if [ "$pybin" != "$(command -v python3 2>/dev/null || true)" ]; then
        log_info "Using Python interpreter for esptool bootstrap: $pybin"
    fi

    mkdir -p "$tools_parent"

    if [ -d "${ESPTOOL_DIR}/.git" ]; then
        log_info "Updating local esptool clone..."
        if ! git -C "$ESPTOOL_DIR" pull --ff-only >/dev/null 2>&1; then
            log_warn "Could not fast-forward esptool clone; using current checkout"
        fi
    else
        if [ -d "$ESPTOOL_DIR" ]; then
            log_error "ESPTOOL_DIR exists but is not a git checkout: ${ESPTOOL_DIR}"
            log_error "Remove it manually or set ESPTOOL_DIR to a different path."
            return 1
        fi
        log_info "Cloning latest esptool from GitHub..."
        git clone --depth 1 "$ESPTOOL_REPO_URL" "$ESPTOOL_DIR"
    fi

    if [ -d "$ESPTOOL_VENV_DIR" ]; then
        if ! "${ESPTOOL_VENV_DIR}/bin/python" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
            log_warn "Existing esptool venv uses Python < 3.10; recreating..."
            rm -rf "$ESPTOOL_VENV_DIR"
        fi
    fi

    if [ ! -d "$ESPTOOL_VENV_DIR" ]; then
        log_info "Creating local Python venv for esptool..."
        "$pybin" -m venv "$ESPTOOL_VENV_DIR"
    fi

    log_info "Installing/updating esptool dependencies..."
    "${ESPTOOL_VENV_DIR}/bin/python" -m pip install --upgrade pip >/dev/null
    "${ESPTOOL_VENV_DIR}/bin/python" -m pip install --upgrade "${ESPTOOL_DIR}" >/dev/null

    if [ ! -f "${ESPTOOL_DIR}/esptool.py" ]; then
        log_error "Bootstrapped esptool is missing script: ${ESPTOOL_DIR}/esptool.py"
        return 1
    fi
}

flash_merged_image() {
    local port="$1"
    local merged_path="$2"

    if command -v esptool >/dev/null 2>&1; then
        log_info "Flashing merged image with system esptool (no rebuild)..."
        esptool --chip esp32s3 --port "$port" --baud 460800 write_flash -z 0x0 "$merged_path"
        return
    fi

    if command -v esptool.py >/dev/null 2>&1; then
        log_info "Flashing merged image with system esptool.py (no rebuild)..."
        esptool.py --chip esp32s3 --port "$port" --baud 460800 write_flash -z 0x0 "$merged_path"
        return
    fi

    log_warn "esptool not found in PATH; bootstrapping latest esptool from GitHub..."
    ensure_latest_github_esptool
    log_info "Flashing merged image with bootstrapped esptool (no rebuild)..."
    "${ESPTOOL_VENV_DIR}/bin/python" "${ESPTOOL_DIR}/esptool.py" --chip esp32s3 --port "$port" --baud 460800 write_flash -z 0x0 "$merged_path"
}

print_header() {
    echo -e "${BLUE}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Heltec V3 Companion Radio Builder - WiFi + TCP Serial"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

print_usage() {
        cat << 'EOF'
Usage: ./build.sh [--repeater] --build [--upload] [OPTIONS]

Firmware Roles:
    (default)      Build companion radio (WiFi + LoRa bridge)
    --repeater     Build repeater (mesh relay with admin interface)

Steps:
    --build        Clone/patch/configure (unless skipped) and build firmware
    --upload       Upload previously built firmware (combine with --build to build+upload)

Options:
    --clean        Remove WORK_DIR before running
    --no-clone     Skip repository cloning (use existing checkout)
    --no-patch     Skip applying patches
    --with-console-mirror
                  Repeater only: apply optional console mirror patches (TCP 5003)
    --erase-flash  Erase device flash before upload (recommended when migrating from 1.11)
    --monitor      Upload and start serial monitor
    --build-only   Build without clone/patch/config steps
    --help         Show this help

Examples:
    ./build.sh --build                             # Build companion
    ./build.sh --clean --build --erase-flash --upload
    ./build.sh --repeater --build --upload         # Build repeater
    ./build.sh --repeater --build --with-console-mirror --upload
    ./build.sh --build --upload                    # Build & upload companion
    ./build.sh --upload                            # Upload existing firmware
EOF
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=0
    
    if ! command -v git &> /dev/null; then
        log_error "git not found"
        missing=1
    fi
    
    if ! command -v pio &> /dev/null; then
        log_error "platformio not found - install: pip install platformio"
        missing=1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    log_success "All dependencies found"
}

clone_repository() {
    log_info "Cloning meshcore-firmware repository..."
    
    if [ -d "$REPO_DIR" ]; then
        log_warn "Repository already exists at ${REPO_DIR}"
        log_info "Using existing repository"
        cd "$REPO_DIR"
        git fetch --tags origin || true
        git checkout "$REPO_BRANCH" || true
        git pull origin "$REPO_BRANCH" || true
        return
    fi
    
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
    
    log_success "Repository cloned"
}

apply_patch_file() {
    local patch_file="$1"
    local optional="${2:-0}"
    local patch_name
    patch_name="$(basename "$patch_file")"

    log_info "Applying ${patch_name}..."
    if git apply --check "$patch_file" >/dev/null 2>&1; then
        git apply "$patch_file"
    elif git apply -R --check "$patch_file" >/dev/null 2>&1; then
        log_warn "Patch ${patch_name} already applied - skipping"
    else
        if [ "$optional" = "1" ]; then
            log_warn "Patch ${patch_name} skipped (optional/overlapping on current upstream)"
        else
            log_error "Patch ${patch_name} failed to apply"
            exit 1
        fi
    fi
}

apply_patches() {
    log_info "Applying code patches..."

    cd "$REPO_DIR"

    # Apply patches non-interactively.
    # IMPORTANT: apply only patches relevant to the selected BUILD_ROLE to avoid
    # unrelated patch failures when upstream MeshCore changes.
    local patch_file

    if [ "$BUILD_ROLE" = "repeater" ]; then
        patch_file="$PATCHES_DIR/04-platformio-base.patch"
        [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
        apply_patch_file "$patch_file" 1

        patch_file="$PATCHES_DIR/06-simple-repeater-platformio.patch"
        [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
        apply_patch_file "$patch_file" 0

        patch_file="$PATCHES_DIR/07-simple-repeater-wifi-tcp.patch"
        [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
        apply_patch_file "$patch_file" 0

        patch_file="$PATCHES_DIR/07b-simple-repeater-wifi-tcp-header.patch"
        [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
        apply_patch_file "$patch_file" 0

        patch_file="$PATCHES_DIR/08-add-wifi-macros-defaults.patch"
        [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
        apply_patch_file "$patch_file" 0

        if [ "${ENABLE_CONSOLE_MIRROR_PATCH}" = "1" ]; then
            patch_file="$PATCHES_DIR/09-simple-repeater-tcp-console-header.patch"
            [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
            apply_patch_file "$patch_file" 1

            patch_file="$PATCHES_DIR/09b-simple-repeater-tcp-console.patch"
            [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
            apply_patch_file "$patch_file" 1
        else
            log_info "Skipping console mirror patches (set ENABLE_CONSOLE_MIRROR_PATCH=1 or pass --with-console-mirror)"
        fi
    else
        patch_file="$PATCHES_DIR/11-companion-v114-heltec-zmo.patch"
        [ -f "$patch_file" ] || { log_error "Missing patch file: $(basename "$patch_file")"; exit 1; }
        apply_patch_file "$patch_file" 0
    fi

    log_success "Patches applied"
}

navigate_to_firmware_source() {
    log_info "Preparing firmware source for role: ${BUILD_ROLE}..."
    cd "$REPO_DIR"
    
    # Apply patches for both companion and repeater
    apply_patches
    
    if [ "$BUILD_ROLE" = "repeater" ]; then
        if [ ! -d "examples/simple_repeater" ]; then
            log_error "Repeater firmware not found at examples/simple_repeater"
            exit 1
        fi
        cd "examples/simple_repeater"
        log_success "Ready to build repeater from examples/simple_repeater"
    else
        log_success "Ready to build companion"
    fi
}

configure_build_flags() {
    log_info "Configuring build flags (platformio.ini)..."

    local config_file="${REPO_DIR}/variants/heltec_v3/platformio.ini"

    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: ${config_file}"
        exit 1
    fi

    # Backup original once
    if [ ! -f "${config_file}.orig" ]; then
        cp "$config_file" "${config_file}.orig"
    fi
    sync_firmware_metadata_headers

    # WiFi
    sed -i.bak "s|-D WIFI_SSID='\"[^\"]*\"'|-D WIFI_SSID='\"${WIFI_SSID}\"'|" "$config_file"
    sed -i.bak "s|-D WIFI_PWD='\"[^\"]*\"'|-D WIFI_PWD='\"${WIFI_PASSWORD}\"'|" "$config_file"
    sed -i.bak "s|-D WIFI_PASSWORD='\"[^\"]*\"'|-D WIFI_PASSWORD='\"${WIFI_PASSWORD}\"'|" "$config_file"
    sed -i.bak "s|-D TCP_PORT=[^ ]*|-D TCP_PORT=${TCP_PORT}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*;[[:space:]]*-D[[:space:]]+CONSOLE_PORT=[^ ]+|  -D CONSOLE_PORT=${CONSOLE_PORT}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*-D[[:space:]]+CONSOLE_PORT=[^ ]+|  -D CONSOLE_PORT=${CONSOLE_PORT}|" "$config_file"
    sed -i.bak "s|-D WIFI_DEBUG_LOGGING=[^ ]*|-D WIFI_DEBUG_LOGGING=${WIFI_DEBUG_LOGGING}|" "$config_file"

    # Upload stability
    set_platformio_env_option "$config_file" "$PIO_ENV" "upload_speed" "$UPLOAD_SPEED"

    # LoRa
    sed -i.bak "s|-D LORA_FREQ=[^ ]*|-D LORA_FREQ=${LORA_FREQ}|" "$config_file"
    sed -i.bak "s|-D LORA_BW=[^ ]*|-D LORA_BW=${LORA_BW}|" "$config_file"
    sed -i.bak "s|-D LORA_SF=[^ ]*|-D LORA_SF=${LORA_SF}|" "$config_file"
    sed -i.bak "s|-D LORA_CR=[^ ]*|-D LORA_CR=${LORA_CR}|" "$config_file"
    sed -i.bak "s|-D LORA_TX_POWER=[^ ]*|-D LORA_TX_POWER=${LORA_TX_POWER}|" "$config_file"

    # Memory / queues / contacts
    sed -i.bak "s|-D MAX_CONTACTS=[^ ]*|-D MAX_CONTACTS=${MAX_CONTACTS}|" "$config_file"
    sed -i.bak "s|-D MAX_GROUP_CHANNELS=[^ ]*|-D MAX_GROUP_CHANNELS=${MAX_GROUP_CHANNELS}|" "$config_file"
    sed -i.bak "s|-D OFFLINE_QUEUE_SIZE=[^ ]*|-D OFFLINE_QUEUE_SIZE=${OFFLINE_QUEUE_SIZE}|" "$config_file"
    sed -i.bak "s|-D MAX_UNREAD_MSGS=[^ ]*|-D MAX_UNREAD_MSGS=${MAX_UNREAD_MSGS}|" "$config_file"
    sed -i.bak "s|-D MAX_BLOBRECS=[^ ]*|-D MAX_BLOBRECS=${MAX_BLOBRECS}|" "$config_file"

    # Display
    sed -i.bak "s|-D DISPLAY_CLASS=[^ ]*|-D DISPLAY_CLASS=${DISPLAY_CLASS}|" "$config_file"
    sed -i.bak "s|-D AUTO_OFF_MILLIS=[^ ]*|-D AUTO_OFF_MILLIS=${AUTO_OFF_MILLIS}|" "$config_file"
    sed -i.bak "s|-D UI_RECENT_LIST_SIZE=[^ ]*|-D UI_RECENT_LIST_SIZE=${UI_RECENT_LIST_SIZE}|" "$config_file"

    # Debug
    # MeshCore's platformio.ini often has these commented out by default (prefixed with ';'),
    # so we handle both commented and uncommented cases.
    sed -E -i.bak "s|^[[:space:]]*;[[:space:]]*-D[[:space:]]+MESH_PACKET_LOGGING=[^ ]+|  -D MESH_PACKET_LOGGING=${MESH_PACKET_LOGGING}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*-D[[:space:]]+MESH_PACKET_LOGGING=[^ ]+|  -D MESH_PACKET_LOGGING=${MESH_PACKET_LOGGING}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*;[[:space:]]*-D[[:space:]]+MESH_DEBUG=[^ ]+|  -D MESH_DEBUG=${MESH_DEBUG}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*-D[[:space:]]+MESH_DEBUG=[^ ]+|  -D MESH_DEBUG=${MESH_DEBUG}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*;[[:space:]]*-D[[:space:]]+BRIDGE_DEBUG=[^ ]+|  -D BRIDGE_DEBUG=${BRIDGE_DEBUG}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*-D[[:space:]]+BRIDGE_DEBUG=[^ ]+|  -D BRIDGE_DEBUG=${BRIDGE_DEBUG}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*;[[:space:]]*-D[[:space:]]+BLE_DEBUG_LOGGING=[^ ]+|  -D BLE_DEBUG_LOGGING=${BLE_DEBUG_LOGGING}|" "$config_file"
    sed -E -i.bak "s|^[[:space:]]*-D[[:space:]]+BLE_DEBUG_LOGGING=[^ ]+|  -D BLE_DEBUG_LOGGING=${BLE_DEBUG_LOGGING}|" "$config_file"

    # Identity
    sed -i.bak "s|-D ADVERT_NAME='\"[^\"]*\"'|-D ADVERT_NAME='\"${ADVERT_NAME}\"'|" "$config_file"
    sed -i.bak "s|-D ADVERT_LAT=[^ ]*|-D ADVERT_LAT=${ADVERT_LAT}|" "$config_file"
    sed -i.bak "s|-D ADVERT_LON=[^ ]*|-D ADVERT_LON=${ADVERT_LON}|" "$config_file"
    sed -i.bak "s|-D LORA_FREQ=[^ ]*|-D LORA_FREQ=${LORA_FREQ}|" "$config_file"
    sed -i.bak "s|-D LORA_BW=[^ ]*|-D LORA_BW=${LORA_BW}|" "$config_file"
    sed -i.bak "s|-D LORA_SF=[^ ]*|-D LORA_SF=${LORA_SF}|" "$config_file"
    sed -i.bak "s|-D LORA_CR=[^ ]*|-D LORA_CR=${LORA_CR}|" "$config_file"
    sed -i.bak "s|-D LORA_TX_POWER=[^ ]*|-D LORA_TX_POWER=${LORA_TX_POWER}|" "$config_file"
    rm -f "${config_file}.bak"

    log_success "Build flags configured"
    log_info "  WiFi SSID: ${WIFI_SSID}"
    log_info "  TCP Port:  ${TCP_PORT}"
    log_info "  LoRa:      ${LORA_FREQ} MHz BW ${LORA_BW} SF${LORA_SF} CR${LORA_CR} TX ${LORA_TX_POWER} dBm"
}

configure_repeater_build_flags() {
    log_info "Configuring build flags for repeater (platformio.ini)..."
    local config_file="${REPO_DIR}/examples/simple_repeater/platformio.ini"
    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: ${config_file}"
        exit 1
    fi
    if [ ! -f "${config_file}.orig" ]; then
        cp "$config_file" "${config_file}.orig"
    fi
    sync_firmware_metadata_headers

    # WiFi
    sed -i.bak "s|-D WIFI_SSID=\"[^\"]*\"|-D WIFI_SSID=\"${WIFI_SSID}\"|" "$config_file"
    sed -i.bak "s|-D WIFI_PWD=\"[^\"]*\"|-D WIFI_PWD=\"${WIFI_PASSWORD}\"|" "$config_file"
    sed -i.bak "s|-D TCP_PORT=[^ ]*|-D TCP_PORT=${TCP_PORT}|" "$config_file"
    sed -i.bak "s|-D CONSOLE_PORT=[^ ]*|-D CONSOLE_PORT=${CONSOLE_PORT}|" "$config_file"
    sed -i.bak "s|-D ADMIN_PASSWORD=\"[^\"]*\"|-D ADMIN_PASSWORD=\"${ADMIN_PASSWORD}\"|" "$config_file"
    sed -i.bak "s|-D GUEST_PASSWORD=\"[^\"]*\"|-D GUEST_PASSWORD=\"${GUEST_PASSWORD}\"|" "$config_file"
    sed -i.bak "s|-D ADVERT_NAME=\"[^\"]*\"|-D ADVERT_NAME=\"${ADVERT_NAME}\"|" "$config_file"
    sed -i.bak "s|-D ADVERT_LAT=[^ ]*|-D ADVERT_LAT=${ADVERT_LAT}|" "$config_file"
    sed -i.bak "s|-D ADVERT_LON=[^ ]*|-D ADVERT_LON=${ADVERT_LON}|" "$config_file"
    sed -i.bak "s|-D LORA_FREQ=[^ ]*|-D LORA_FREQ=${LORA_FREQ}|" "$config_file"
    sed -i.bak "s|-D LORA_BW=[^ ]*|-D LORA_BW=${LORA_BW}|" "$config_file"
    sed -i.bak "s|-D LORA_SF=[^ ]*|-D LORA_SF=${LORA_SF}|" "$config_file"
    sed -i.bak "s|-D LORA_CR=[^ ]*|-D LORA_CR=${LORA_CR}|" "$config_file"
    sed -i.bak "s|-D LORA_TX_POWER=[^ ]*|-D LORA_TX_POWER=${LORA_TX_POWER}|" "$config_file"
    rm -f "${config_file}.bak"
    log_success "Build flags configured for repeater"
    log_info "  WiFi SSID: ${WIFI_SSID}"
    log_info "  TCP Port:  ${TCP_PORT}"
    log_info "  LoRa: ${LORA_FREQ} MHz BW ${LORA_BW} SF${LORA_SF} CR${LORA_CR} TX ${LORA_TX_POWER} dBm"
}

build_firmware() {
    log_info "Building firmware for ${PIO_ENV}..."
    local runtime_flags
    runtime_flags="${EXTRA_BUILD_FLAGS:-}"
    
    cd "$REPO_DIR"
    
    # Clean previous build
    if [ -n "$runtime_flags" ]; then
        PLATFORMIO_BUILD_FLAGS="$runtime_flags" pio run -e "$PIO_ENV" --target clean
    else
        pio run -e "$PIO_ENV" --target clean
    fi
    
    # Build
    if [ -n "$runtime_flags" ]; then
        PLATFORMIO_BUILD_FLAGS="$runtime_flags" pio run -e "$PIO_ENV"
    else
        pio run -e "$PIO_ENV"
    fi

    generate_merged_firmware
    
    log_success "Firmware built successfully"
}

generate_merged_firmware() {
    local build_dir
    local firmware_path
    local merged_path
    local runtime_flags
    runtime_flags="${EXTRA_BUILD_FLAGS:-}"

    build_dir="${REPO_DIR}/.pio/build/${PIO_ENV}"
    firmware_path="${build_dir}/firmware.bin"
    merged_path="${build_dir}/firmware-merged.bin"

    if [ ! -f "$firmware_path" ]; then
        log_warn "Skipping merged image generation because firmware.bin is missing"
        return
    fi

    log_info "Generating merged flash image for ${PIO_ENV}..."
    cd "$REPO_DIR"

    if [ -n "$runtime_flags" ]; then
        if ! PLATFORMIO_BUILD_FLAGS="$runtime_flags" pio run -e "$PIO_ENV" -t mergebin >/dev/null; then
            log_warn "Merged image target failed; use bootloader.bin + partitions.bin + firmware.bin for manual flashing"
            return
        fi
    elif ! pio run -e "$PIO_ENV" -t mergebin >/dev/null; then
        log_warn "Merged image target failed; use bootloader.bin + partitions.bin + firmware.bin for manual flashing"
        return
    fi

    if [ -f "$merged_path" ]; then
        log_success "Merged flash image ready: ${merged_path}"
    else
        log_warn "Merged image target completed but ${merged_path} was not created"
    fi
}

upload_firmware() {
    local port
    local build_dir
    local firmware_path
    local merged_path
    port=$(detect_upload_port)

    if [ -z "$port" ]; then
        log_error "No upload port found. Connect the device or set UPLOAD_PORT in config.env"
        exit 1
    fi

    log_info "Uploading firmware to ${port}..."

    build_dir="${REPO_DIR}/.pio/build/${PIO_ENV}"
    firmware_path="${build_dir}/firmware.bin"
    merged_path="${build_dir}/firmware-merged.bin"

    if [ ! -f "$firmware_path" ]; then
        log_error "Firmware artifact missing: ${firmware_path}. Run with --build first."
        exit 1
    fi

    if [ ! -f "$merged_path" ]; then
        log_warn "Merged image missing, generating it now..."
        generate_merged_firmware
    fi

    if [ ! -f "$merged_path" ]; then
        log_error "Merged image is still missing: ${merged_path}"
        exit 1
    fi

    flash_merged_image "$port" "$merged_path"
    
    log_success "Firmware uploaded successfully"
}

erase_flash() {
    local port
    port=$(detect_upload_port)

    if [ -z "$port" ]; then
        log_error "No upload port found. Connect the device or set UPLOAD_PORT in config.env"
        exit 1
    fi

    log_info "Erasing flash on ${port}..."

    local pio_bin
    local pio_python
    local esptool_path

    pio_bin="$(command -v pio)"
    pio_python="$(head -n 1 "$pio_bin" | sed 's/^#!//')"

    if [ ! -x "$pio_python" ]; then
        log_error "Failed to resolve PlatformIO Python interpreter"
        exit 1
    fi

    esptool_path="${HOME}/.platformio/packages/tool-esptoolpy/esptool.py"

    if [ ! -f "$esptool_path" ]; then
        log_error "esptool.py not found at ${esptool_path}"
        exit 1
    fi

    "$pio_python" "$esptool_path" --chip esp32s3 --port "$port" erase_flash

    log_success "Flash erased successfully"
}

monitor_serial() {
    local port
    port=$(detect_upload_port)

    if [ -z "$port" ]; then
        log_error "No serial port found. Connect the device or set UPLOAD_PORT in config.env"
        exit 1
    fi

    log_info "Starting serial monitor on ${port}..."
    log_warn "Press Ctrl+C to exit monitor"
    sleep 1
    
    cd "$REPO_DIR"
    pio device monitor -p "$port" -b 115200
}

show_summary() {
    local firmware_label="Companion Radio (WiFi + LoRa TCP Bridge)"
    if [ "$BUILD_ROLE" = "repeater" ]; then
        firmware_label="Repeater (WiFi + LoRa bridge + TCP console)"
    fi

    echo
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    Build Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "Configuration:"
    echo -e "  Device:       Heltec V3"
    echo -e "  Firmware:     ${firmware_label}"
    echo -e "  WiFi SSID:    ${WIFI_SSID}"
    echo -e "  IP Address:   DHCP (check serial log for assigned IP)"
    if [ "$BUILD_ROLE" = "repeater" ]; then
        echo -e "  TCP Port:     ${TCP_PORT} (serial@tcp / raw packet stream)"
        echo -e "  Console Port: ${CONSOLE_PORT} (repeater configuration/admin console)"
        echo -e "  Mirror 5003:  $([ "${ENABLE_CONSOLE_MIRROR_PATCH}" = "1" ] && echo enabled || echo disabled)"
    else
        echo -e "  TCP Port:     ${TCP_PORT} (serial@tcp endpoint)"
        echo -e "  Console Port: ${CONSOLE_PORT} (companion console/control endpoint)"
        echo -e "  Mirror 5003:  disabled (not used in companion)"
    fi
    echo
    echo -e "Testing:"
    echo -e "  1. Monitor: ${BLUE}pio device monitor -p ${UPLOAD_PORT:-<auto-detect>} -b 115200${NC}"
    echo -e "  2. Connect: ${BLUE}nc <device-ip> ${TCP_PORT}${NC}"
    echo -e "  3. Send:    ${BLUE}python3 mesh_client.py <device-ip> ${TCP_PORT}${NC}"
    echo
    echo -e "Firmware location:"
    echo -e "  ${REPO_DIR}/.pio/build/${PIO_ENV}/firmware.bin"
    echo
}

# Main script
main() {
    print_header
    
    # Parse arguments
    DO_CLONE=-1
    DO_PATCH=-1
    DO_CONFIGURE=-1
    DO_BUILD=0
    DO_UPLOAD=0
    DO_MONITOR=0
    DO_CLEAN=0
    DO_ERASE_FLASH=0
    
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --repeater)
                BUILD_ROLE="repeater"
                PIO_ENV="Heltec_v3_repeater"
                if [ "$REPO_BRANCH" = "$DEFAULT_COMPANION_BRANCH" ]; then
                    REPO_BRANCH="$DEFAULT_REPEATER_BRANCH"
                fi
                shift
                ;;
            --clean)
                DO_CLEAN=1
                shift
                ;;
            --build)
                DO_BUILD=1
                shift
                ;;
            --no-clone)
                DO_CLONE=0
                shift
                ;;
            --no-patch)
                DO_PATCH=0
                shift
                ;;
            --with-console-mirror)
                ENABLE_CONSOLE_MIRROR_PATCH=1
                shift
                ;;
            --upload)
                DO_UPLOAD=1
                shift
                ;;
            --erase-flash)
                DO_ERASE_FLASH=1
                DO_UPLOAD=1
                shift
                ;;
            --monitor)
                DO_MONITOR=1
                DO_UPLOAD=1
                shift
                ;;
            --build-only)
                DO_BUILD=1
                DO_CLONE=0
                DO_PATCH=0
                DO_CONFIGURE=0
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    enforce_repeater_profile
    
    if [ $DO_BUILD -eq 1 ]; then
        [ $DO_CLONE -eq -1 ] && DO_CLONE=1
        [ $DO_PATCH -eq -1 ] && DO_PATCH=1
        [ $DO_CONFIGURE -eq -1 ] && DO_CONFIGURE=1
    else
        [ $DO_CLONE -eq -1 ] && DO_CLONE=0
        [ $DO_PATCH -eq -1 ] && DO_PATCH=0
        [ $DO_CONFIGURE -eq -1 ] && DO_CONFIGURE=0
    fi

    if [ $DO_UPLOAD -eq 1 ] && [ $DO_BUILD -eq 0 ]; then
        local firmware_path="${REPO_DIR}/.pio/build/${PIO_ENV}/firmware.bin"
        if [ -f "$firmware_path" ]; then
            log_info "Upload requested and firmware exists -> skip clone/patch/build"
            DO_CLONE=0
            DO_PATCH=0
            DO_CONFIGURE=0
            DO_BUILD=0
        else
            log_error "Upload requested but firmware is missing. Run with --build first or combine --build --upload."
            exit 1
        fi
    fi

    check_dependencies

    if [ $DO_CLEAN -eq 1 ]; then
        log_info "Cleaning work directory ${WORK_DIR}"
        rm -rf "$WORK_DIR"
    fi
    
    # Only validate config if doing something
    if [ $DO_CLONE -eq 1 ] || [ $DO_PATCH -eq 1 ] || [ $DO_CONFIGURE -eq 1 ] || [ $DO_BUILD -eq 1 ]; then
        validate_config
    fi
    
    [ $DO_CLONE -eq 1 ] && clone_repository
    [ $DO_PATCH -eq 1 ] && navigate_to_firmware_source
    if [ $DO_CONFIGURE -eq 1 ]; then
        if [ "$BUILD_ROLE" = "repeater" ]; then
            configure_repeater_build_flags
        else
            configure_build_flags
        fi
    fi
    [ $DO_BUILD -eq 1 ] && build_firmware
    [ $DO_ERASE_FLASH -eq 1 ] && erase_flash
    [ $DO_UPLOAD -eq 1 ] && upload_firmware
    
    [ $DO_MONITOR -eq 1 ] && monitor_serial
    
    show_summary
}

# Run
main "$@"
