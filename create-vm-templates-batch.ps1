#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Create multiple Windows Golden Image Templates from vCenter Content Library

.DESCRIPTION
    This script processes a list of templates from templates.json and creates VMs/templates for each

.PARAMETER vCenterServer
    vCenter Server hostname or IP address (default: 10.93.76.50)

.PARAMETER vCenterUser
    vCenter username (default: administrator@vsphere.local)

.PARAMETER vCenterPassword
    vCenter password (if not provided, will use secret-tool)

.PARAMETER vDatacenter
    Datacenter name (default: wldn-130-DC)

.PARAMETER vCluster
    Cluster name (default: wldn-130-cl01)

.PARAMETER vDatastore
    Datastore name (default: wldn-130-cl01-vsan01)

.PARAMETER vFolder
    VM folder name (default: windows-golden-images)

.PARAMETER vContentLibrary
    Content library name (default: win-images)

.PARAMETER vNetwork
    Network/Port group name (default: VM Network)

.PARAMETER vTemplatesConfig
    Templates configuration file (default: templates.json)

.PARAMETER vProxy
    HTTPS proxy URL (default: http://127.0.0.1:9999)

.EXAMPLE
    ./create-vm-templates-batch.ps1

.EXAMPLE
    ./create-vm-templates-batch.ps1 -vCenterServer "vcenter-130.com" -vCenterUser "administrator@vsphere.local" -vDatacenter wldn-130-DC -vCluster wldn-130-cl01
#>

param(
    [Parameter(HelpMessage="vCenter Server hostname or IP")]
    [string]$vCenterServer = "10.93.76.50",

    [Parameter(HelpMessage="vCenter username")]
    [string]$vCenterUser = "administrator@vsphere.local",

    [Parameter(HelpMessage="vCenter password (if not provided, will use secret-tool)")]
    [string]$vCenterPassword = "",

    [Parameter(HelpMessage="Datacenter name")]
    [string]$vDatacenter = "wldn-130-DC",

    [Parameter(HelpMessage="Cluster name")]
    [string]$vCluster = "wldn-130-cl01",

    [Parameter(HelpMessage="Datastore name")]
    [string]$vDatastore = "wldn-130-cl01-vsan01",

    [Parameter(HelpMessage="VM folder name")]
    [string]$vFolder = "windows-golden-images",

    [Parameter(HelpMessage="Content library name")]
    [string]$vContentLibrary = "win-images",

    [Parameter(HelpMessage="Network/Port group name")]
    [string]$vNetwork = "VM Network",

    [Parameter(HelpMessage="Templates configuration file")]
    [string]$vTemplatesConfig = "templates.json",

    [Parameter(HelpMessage="HTTPS proxy URL")]
    [string]$vProxy = "http://127.0.0.1:9999"
)

# Use parameter values for configuration
$Datacenter = $vDatacenter
$Cluster = $vCluster
$Datastore = $vDatastore
$FolderName = $vFolder
$ContentLibrary = $vContentLibrary
$NetworkName = $vNetwork
$TemplatesConfigFile = $vTemplatesConfig

# Set proxy for this session
if ($vProxy) {
    $env:HTTPS_PROXY = $vProxy
    $env:HTTP_PROXY = $vProxy
}


Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "vCenter Batch Template Creation Script (PowerCLI)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# Load templates configuration
Write-Host "`nLoading templates configuration..." -ForegroundColor Yellow
if (-not (Test-Path $TemplatesConfigFile)) {
    Write-Host "❌ Error: Templates configuration file '$TemplatesConfigFile' not found" -ForegroundColor Red
    exit 1
}

try {
    $templatesConfig = Get-Content $TemplatesConfigFile -Raw | ConvertFrom-Json
    $enabledTemplates = $templatesConfig | Where-Object { $_.enabled -eq $true }

    if ($enabledTemplates.Count -eq 0) {
        Write-Host "❌ Error: No enabled templates found in configuration" -ForegroundColor Red
        exit 1
    }

    Write-Host "✓ Found $($enabledTemplates.Count) enabled template(s) to process:" -ForegroundColor Green
    foreach ($tmpl in $enabledTemplates) {
        Write-Host "  - $($tmpl.name)" -ForegroundColor Gray
        if ($tmpl.description) {
            Write-Host "    $($tmpl.description)" -ForegroundColor DarkGray
        }
        if ($tmpl.last_deployed_version) {
            Write-Host "    Last deployed: v$($tmpl.last_deployed_version) on $($tmpl.last_deployed_date)" -ForegroundColor DarkGray
        }
    }
}
catch {
    Write-Host "❌ Error: Could not parse templates configuration: $_" -ForegroundColor Red
    exit 1
}

# Get password from secret-tool or parameter
Write-Host "`n[1/3] Getting vCenter credentials..." -ForegroundColor Yellow
try {
    if ($vCenterPassword) {
        # Use provided password
        $passwordText = $vCenterPassword
        Write-Host "✓ Using provided password" -ForegroundColor Green
    }
    else {
        # Use secret-tool
        $passwordText = & secret-tool lookup service vcenter130
        Write-Host "✓ Password retrieved from secret-tool" -ForegroundColor Green
    }
    $securePassword = ConvertTo-SecureString $passwordText -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vCenterUser, $securePassword)
}
catch {
    Write-Host "❌ Error: Could not retrieve vCenter password" -ForegroundColor Red
    Write-Host "   Provide password via -vCenterPassword parameter or ensure secret-tool is configured" -ForegroundColor Red
    exit 1
}

