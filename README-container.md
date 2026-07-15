# PowerCLI + Twingate Container

This container combines PowerShell, VMware PowerCLI, and Twingate client to run the `create-vm-templates-batch.ps1` script from within a containerized environment.

## Files

- `Dockerfile.powercli-twingate` - Container definition
- `entrypoint-powercli.sh` - Container entrypoint that starts Twingate and runs PowerShell script
- `run-powercli-container.sh` - Script to run the container with Podman
- `build-and-run.sh` - Complete workflow: build and run in one command
- `create-vm-templates-batch.ps1` - PowerShell script (runs inside container)
- `templates.json` - Templates configuration

## Quick Start

```bash
# Set required environment variables
export TWINGATE_SERVICE_KEY='your-twingate-service-key'
export VCENTER_PASSWORD='your-vcenter-password'

# Build and run (all-in-one)
./build-and-run.sh
```

## Manual Steps

### 1. Build the Container

```bash
podman build -f Dockerfile.powercli-twingate -t powercli-twingate:latest .
```

### 2. Run the Container

```bash
# Set environment variables
export TWINGATE_SERVICE_KEY='your-twingate-service-key'
export VCENTER_PASSWORD='your-vcenter-password'

# Run
./run-powercli-container.sh
```

## Environment Variables

### Required

- `TWINGATE_SERVICE_KEY` - Twingate service key for authentication
- `VCENTER_PASSWORD` - vCenter password

### Optional (with defaults)

- `VCENTER_SERVER` (default: `10.93.76.50`)
- `VCENTER_USER` (default: `administrator@vsphere.local`)
- `VCENTER_DATACENTER` (default: `wldn-130-DC`)
- `VCENTER_CLUSTER` (default: `wldn-130-cl01`)
- `VCENTER_DATASTORE` (default: `wldn-130-cl01-vsan01`)
- `VM_FOLDER` (default: `windows-golden-images`)
- `CONTENT_LIBRARY` (default: `win-images`)
- `NETWORK_NAME` (default: `VM Network`)
- `TEMPLATES_CONFIG` (default: `templates.json`)
- `HTTPS_PROXY` (default: `http://127.0.0.1:9999`)

## Advanced Usage

### Using secret-tool for Password

The `build-and-run.sh` script will automatically attempt to retrieve the vCenter password from secret-tool if not set:

```bash
export TWINGATE_SERVICE_KEY='your-key'
# Password will be retrieved from secret-tool
./build-and-run.sh
```

### Override Default Values

```bash
export TWINGATE_SERVICE_KEY='your-key'
export VCENTER_PASSWORD='your-password'
export VCENTER_SERVER='vcenter-130.com'
export VCENTER_DATACENTER='custom-dc'
export TEMPLATES_CONFIG='custom-templates.json'

./build-and-run.sh
```

### Run with Custom Templates Config

```bash
# Create custom templates.json
cp templates.json my-templates.json
# Edit my-templates.json...

# Run with custom config
TEMPLATES_CONFIG=my-templates.json ./run-powercli-container.sh
```

## Container Capabilities

The container runs Twingate in **userspace mode** (HTTP proxy mode):
- **No elevated privileges required** (`NET_ADMIN` not needed)
- **No TUN device needed** (`/dev/net/tun` not required)
- Twingate runs as an HTTP proxy on `127.0.0.1:9999`
- PowerShell/PowerCLI connects through this proxy automatically

## Troubleshooting

### Twingate Connection Issues

Check Twingate logs inside the container:
```bash
podman run -it \
  -e TWINGATE_SERVICE_KEY='your-key' \
  -e VCENTER_SERVER='10.93.76.50' \
  -e VCENTER_USER='administrator@vsphere.local' \
  -e VCENTER_PASSWORD='your-password' \
  powercli-twingate:latest /bin/bash
```

Then manually test:
```bash
# Start Twingate in userspace mode
echo "$TWINGATE_SERVICE_KEY" > /etc/twingate/service_key.json
twingated --http-proxy 127.0.0.1:9999 --tun off &

# Test proxy connectivity
curl -x http://127.0.0.1:9999 -k https://10.93.76.50
```

### PowerCLI Connection Issues

Check if vCenter is reachable through Twingate:
```bash
# Inside container
ping 10.93.76.50
curl -k https://10.93.76.50
```

### View Container Logs

```bash
podman logs powercli-twingate
```

## Security Notes

- Never commit files containing `TWINGATE_SERVICE_KEY` or `VCENTER_PASSWORD`
- Use environment variables or secret management tools
- The container runs **without elevated privileges** (uses Twingate userspace mode)
- Twingate operates as an HTTP proxy, not a kernel-level VPN tunnel

## How It Works

Twingate runs in **userspace networking mode**:
1. `twingated` starts as an HTTP proxy on `127.0.0.1:9999` (no root required)
2. The `--tun off` flag disables TUN device creation
3. PowerShell/PowerCLI uses the proxy via `HTTPS_PROXY` environment variable
4. All vCenter traffic routes through the Twingate proxy automatically
