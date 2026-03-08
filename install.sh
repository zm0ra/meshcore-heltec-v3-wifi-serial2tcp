#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
CONFIG_EXAMPLE="${SCRIPT_DIR}/config.env.example"

print_usage() {
    cat << 'EOF'
Usage: ./install.sh [OPTIONS]

Ready-made install flow for Heltec V3 companion firmware based on MeshCore 1.14.

What it does:
  1. Clones upstream MeshCore tag companion-v1.14.0
  2. Applies the heltec-zmo companion patch
  3. Builds Heltec_v3_companion_radio_wifi
  4. Erases flash
  5. Uploads firmware

Options:
  --monitor   Open serial monitor after upload
  --help      Show this help

Before first run:
  cp config.env.example config.env
  edit WIFI_SSID / WIFI_PASSWORD / LORA_FREQ / UPLOAD_PORT

Example:
  ./install.sh
  ./install.sh --monitor
EOF
}

if [ "${1:-}" = "--help" ]; then
    print_usage
    exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
    echo "Created config.env from config.env.example"
    echo "Edit config.env and run ./install.sh again"
    exit 0
fi

export BUILD_ROLE="companion"
export PIO_ENV="Heltec_v3_companion_radio_wifi"
export REPO_URL="https://github.com/meshcore-dev/MeshCore"
export REPO_BRANCH="companion-v1.14.0"

exec "$SCRIPT_DIR/build.sh" --clean --build --erase-flash --upload "$@"
