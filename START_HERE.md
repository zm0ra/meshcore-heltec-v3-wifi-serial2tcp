# Start Here

## Quick path

```bash
# 1. Clone and configure
git clone https://github.com/zm0ra/meshcore-heltec-v3-wifi-serial2tcp.git
cd meshcore-heltec-v3-wifi-serial2tcp
cp config.env.example config.env
nano config.env

# 2. Build and flash the companion
./install.sh

# 3. Or keep the monitor open after flashing
./install.sh --monitor

# 4. Test the raw bridge
python3 mesh_client.py <device-ip> 5002
```

Default companion ports:

- `5000` – native MeshCore WiFi interface
- `5001` – text console
- `5002` – raw RS232Bridge bridge

See [README.md](README.md) for repeater builds, manual build commands, and troubleshooting.