# Connect to vCenter
Write-Host "`n[2/3] Connecting to vCenter..." -ForegroundColor Yellow
Write-Host "  Server: $vCenterServer" -ForegroundColor Gray
Write-Host "  User: $vCenterUser" -ForegroundColor Gray
try {
    $viServer = Connect-VIServer -Server $vCenterServer -Credential $credential -Force -ErrorAction Stop
    Write-Host "✓ Connected to $($viServer.Name)" -ForegroundColor Green
    Write-Host "  Version: $($viServer.Version) Build $($viServer.Build)" -ForegroundColor Gray
}
catch {
    Write-Host "❌ Error: Could not connect to vCenter: $_" -ForegroundColor Red
    exit 1
}

# Get common vCenter objects
Write-Host "`n[3/3] Retrieving vCenter objects..." -ForegroundColor Yellow

# Get datacenter
$dc = Get-Datacenter -Name $Datacenter -ErrorAction SilentlyContinue
if (-not $dc) {
    Write-Host "❌ Error: Datacenter '$Datacenter' not found" -ForegroundColor Red
    Disconnect-VIServer -Server $viServer -Confirm:$false
    exit 1
}
Write-Host "  ✓ Datacenter: $($dc.Name)" -ForegroundColor Green

# Get/create folder
$vmFolder = Get-Folder -Name "vm" -Location $dc -NoRecursion -ErrorAction SilentlyContinue
$folder = Get-Folder -Name $FolderName -Location $vmFolder -ErrorAction SilentlyContinue
if (-not $folder) {
    try {
        $folder = New-Folder -Name $FolderName -Location $vmFolder -ErrorAction Stop
        Write-Host "  ✓ Created folder: $FolderName" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error creating folder: $_" -ForegroundColor Red
        Disconnect-VIServer -Server $viServer -Confirm:$false
        exit 1
    }
}
else {
    Write-Host "  ✓ Folder: $FolderName" -ForegroundColor Green
}

# Check for required network
$network = Get-VDPortgroup -Name $NetworkName -ErrorAction SilentlyContinue
if (-not $network) {
    $network = Get-VirtualPortGroup -Name $NetworkName -Standard -ErrorAction SilentlyContinue
}
if (-not $network) {
    Write-Host "❌ Error: Required port group '$NetworkName' not found" -ForegroundColor Red
    Disconnect-VIServer -Server $viServer -Confirm:$false
    exit 1
}
$portGroupType = if ($network.GetType().Name -eq "VDPortgroupImpl") { "Distributed" } else { "Standard" }
Write-Host "  ✓ Network: $NetworkName ($portGroupType)" -ForegroundColor Green

# Get content library
$contentLib = Get-ContentLibrary -Name $ContentLibrary -ErrorAction SilentlyContinue
if (-not $contentLib) {
    Write-Host "❌ Error: Content library '$ContentLibrary' not found" -ForegroundColor Red
    Disconnect-VIServer -Server $viServer -Confirm:$false
    exit 1
}
Write-Host "  ✓ Content Library: $($contentLib.Name)" -ForegroundColor Green

