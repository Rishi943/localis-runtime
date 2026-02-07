#Requires -Version 5.1

<#
.SYNOPSIS
    Builds the Localis Windows installer using Inno Setup.

.DESCRIPTION
    This script automates the process of building the Localis installer:
    - Verifies required build outputs exist
    - Extracts runtime pack if needed
    - Determines version from environment, git, or defaults
    - Invokes Inno Setup Compiler (ISCC) to create the installer

.PARAMETER Version
    Override the version number. If not specified, uses LOCALIS_VERSION env var,
    git describe, or defaults to 0.0.0

.EXAMPLE
    .\scripts\build_installer.ps1
    .\scripts\build_installer.ps1 -Version "1.0.0"

.NOTES
    Requires: Inno Setup 6.x installed
#>

[CmdletBinding()]
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$SCRIPT_ROOT = Split-Path -Parent $PSScriptRoot
$DIST_DIR = Join-Path $SCRIPT_ROOT "dist"
$RUNTIME_PACK_ZIP = Join-Path $DIST_DIR "LocalisRuntimePack.zip"
$RUNTIME_DIR = Join-Path $DIST_DIR "runtime"
$LOCALIS_EXE = Join-Path $DIST_DIR "Localis\Localis.exe"
$INSTALLER_SCRIPT = Join-Path $SCRIPT_ROOT "installer.iss"
$OUTPUT_DIR = Join-Path $SCRIPT_ROOT "output"

# Inno Setup default installation path
$ISCC_DEFAULT_PATH = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "===================================================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Get-LocalisVersion {
    <#
    .SYNOPSIS
        Determines the version to use for the installer.

    .DESCRIPTION
        Version detection order:
        1. Parameter override
        2. LOCALIS_VERSION environment variable
        3. Git describe --tags --always (sanitized to semver)
        4. Fallback to 0.0.0
    #>
    param([string]$VersionParam)

    # 1. Parameter override
    if ($VersionParam) {
        Write-Info "Using version from parameter: $VersionParam"
        return $VersionParam
    }

    # 2. Environment variable
    $envVersion = $env:LOCALIS_VERSION
    if ($envVersion) {
        Write-Info "Using version from LOCALIS_VERSION env var: $envVersion"
        return $envVersion
    }

    # 3. Git describe (if available)
    try {
        $gitAvailable = Get-Command git -ErrorAction SilentlyContinue
        if ($gitAvailable) {
            $gitVersion = & git describe --tags --always 2>&1
            if ($LASTEXITCODE -eq 0) {
                # Sanitize git version to semver-ish format
                # Remove leading 'v' if present
                $gitVersion = $gitVersion -replace '^v', ''

                # If it's just a commit hash (no tags), prefix with 0.0.0-
                if ($gitVersion -match '^[0-9a-f]{7,}$') {
                    $gitVersion = "0.0.0-$gitVersion"
                }

                Write-Info "Using version from git: $gitVersion"
                return $gitVersion
            }
        }
    }
    catch {
        Write-Info "Git not available or no tags found"
    }

    # 4. Fallback
    Write-Info "Using fallback version: 0.0.0"
    return "0.0.0"
}

function Find-ISCC {
    <#
    .SYNOPSIS
        Locates the Inno Setup Compiler executable.

    .DESCRIPTION
        Searches for ISCC.exe in:
        1. Default installation path (C:\Program Files (x86)\Inno Setup 6\)
        2. System PATH

    .OUTPUTS
        String path to ISCC.exe, or $null if not found
    #>

    # Try default path first
    if (Test-Path $ISCC_DEFAULT_PATH) {
        Write-Success "Found ISCC at default location: $ISCC_DEFAULT_PATH"
        return $ISCC_DEFAULT_PATH
    }

    # Try to find in PATH
    try {
        $isccCmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($isccCmd) {
            $isccPath = $isccCmd.Source
            Write-Success "Found ISCC in PATH: $isccPath"
            return $isccPath
        }
    }
    catch {
        # Not in PATH
    }

    return $null
}

# ============================================================================
# MAIN BUILD PROCESS
# ============================================================================

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "                                                                        " -ForegroundColor Magenta
Write-Host "                    Localis Installer Builder                          " -ForegroundColor Magenta
Write-Host "                                                                        " -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host ""

# ============================================================================
# STEP 1: Verify required build outputs
# ============================================================================

Write-Step "Step 1: Verifying build outputs"

