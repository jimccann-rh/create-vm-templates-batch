#!/bin/bash

# Complete workflow: Build and run the PowerCLI + Twingate container
# Usage: ./build-and-run.sh

set -e

CONTAINER_IMAGE="powercli-twingate:latest"

echo "======================================================================="
echo "Step 1: Building container image"
echo "======================================================================="
podman build -f Dockerfile.powercli-twingate -t "$CONTAINER_IMAGE" .

echo ""
echo "======================================================================="
echo "Step 2: Running container"
echo "======================================================================="
echo ""

# Check if environment variables are set
if [ -z "$TWINGATE_SERVICE_KEY" ]; then
    echo "ERROR: TWINGATE_SERVICE_KEY not set"
    echo ""
    echo "Usage:"
    echo "  export TWINGATE_SERVICE_KEY='your-key'"
    echo "  export VCENTER_PASSWORD='your-password'"
    echo "  ./build-and-run.sh"
    echo ""
    echo "Optional environment variables:"
    echo "  VCENTER_SERVER (default: 10.93.76.50)"
    echo "  VCENTER_USER (default: administrator@vsphere.local)"
    echo "  VCENTER_DATACENTER (default: wldn-130-DC)"
    echo "  VCENTER_CLUSTER (default: wldn-130-cl01)"
    echo "  VCENTER_DATASTORE (default: wldn-130-cl01-vsan01)"
    echo "  VM_FOLDER (default: windows-golden-images)"
    echo "  CONTENT_LIBRARY (default: win-images)"
    echo "  NETWORK_NAME (default: VM Network)"
    echo "  TEMPLATES_CONFIG (default: templates.json)"
    echo "  HTTPS_PROXY (default: http://127.0.0.1:9999)"
    exit 1
fi

if [ -z "$VCENTER_PASSWORD" ]; then
    echo "ERROR: VCENTER_PASSWORD not set"
    echo "Attempting to retrieve from secret-tool..."
    VCENTER_PASSWORD=$(secret-tool lookup service vcenter130 2>/dev/null || true)
    if [ -z "$VCENTER_PASSWORD" ]; then
        echo "ERROR: Could not retrieve password from secret-tool"
        exit 1
    fi
    echo "✓ Password retrieved from secret-tool"
    export VCENTER_PASSWORD
fi

# Create local persistent data directory for templates.json
mkdir -p data

# Run the container
CONTAINER_IMAGE="$CONTAINER_IMAGE" ./run-powercli-container.sh
