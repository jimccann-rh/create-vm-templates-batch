# Windows Golden Image Template Automation

Automated deployment of Windows Server templates from vCenter Content Library using PowerCLI.

## Overview

This solution provides automated batch deployment of Windows Server templates from a vCenter content library. It features intelligent version tracking, automatic updates when content changes, and comprehensive validation.

## Prerequisites

### 1. PowerShell and PowerCLI

Install PowerShell:
```bash
sudo dnf install -y powershell
```

Install VMware PowerCLI:
```bash
./install-powercli.sh
```

### 2. vCenter Credentials

Store vCenter password in secret-tool:
```bash
secret-tool store --label='vcenter130' service vcenter130
```

### 3. Network Requirements

Ensure the "VM Network" port group exists in vCenter (required for deployment).

## Configuration

### templates.json

The main configuration file that defines which templates to deploy and tracks their versions:

```json
[
  {
    "name": "windows-server-2022-template-ipv6-disabled",
    "enabled": true,
    "description": "Windows Server 2022 with IPv6 disabled",
    "last_deployed_version": null,
    "last_deployed_date": null,
    "content_library_item_id": null
  },
  {
    "name": "windows-server-2025-template-ipv6-disabled",
    "enabled": true,
    "description": "Windows Server 2025 with IPv6 disabled",
    "last_deployed_version": null,
    "last_deployed_date": null,
    "content_library_item_id": null
  }
]
```

**Fields:**
- `name`: Template name in content library (also used as VM/template name)
- `enabled`: Set to `false` to skip this template
- `description`: Human-readable description
- `last_deployed_version`: Auto-updated after deployment
- `last_deployed_date`: Auto-updated after deployment
- `content_library_item_id`: Auto-updated after deployment

## Usage

### Batch Processing (Recommended)

Deploy all enabled templates:
```bash
./create-vm-templates-batch.ps1
```

### Single Template

Deploy a single template:
```bash
./create-vm-template.ps1
```

## Features

### ✅ Intelligent Version Tracking

- Tracks content library version for each template in `templates.json`
- Compares current version with last deployed version
- Automatically redeploys when version changes
- Skips deployment if version unchanged (saves time)

### ✅ Automatic Update Handling

When a template version changes:
1. Detects the version change
2. Removes the old template/VM
3. Deploys the new version
4. Updates version tracking in `templates.json`

### ✅ Comprehensive Validation

- ✓ Verifies connection to vCenter
- ✓ Displays vCenter version information
- ✓ Checks for required "VM Network" port group
- ✓ Validates content library and template existence
- ✓ Confirms datacenter, cluster, and datastore availability

### ✅ Network Configuration

- Automatically checks for "VM Network" port group (Standard or Distributed)
- Configures VM network adapter to use "VM Network" during deployment
- Stops deployment if network is missing

### ✅ Batch Processing

- Processes multiple templates in one run
- Shows progress for each template (`[Template 1 of 2]`)
- Provides detailed summary at completion
- Exit code reflects success/failure count

### ✅ Idempotent Deployment

- Skips templates that already exist with unchanged versions
- Only redeploys when content library version changes
- Prevents duplicate work and saves time

## What It Does

### Step-by-Step Process

1. **[1/3] Get Credentials** - Retrieves vCenter password from secret-tool
2. **[2/3] Connect to vCenter** - Establishes connection via proxy
3. **[3/3] Retrieve vCenter Objects** - Validates datacenter, cluster, datastore, network, folder, content library

For each enabled template:

1. **[1/6] Find Template** - Locates template in content library
2. **[2/6] Check Version** - Compares current vs. last deployed version
3. **[3/6] Check Existence** - Looks for existing template/VM in folder
   - If exists and version unchanged → Skip
   - If exists and version changed → Delete and continue
   - If not exists → Continue to deploy
4. **[4/6] Deploy VM** - Creates VM from content library item
5. **[5/6] Configure Network** - Sets network adapter to "VM Network"
6. **[6/6] Convert to Template** - Powers off VM and converts to template

### Final Steps

- Updates `templates.json` with deployment information
- Displays summary report
- Disconnects from vCenter

## Example Output

```
======================================================================
vCenter Batch Template Creation Script (PowerCLI)
======================================================================

✓ Found 2 enabled template(s) to process:
  - windows-server-2022-template-ipv6-disabled
    Last deployed: v2 on 2026-07-09T14:30:00Z
  - windows-server-2025-template-ipv6-disabled

[Template 1 of 2]
--- Processing: windows-server-2022-template-ipv6-disabled ---
  [2/6] Checking template version...
    Current in library: v2 @ 2026-07-09...
    Last deployed:      v2 @ 2026-07-09...
  ℹ Version unchanged since last deployment
  [3/6] Checking if template already exists...
  ℹ Template already exists and version unchanged - skipping deployment

[Template 2 of 2]
--- Processing: windows-server-2025-template-ipv6-disabled ---
  [2/6] Checking template version...
    Current in library: v3 @ 2026-07-09...
    Last deployed:      v2 @ 2026-07-08...
  ⚠ Version CHANGED: v2 → v3
  [3/6] Checking if template already exists...
  ⚠ Template exists but version changed - removing old template...
  ✓ Old template removed
  [4/6] Deploying VM...
  ✓ VM deployed
  [5/6] Configuring network...
  ✓ Network configured: VM Network
  [6/6] Converting to template...
  ✓ Converted to template!

======================================================================
Summary
======================================================================
Total: 2 | Success: 2 | Failed: 0

✓ windows-server-2022-template-ipv6-disabled
    Deployed version: v2
✓ windows-server-2025-template-ipv6-disabled (version changed)
    Deployed version: v3
======================================================================
```

## Files

| File | Purpose |
|------|---------|
| `templates.json` | Template configuration and version tracking |
| `create-vm-templates-batch.ps1` | Batch processing script (recommended) |
| `install-powercli.sh` | PowerCLI installation script |
| `install-requirements.sh` | Python dependencies (legacy, not used) |

## Environment

- **vCenter Server**: 10.93.76.50
- **Datacenter**: wldn-130-DC
- **Cluster**: wldn-130-cl01
- **Datastore**: wldn-130-cl01-vsan01
- **Folder**: windows-golden-images
- **Content Library**: win-images
- **Network**: VM Network
- **Proxy**: http://127.0.0.1:9999

## Troubleshooting

### PowerCLI Not Installed

```bash
./install-powercli.sh
```

### Network Port Group Missing

Error: `Required port group 'VM Network' not found`

**Solution**: Create the "VM Network" port group in vCenter before running the script.

### Template Not Found in Content Library

**Solution**: Verify template name in content library matches name in `templates.json` exactly.

### Connection Issues

Ensure HTTPS proxy is running on `127.0.0.1:9999` or update the proxy settings in the script.

## Notes

- All operations use the `HTTPS_PROXY` environment variable
- SSL certificate validation is disabled for the proxy connection
- Templates are created in the `windows-golden-images` folder
- Version tracking is stored directly in `templates.json`
- Scripts require PowerShell 7+ and VMware PowerCLI module
- Exit code: 0 = all success, N = number of failures
