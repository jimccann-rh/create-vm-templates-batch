#!/bin/bash
set -e

echo "======================================================================="
echo "PowerCLI + Twingate Container (Userspace Mode)"
echo "======================================================================="

# Check required environment variables
if [ -z "$TWINGATE_SERVICE_KEY" ]; then
    echo "ERROR: TWINGATE_SERVICE_KEY environment variable is required"
    exit 1
fi

if [ -z "$VCENTER_SERVER" ]; then
    echo "ERROR: VCENTER_SERVER environment variable is required"
    exit 1
fi

if [ -z "$VCENTER_USER" ]; then
    echo "ERROR: VCENTER_USER environment variable is required"
    exit 1
fi

if [ -z "$VCENTER_PASSWORD" ]; then
    echo "ERROR: VCENTER_PASSWORD environment variable is required"
    exit 1
fi

# Set runtime dir for OpenShift (random UID has no /run/user/<uid>)
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$XDG_RUNTIME_DIR"

# Persistent storage for templates config
# If /data is mounted (PVC in OpenShift, -v locally), use it for templates.json
# so last_deployed_version and last_deployed_date persist across runs.
# First run seeds from the built-in copy; subsequent runs reuse the persisted file.
PERSIST_DIR="/data"
PERSIST_TEMPLATES="$PERSIST_DIR/templates.json"
if [ -d "$PERSIST_DIR" ] && [ -w "$PERSIST_DIR" ]; then
    if [ ! -f "$PERSIST_TEMPLATES" ]; then
        cp /workspace/templates.json "$PERSIST_TEMPLATES"
        echo "✓ Seeded $PERSIST_TEMPLATES from built-in config"
    else
        echo "✓ Using persistent templates config: $PERSIST_TEMPLATES"
    fi
    export TEMPLATES_CONFIG="$PERSIST_TEMPLATES"
else
    echo "ℹ No persistent storage at $PERSIST_DIR - using built-in config (changes will not persist)"
fi

# Write service key directly to where twingated expects it
echo "Setting up Twingate..."
echo "$TWINGATE_SERVICE_KEY" > /etc/twingate/service_key.json

# Clear any proxy vars so twingated can reach its control plane directly
unset HTTPS_PROXY HTTP_PROXY http_proxy https_proxy NO_PROXY no_proxy

# Start Twingate in userspace mode (HTTP proxy, no TUN device)
echo "Starting Twingate in userspace mode (HTTP proxy on 127.0.0.1:9999)..."
twingated --http-proxy 127.0.0.1:9999 --tun off &
TWINGATE_PID=$!

# Wait for Twingate to come online and load resource policies
echo "Waiting for Twingate to initialize..."
RETRIES=0
MAX_RETRIES=30
while [ $RETRIES -lt $MAX_RETRIES ]; do
    if ! ps -p $TWINGATE_PID > /dev/null; then
        echo "ERROR: Twingate daemon failed to start"
        exit 1
    fi
    # Check if twingated is online and has loaded resources
    if curl -s --proxy http://127.0.0.1:9999 -k -o /dev/null -w "%{http_code}" "https://$VCENTER_SERVER" 2>/dev/null | grep -qE "^(200|301|302|401|403|500)"; then
        echo "✓ Twingate proxy can reach $VCENTER_SERVER"
        break
    fi
    RETRIES=$((RETRIES + 1))
    echo "  Waiting for Twingate tunnel... ($RETRIES/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "WARNING: Could not verify connectivity to $VCENTER_SERVER through proxy, continuing anyway..."
fi

# Remove the service key from filesystem now that twingated has read it
rm -f /etc/twingate/service_key.json

echo "✓ Twingate running in userspace mode (PID: $TWINGATE_PID)"

# Set proxy and SSL env vars for .NET / PowerShell
export HTTPS_PROXY="http://127.0.0.1:9999"
export HTTP_PROXY="http://127.0.0.1:9999"
export NO_PROXY="localhost"

echo ""
echo "======================================================================="
echo "Running PowerShell script: create-vm-templates-batch.ps1"
echo "======================================================================="
echo ""

# Run the PowerShell script with environment variables
pwsh /workspace/create-vm-templates-batch.ps1 \
    -vCenterServer "$VCENTER_SERVER" \
    -vCenterUser "$VCENTER_USER" \
    -vCenterPassword "$VCENTER_PASSWORD" \
    -vDatacenter "${VCENTER_DATACENTER:-wldn-130-DC}" \
    -vCluster "${VCENTER_CLUSTER:-wldn-130-cl01}" \
    -vDatastore "${VCENTER_DATASTORE:-wldn-130-cl01-vsan01}" \
    -vFolder "${VM_FOLDER:-windows-golden-images}" \
    -vContentLibrary "${CONTENT_LIBRARY:-win-images}" \
    -vNetwork "${NETWORK_NAME:-VM Network}" \
    -vTemplatesConfig "${TEMPLATES_CONFIG:-templates.json}" \
    -vProxy "http://127.0.0.1:9999"

# Capture exit code
EXIT_CODE=$?

echo ""
echo "======================================================================="
echo "Script completed with exit code: $EXIT_CODE"
echo "======================================================================="

# Stop Twingate daemon
echo "Stopping Twingate client..."
if ps -p $TWINGATE_PID > /dev/null; then
    kill $TWINGATE_PID
    wait $TWINGATE_PID 2>/dev/null || true
fi

exit $EXIT_CODE