# Get cluster and resource pool
$clusterObj = Get-Cluster -Name $Cluster -ErrorAction SilentlyContinue
if (-not $clusterObj) {
    Write-Host "❌ Error: Cluster '$Cluster' not found" -ForegroundColor Red
    Disconnect-VIServer -Server $viServer -Confirm:$false
    exit 1
}
$resourcePool = Get-ResourcePool -Location $clusterObj -Name "Resources" -ErrorAction SilentlyContinue
if (-not $resourcePool) {
    $resourcePool = Get-ResourcePool -Location $clusterObj | Select-Object -First 1
}
Write-Host "  ✓ Cluster: $Cluster" -ForegroundColor Green

# Get datastore
$datastoreObj = Get-Datastore -Name $Datastore -ErrorAction SilentlyContinue
if (-not $datastoreObj) {
    Write-Host "❌ Error: Datastore '$Datastore' not found" -ForegroundColor Red
    Disconnect-VIServer -Server $viServer -Confirm:$false
    exit 1
}
Write-Host "  ✓ Datastore: $Datastore" -ForegroundColor Green

# Process each template
Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "Processing Templates" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$results = @()
$updatedConfig = @()

$templateIndex = 0
foreach ($tmplConfig in $templatesConfig) {
    $templateIndex++
    Write-Host "`n[Template $templateIndex of $($templatesConfig.Count)]" -ForegroundColor DarkGray

    # Create a copy of the config to update
    $updatedTemplate = $tmplConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json

    if (-not $tmplConfig.enabled) {
        Write-Host "--- Skipping (disabled): $($tmplConfig.name) ---" -ForegroundColor DarkGray
        $updatedConfig += $updatedTemplate
        continue
    }

    $templateName = $tmplConfig.name
    $vmName = $templateName

    Write-Host "--- Processing: $templateName ---" -ForegroundColor Cyan

    $result = @{
        TemplateName = $templateName
        Success = $false
        Message = ""
        Version = $null
        VersionChanged = $false
    }

    try {
        # Find template in content library
        Write-Host "  [1/6] Finding template in content library..." -ForegroundColor Yellow
        $template = Get-ContentLibraryItem -Name $templateName -ContentLibrary $contentLib -ErrorAction Stop
        Write-Host "  ✓ Found template: $($template.Name)" -ForegroundColor Green

        # Check version
        Write-Host "  [2/6] Checking template version..." -ForegroundColor Yellow
        $currentVersion = $template.ContentVersion
        $currentItemId = $template.Id
        $currentModifiedDate = $template.LastModifiedTime
        $currentSize = $template.Size

        Write-Host "    Current in library: v$currentVersion @ $currentModifiedDate" -ForegroundColor Gray
        Write-Host "    Size: $([math]::Round($currentSize / 1GB, 2)) GB" -ForegroundColor Gray

        # Compare with last deployed version from config
        $versionChanged = $false
        if ($tmplConfig.last_deployed_version) {
            Write-Host "    Last deployed:      v$($tmplConfig.last_deployed_version) @ $($tmplConfig.last_deployed_date)" -ForegroundColor Gray

            if ($tmplConfig.last_deployed_version -eq $currentVersion) {
                Write-Host "  ℹ Version unchanged since last deployment" -ForegroundColor Cyan
                $versionChanged = $false
            }
            else {
                Write-Host "  ⚠ Version CHANGED: v$($tmplConfig.last_deployed_version) → v$currentVersion" -ForegroundColor Yellow
                $versionChanged = $true
            }
        }
        else {
            Write-Host "  ℹ First deployment (no previous version tracked)" -ForegroundColor Cyan
            $versionChanged = $true
        }

        $result.VersionChanged = $versionChanged

        # Check if template/VM already exists in the folder
        Write-Host "  [3/6] Checking if template already exists..." -ForegroundColor Yellow
        $existingTemplate = Get-Template -Name $vmName -Location $folder -ErrorAction SilentlyContinue
        $existingVM = Get-VM -Name $vmName -Location $folder -ErrorAction SilentlyContinue

        if ($existingTemplate) {
            if (-not $versionChanged) {
                Write-Host "  ℹ Template already exists and version unchanged - skipping deployment" -ForegroundColor Cyan
                $result.Success = $true
                $result.Message = "Template already exists, version unchanged - skipped"
                $result.Version = $currentVersion
                $results += [PSCustomObject]$result
                $updatedConfig += $updatedTemplate
                continue
            }
            else {
                Write-Host "  ⚠ Template exists but version changed - removing old template..." -ForegroundColor Yellow
                Remove-Template -Template $existingTemplate -Confirm:$false -ErrorAction Stop
                Write-Host "  ✓ Old template removed" -ForegroundColor Green
            }
        }
        elseif ($existingVM) {
            if (-not $versionChanged) {
                Write-Host "  ℹ VM already exists and version unchanged - skipping deployment" -ForegroundColor Cyan
                $result.Success = $true
                $result.Message = "VM already exists, version unchanged - skipped"
                $result.Version = $currentVersion
                $results += [PSCustomObject]$result
                $updatedConfig += $updatedTemplate
                continue
            }
            else {
                Write-Host "  ⚠ VM exists but version changed - removing old VM..." -ForegroundColor Yellow
                if ($existingVM.PowerState -eq "PoweredOn") {
                    Stop-VM -VM $existingVM -Confirm:$false -ErrorAction Stop | Out-Null
                }
                Remove-VM -VM $existingVM -DeletePermanently -Confirm:$false -ErrorAction Stop
                Write-Host "  ✓ Old VM removed" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  ✓ No existing template/VM found - will deploy new" -ForegroundColor Green
        }

        # Deploy VM
        Write-Host "  [4/6] Deploying VM..." -ForegroundColor Yellow
        $vm = New-VM -Name $vmName `
                     -ContentLibraryItem $template `
                     -ResourcePool $resourcePool `
                     -Datastore $datastoreObj `
                     -Location $folder `
                     -ErrorAction Stop
        Write-Host "  ✓ VM deployed: $($vm.Name)" -ForegroundColor Green

        # Configure network
        Write-Host "  [5/6] Configuring network..." -ForegroundColor Yellow
        $networkAdapter = Get-NetworkAdapter -VM $vm | Select-Object -First 1
        if ($networkAdapter) {
            Set-NetworkAdapter -NetworkAdapter $networkAdapter -Portgroup $network -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Network configured: $NetworkName" -ForegroundColor Green
        }

        # Power off and convert to template
        Write-Host "  [6/6] Converting to template..." -ForegroundColor Yellow
        if ($vm.PowerState -eq "PoweredOn") {
            Stop-VM -VM $vm -Confirm:$false -ErrorAction Stop | Out-Null
            Write-Host "    Powered off VM" -ForegroundColor Gray
        }

        Set-VM -VM $vm -ToTemplate -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Converted to template!" -ForegroundColor Green

        # Update the config with deployment info
        $updatedTemplate.last_deployed_version = $currentVersion
        $updatedTemplate.last_deployed_date = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $updatedTemplate.content_library_item_id = $currentItemId

        $result.Success = $true
        $result.Message = "Successfully created template"
        $result.Version = $currentVersion
    }
    catch {
        Write-Host "  ❌ Error: $_" -ForegroundColor Red
        $result.Message = $_.Exception.Message
    }

    $results += [PSCustomObject]$result
    $updatedConfig += $updatedTemplate
}

# Save updated configuration with version tracking
Write-Host "`nUpdating templates configuration with deployment info..." -ForegroundColor Yellow
try {
    $updatedConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $TemplatesConfigFile -ErrorAction Stop
    Write-Host "✓ Configuration updated: $TemplatesConfigFile" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Warning: Could not save configuration: $_" -ForegroundColor Yellow
}

# Summary
Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$successCount = ($results | Where-Object { $_.Success -eq $true }).Count
$failCount = ($results | Where-Object { $_.Success -eq $false }).Count

Write-Host "Total: $($results.Count) | Success: $successCount | Failed: $failCount" -ForegroundColor White
Write-Host ""

foreach ($result in $results) {
    $status = if ($result.Success) { "✓" } else { "❌" }
    $color = if ($result.Success) { "Green" } else { "Red" }
    $versionInfo = if ($result.VersionChanged) { " (version changed)" } else { "" }
    Write-Host "$status $($result.TemplateName)$versionInfo" -ForegroundColor $color
    if ($result.Success -and $result.Version) {
        Write-Host "    Deployed version: v$($result.Version)" -ForegroundColor Gray
    }
    if (-not $result.Success) {
        Write-Host "    Error: $($result.Message)" -ForegroundColor Red
    }
}

Write-Host "`n======================================================================" -ForegroundColor Cyan

# Disconnect
Disconnect-VIServer -Server $viServer -Confirm:$false
Write-Host "`n✓ Disconnected from vCenter" -ForegroundColor Green

# Exit with appropriate code
exit $failCount
