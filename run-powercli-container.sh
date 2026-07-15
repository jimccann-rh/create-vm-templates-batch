#!/bin/bash

# Script to run PowerCLI + Twingate container with Podman
# Usage: ./run-powercli-container.sh

set -e

# Default values (can be overridden by environment variables)
TWINGATE_SERVICE_KEY="${TWINGATE_SERVICE_KEY:-}"
VCENTER_SERVER="${VCENTER_SERVER:-10.93.76.50}"
VCENTER_USER="${VCENTER_USER:-administrator@vsphere.local}"
VCENTER_PASSWORD="${VCENTER_PASSWORD:-}"
VCENTER_DATACENTER="${VCENTER_DATACENTER:-wldn-130-DC}"
VCENTER_CLUSTER="${VCENTER_CLUSTER:-wldn-130-cl01}"
VCENTER_DATASTORE="${VCENTER_DATASTORE:-wldn-130-cl01-vsan01}"
VM_FOLDER="${VM_FOLDER:-windows-golden-images}"
CONTENT_LIBRARY="${CONTENT_LIBRARY:-win-images}"
NETWORK_NAME="${NETWORK_NAME:-VM Network}"
TEMPLATES_CONFIG="${TEMPLATES_CONFIG:-templates.json}"
HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:9999}"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-powercli-twingate:latest}"

# Check for required variables
if [ -z "$TWINGATE_SERVICE_KEY" ]; then
    echo "ERROR: TWINGATE_SERVICE_KEY environment variable is required"
    echo "Usage: TWINGATE_SERVICE_KEY=your-key ./run-powercli-container.sh"
    exit 1
fi

if [ -z "$VCENTER_PASSWORD" ]; then
    echo "ERROR: VCENTER_PASSWORD environment variable is required"
    echo "You can also use secret-tool to retrieve it"
    exit 1
fi

echo "======================================================================="
echo "Running PowerCLI + Twingate Container"
echo "======================================================================="
echo "Container Image: $CONTAINER_IMAGE"
echo "vCenter Server: $VCENTER_SERVER"
echo "vCenter User: $VCENTER_USER"
echo "Datacenter: $VCENTER_DATACENTER"
echo "Cluster: $VCENTER_CLUSTER"
echo "Datastore: $VCENTER_DATASTORE"
echo "Templates Config: $TEMPLATES_CONFIG"
echo "Persistent Data: $(pwd)/data"
echo "======================================================================="
echo ""

# Create local persistent data directory for templates.json
mkdir -p "$(pwd)/data"

# Run container with Podman (no elevated privileges needed - userspace mode)
podman run --rm --replace -it \
    --name powercli-twingate \
    --network=host \
    -v "$(pwd)/data:/data:Z" \
    -e TWINGATE_SERVICE_KEY="$TWINGATE_SERVICE_KEY" \
    -e VCENTER_SERVER="$VCENTER_SERVER" \
    -e VCENTER_USER="$VCENTER_USER" \
    -e VCENTER_PASSWORD="$VCENTER_PASSWORD" \
    -e VCENTER_DATACENTER="$VCENTER_DATACENTER" \
    -e VCENTER_CLUSTER="$VCENTER_CLUSTER" \
    -e VCENTER_DATASTORE="$VCENTER_DATASTORE" \
    -e VM_FOLDER="$VM_FOLDER" \
    -e CONTENT_LIBRARY="$CONTENT_LIBRARY" \
    -e NETWORK_NAME="$NETWORK_NAME" \
    -e TEMPLATES_CONFIG="$TEMPLATES_CONFIG" \
    -e HTTPS_PROXY="$HTTPS_PROXY" \
    "$CONTAINER_IMAGE"

echo ""
echo "Container execution completed"