# Check for Localis.exe (required)
if (-not (Test-Path $LOCALIS_EXE)) {
    Write-ErrorMsg "Localis.exe not found at: $LOCALIS_EXE"
    Write-Host ""
    Write-Host "Please build the PyInstaller executable first:" -ForegroundColor Yellow
    Write-Host "  pyinstaller LocalisLauncher.spec" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
Write-Success "Found Localis.exe"

# Check for runtime (zip or directory)
$hasRuntimeZip = Test-Path $RUNTIME_PACK_ZIP
$hasRuntimeDir = Test-Path $RUNTIME_DIR

if (-not $hasRuntimeZip -and -not $hasRuntimeDir) {
    Write-ErrorMsg "Runtime pack not found"
    Write-Host ""
    Write-Host "Missing both:" -ForegroundColor Yellow
    Write-Host "  - $RUNTIME_PACK_ZIP" -ForegroundColor Gray
    Write-Host "  - $RUNTIME_DIR" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Please build the runtime pack first:" -ForegroundColor Yellow
    Write-Host "  .\build_runtime_pack_windows.ps1" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

if ($hasRuntimeZip) {
    Write-Success "Found runtime pack zip: $RUNTIME_PACK_ZIP"
}
if ($hasRuntimeDir) {
    Write-Success "Found runtime directory: $RUNTIME_DIR"
}

# Check for installer.iss
if (-not (Test-Path $INSTALLER_SCRIPT)) {
    Write-ErrorMsg "Installer script not found: $INSTALLER_SCRIPT"
    Write-Host ""
    Write-Host "The installer.iss file is required to build the installer." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
Write-Success "Found installer script: installer.iss"

# ============================================================================
# STEP 2: Ensure runtime directory exists
# ============================================================================

Write-Step "Step 2: Preparing runtime directory"

if (-not $hasRuntimeDir) {
    Write-Info "Extracting runtime pack to $RUNTIME_DIR..."

    try {
        # Create dist directory if it doesn't exist
        if (-not (Test-Path $DIST_DIR)) {
            New-Item -ItemType Directory -Path $DIST_DIR -Force | Out-Null
        }

        # Extract zip
        Expand-Archive -Path $RUNTIME_PACK_ZIP -DestinationPath $DIST_DIR -Force

        # Verify extraction
        if (Test-Path $RUNTIME_DIR) {
            Write-Success "Runtime pack extracted successfully"
        }
        else {
            Write-ErrorMsg "Extraction succeeded but runtime directory not found"
            Write-Host "Expected: $RUNTIME_DIR" -ForegroundColor Yellow
            exit 1
        }
    }
    catch {
        Write-ErrorMsg "Failed to extract runtime pack: $_"
        exit 1
    }
}
else {
    Write-Success "Runtime directory already exists"
}

# Verify critical runtime files
$pythonExe = Join-Path $RUNTIME_DIR "python\python.exe"
$gitExe = Join-Path $RUNTIME_DIR "git\bin\git.exe"

if (-not (Test-Path $pythonExe)) {
    Write-ErrorMsg "Runtime validation failed: python.exe not found at $pythonExe"
    exit 1
}
if (-not (Test-Path $gitExe)) {
    Write-ErrorMsg "Runtime validation failed: git.exe not found at $gitExe"
    exit 1
}

Write-Success "Runtime directory validated"

# ============================================================================
# STEP 3: Determine version
# ============================================================================

Write-Step "Step 3: Determining version"

$installerVersion = Get-LocalisVersion -VersionParam $Version
Write-Host ""
Write-Host "Installer Version: $installerVersion" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 4: Locate Inno Setup Compiler
# ============================================================================

Write-Step "Step 4: Locating Inno Setup Compiler"

$isccPath = Find-ISCC

if (-not $isccPath) {
    Write-ErrorMsg "Inno Setup Compiler (ISCC.exe) not found"
    Write-Host ""
    Write-Host "Please install Inno Setup 6.x from:" -ForegroundColor Yellow
    Write-Host "  https://jrsoftware.org/isdl.php" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Expected location: $ISCC_DEFAULT_PATH" -ForegroundColor Gray
    Write-Host "Or ensure ISCC.exe is in your PATH" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# ============================================================================
# STEP 5: Build installer with Inno Setup
# ============================================================================

Write-Step "Step 5: Building installer"

# Prepare output directory
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
}

# Build ISCC command
$isccArgs = @(
    "/DMyAppVersion=$installerVersion"
    "`"$INSTALLER_SCRIPT`""
)

Write-Info "Invoking Inno Setup Compiler..."
Write-Host "  Command: $isccPath" -ForegroundColor Gray
Write-Host "  Version: /DMyAppVersion=$installerVersion" -ForegroundColor Gray
Write-Host ""

try {
    # Execute ISCC
    $process = Start-Process -FilePath $isccPath -ArgumentList $isccArgs -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-ErrorMsg "Inno Setup compilation failed with exit code $($process.ExitCode)"
        exit 1
    }
}
catch {
    Write-ErrorMsg "Failed to run Inno Setup Compiler: $_"
    exit 1
}

Write-Success "Installer compiled successfully"

# ============================================================================
# STEP 6: Verify output and display results
# ============================================================================

Write-Step "Build Complete"

$installerFileName = "LocalisSetup-$installerVersion.exe"
$installerPath = Join-Path $OUTPUT_DIR $installerFileName

if (Test-Path $installerPath) {
    $installerSize = (Get-Item $installerPath).Length / 1MB

    Write-Host ""
    Write-Host "Installer created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output file:" -ForegroundColor White
    Write-Host "  $installerPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Size: $([math]::Round($installerSize, 2)) MB" -ForegroundColor Gray
    Write-Host "Version: $installerVersion" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Test the installer on a clean Windows machine" -ForegroundColor Gray
    Write-Host "  2. Verify installation to %LOCALAPPDATA%\Localis" -ForegroundColor Gray
    Write-Host "  3. Test launch, updates, and uninstall" -ForegroundColor Gray
    Write-Host ""
}
else {
    Write-ErrorMsg "Build appeared to succeed but installer file not found"
    Write-Host "Expected: $installerPath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Check the output directory:" -ForegroundColor Yellow
    Write-Host "  $OUTPUT_DIR" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
