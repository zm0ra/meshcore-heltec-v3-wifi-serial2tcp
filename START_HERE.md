# Start here

## Quick Build

```bash
# 1. Edit WiFi settings
cp config.env.example config.env
nano config.env    # Set WIFI_SSID and WIFI_PASSWORD

# 2. Build and upload
./build.sh --build --upload

# 3. Monitor
pio device monitor -b 115200

# 4. Find device IP in serial output, then connect:
python3 mesh_client.py <device-ip> 5002
```

See [README.md](README.md) for detailed documentation.
