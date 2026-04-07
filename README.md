# Heltec V3 WiFi Serial2TCP for MeshCore

Wrapper build system for MeshCore on Heltec V3 that adds a LoRa ↔ WiFi/TCP bridge and a reproducible companion install flow.

The project is ready for both local build-and-flash use and simple automation.

## What you get

- Unified wrapper flow: clone → patch → configure flags → build → erase → upload → monitor.
- Two firmware roles:
  - **Companion**: MeshCore WiFi companion with native TCP on `5000`, text console on `5001`, raw bridge on `5002`.
  - **Repeater**: repeater build flow through the same wrapper, with optional console mirror on `5003` (`--with-console-mirror`).
- Stable RS232Bridge transport (`C0 3E`, big-endian length, Fletcher-16).
- Multi-client TCP support for the raw bridge.
- A one-command companion installer in `install.sh`.

## Practical usage

### Mode 1: Companion

1. Configure `config.env`.
2. Run:

```bash
./install.sh
```

3. Read the IP from UART logs.
4. Use these ports:
   - `5000` – MeshCore native WiFi interface
   - `5001` – text console
   - `5002` – raw RS232Bridge-compatible bridge

### Mode 2: Repeater

1. Configure `config.env`.
2. Run:

```bash
./build.sh --repeater --clean --build --erase-flash --with-console-mirror --upload
```

3. Use the ports exposed by the selected repeater build.

### Most common operational scenarios

- **First clean companion deployment**

```bash
./install.sh --monitor
```

- **Manual clean companion build without the installer**

```bash
./build.sh --clean --build --erase-flash --upload
```

- **Fast iteration without re-cloning**

```bash
./build.sh --build --no-clone
```

- **Upload previously built firmware**

```bash
./build.sh --upload
```

`--upload` flashes the already built merged image and does not trigger a second firmware build.
By default it uses `esptool`/`esptool.py` from your `PATH`; if neither is installed, the wrapper
automatically clones the latest `esptool` from GitHub into `build/tools/esptool`, creates a local
Python virtual environment, and uses that copy for flashing.

- **Build artifacts only**

```bash
./build.sh --build
```

- **Build without patching**

```bash
./build.sh --build --no-patch
```

## Requirements

- Heltec V3 with LoRa radio
- USB cable for flashing
- 2.4 GHz WiFi network
- macOS or Linux with `git`, `python3`, and `platformio` (`pio`)

## Quick start

### 1. Clone the repository and configure it

```bash
git clone https://github.com/zm0ra/meshcore-heltec-v3-wifi-serial2tcp.git
cd meshcore-heltec-v3-wifi-serial2tcp
cp config.env.example config.env
nano config.env
```

Minimum settings:

```bash
WIFI_SSID="YourNetwork"
WIFI_PASSWORD="YourPassword"
LORA_FREQ=869.618
UPLOAD_PORT="/dev/cu.usbserial-0001"   # optional, auto-detect works when empty
```

### 2. Build and upload

```bash
# Companion
./install.sh

# Companion with serial monitor
./install.sh --monitor

# Repeater
./build.sh --repeater --build --upload
```

After boot, look for log lines like these:

```text
[WIFI] Connected to '<ssid>'
[WIFI] DHCP address: <ip>
[WIFI] Native interface: nc <ip> 5000
[WIFI] Console: nc <ip> 5001
[WIFI] Connect with: nc <ip> 5002
```

### 3. Test connectivity

```bash
# Raw bridge
nc -vz <device-ip> 5002

# Text console
nc -vz <device-ip> 5001

# Native MeshCore WiFi interface
nc -vz <device-ip> 5000
```

## build.sh options

```text
Usage: ./build.sh [--repeater] --build [--upload] [OPTIONS]
```

Key options:

- `--repeater` – switch role to repeater.
- `--build` – run the build pipeline.
- `--upload` – upload existing firmware, or build and upload when combined with `--build`.
- `--with-console-mirror` – repeater only, enables optional TCP mirror on `5003`.
- `--monitor` – start the serial monitor after upload.
- `--clean` – remove the working directory.
- `--no-clone` – skip upstream repo cloning.
- `--no-patch` – skip patch application.
- `--erase-flash` – erase flash before upload.
- `--build-only` – build only, without clone, patch, or configure steps.

