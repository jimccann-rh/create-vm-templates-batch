#!/bin/bash
# Install VMware PowerCLI module for PowerShell

echo "========================================================================"
echo "Installing VMware PowerCLI"
echo "========================================================================"

echo ""
echo "Checking if PowerShell is installed..."
if ! command -v pwsh &> /dev/null; then
    echo "❌ PowerShell (pwsh) is not installed"
    echo ""
    echo "Install PowerShell first:"
    echo "  sudo dnf install -y powershell"
    exit 1
fi

echo "✓ PowerShell is installed: $(pwsh --version)"

echo ""
echo "Installing VMware PowerCLI module..."
pwsh -Command "Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ PowerCLI installed successfully!"
    echo ""
    echo "Verifying installation..."
    pwsh -Command "Get-Module -ListAvailable VMware.PowerCLI | Select-Object Name, Version"
    echo ""
    echo "========================================================================"
    echo "You can now run: ./create-vm-template.ps1"
    echo "========================================================================"
else
    echo ""
    echo "❌ PowerCLI installation failed"
    exit 1
fi