Examples:

```bash
./build.sh --clean --build
./build.sh --repeater --build --with-console-mirror --upload --monitor
./build.sh --build --no-clone --no-patch
./build.sh --upload
```

## Ports and operating modes

| Mode | Port | Purpose |
|------|------|---------|
| Companion | `5000` | Native MeshCore WiFi interface |
| Companion | `5001` | Text console |
| Companion | `5002` | Raw bridge (RS232Bridge) |

## Configuration (`config.env`)

Key variables:

- **WiFi / TCP**: `WIFI_SSID`, `WIFI_PASSWORD`, `TCP_PORT`, `WIFI_DEBUG_LOGGING`
- **LoRa**: `LORA_FREQ`, `LORA_BW`, `LORA_SF`, `LORA_CR`, `LORA_TX_POWER`
- **Identity**: `ADVERT_NAME`, `ADVERT_LAT`, `ADVERT_LON`, `ADMIN_PASSWORD`, `GUEST_PASSWORD`
- **Debug**: `MESH_PACKET_LOGGING`, `MESH_DEBUG`, `BRIDGE_DEBUG`, `BLE_DEBUG_LOGGING`
- **Build orchestration**: `BUILD_ROLE`, `PIO_ENV`, `UPLOAD_SPEED`
- **Infra**: `UPLOAD_PORT`, `REPO_URL`, `REPO_BRANCH`, `WORK_DIR`

`config.env.example` contains the full set and default values.

## TCP protocol (RS232Bridge)

Each frame looks like this:

```text
[Magic:2] [Length:2] [Payload:N] [Checksum:2] [Newline:1]
  C0 3E      00 15      ...         D9 B0        0A
```

- `Magic`: always `C0 3E`
- `Length`: big-endian payload length
- `Checksum`: Fletcher-16 over `Payload`
- TCP input ignores `\r` and `\n`
- TCP output appends `\n` after each frame

## What gets patched

Primary companion patch:

- `11-companion-v114-heltec-zmo.patch`

It targets upstream `companion-v1.14.0` and adds:

- firmware suffix `v1.14.0-heltec-zmo`
- raw TCP bridge on `5002`
- text console on `5001`
- WiFi boot logs with IP and port hints

The wrapper also contains repeater-related patch handling used by `build.sh`.

## Typical developer workflow

```bash
# full clean companion build
./build.sh --clean --build

# upload already-built firmware only
./build.sh --upload

# monitor logs after flashing
./install.sh --monitor
```

Artifacts:

- `build/meshcore-firmware/.pio/build/<PIO_ENV>/firmware.bin`
- `build/meshcore-firmware/.pio/build/<PIO_ENV>/firmware.elf`

## Troubleshooting (quick)

### 1. Upload fails partway through

- Symptom: `The chip stopped responding` during `esptool` write.
- Typical fixes:
  - lower `UPLOAD_SPEED`
  - use a shorter or better USB cable
  - retry with a clean flash erase
  - reconnect the board and flash again

### 2. Reboot loop after flashing

- Symptom: repeated `rst:0x3 (RTC_SW_SYS_RST)` on boot.
- Fix: erase flash before upload. This is why `install.sh` uses `--erase-flash`.

### 3. No WiFi connection

- check `WIFI_SSID` and `WIFI_PASSWORD`
- use 2.4 GHz WiFi only
- read UART logs with `pio device monitor -b 115200`

### 4. Missing upload port

```bash
pio device list
```

If auto-detection fails, set `UPLOAD_PORT` in `config.env`.

## File layout

```text
meshcore-heltec-v3-wifi-serial2tcp/
├── build.sh
├── install.sh
├── config.env.example
├── START_HERE.md
├── README.md
├── mesh_client.py
├── patches/
│   ├── 11-companion-v114-heltec-zmo.patch
│   └── ...
└── build/
    └── meshcore-firmware/
```

## License

Based on MeshCore. See the upstream project for licensing details.

**Need help?** Open an issue on GitHub or check the [MeshCore Discord](https://discord.gg/BMwCtwHj5V).
