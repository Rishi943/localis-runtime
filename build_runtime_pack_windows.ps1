# build_runtime_pack_windows.ps1
# PowerShell script to build LocalMind Windows Runtime Pack
# Requires: PowerShell 5.1+, Internet connection
# Purpose: Creates distributable zip with launcher, bundled Python, and Git

#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$PYTHON_VERSION = "3.12.8"
$PYTHON_EMBED_URL = "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-embed-amd64.zip"
$GET_PIP_URL = "https://bootstrap.pypa.io/get-pip.py"

# Portable Git - use official MinGit distribution
$GIT_VERSION = "2.48.1"
$GIT_URL = "https://github.com/git-for-windows/git/releases/download/v$GIT_VERSION.windows.1/MinGit-$GIT_VERSION-64-bit.zip"

# Output paths
$DIST_DIR = "dist"
$RUNTIME_DIR = "$DIST_DIR\runtime"
$PYTHON_DIR = "$RUNTIME_DIR\python"
$GIT_DIR = "$RUNTIME_DIR\git"
$OUTPUT_ZIP = "$DIST_DIR\LocalisRuntimePack.zip"

# Environment variable for app repo path (must contain requirements.txt)
$APP_REPO_PATH = $env:LOCALIS_APP_REPO_PATH
if (-not $APP_REPO_PATH) {
    Write-Host "ERROR: LOCALIS_APP_REPO_PATH environment variable not set" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please set the path to your local Localis application repository:" -ForegroundColor Yellow
    Write-Host '  $env:LOCALIS_APP_REPO_PATH = "C:\path\to\localis"' -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The repository must contain a requirements.txt file." -ForegroundColor Yellow
    exit 1
}

$REQUIREMENTS_FILE = Join-Path $APP_REPO_PATH "requirements.txt"
if (-not (Test-Path $REQUIREMENTS_FILE)) {
    Write-Host "ERROR: requirements.txt not found at: $REQUIREMENTS_FILE" -ForegroundColor Red
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "===================================================================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "===================================================================================================" -ForegroundColor Cyan
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    Write-Host "Downloading: $Url" -ForegroundColor Yellow
    Write-Host "         to: $OutputPath" -ForegroundColor Yellow

    # Use .NET WebClient for progress (Invoke-WebRequest can be slow)
    $webClient = New-Object System.Net.WebClient
    try {
        $webClient.DownloadFile($Url, $OutputPath)
        Write-Host "Download complete!" -ForegroundColor Green
    }
    finally {
        $webClient.Dispose()
    }
}

function Expand-ZipFile {
    param(
        [string]$ZipPath,
        [string]$DestinationPath
    )
    Write-Host "Extracting: $ZipPath" -ForegroundColor Yellow
    Write-Host "        to: $DestinationPath" -ForegroundColor Yellow

    Expand-Archive -Path $ZipPath -DestinationPath $DestinationPath -Force
    Write-Host "Extraction complete!" -ForegroundColor Green
}

# ============================================================================
# MAIN BUILD PROCESS
# ============================================================================

Write-Host ""
Write-Host "========================================================================================" -ForegroundColor Magenta
Write-Host "                                                                                        " -ForegroundColor Magenta
Write-Host "                    LocalMind Windows Runtime Pack Builder                             " -ForegroundColor Magenta
Write-Host "                                                                                        " -ForegroundColor Magenta
Write-Host "========================================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "Configuration:" -ForegroundColor White
Write-Host "  Python Version: $PYTHON_VERSION" -ForegroundColor Gray
Write-Host "  Git Version:    $GIT_VERSION" -ForegroundColor Gray
Write-Host "  App Repo Path:  $APP_REPO_PATH" -ForegroundColor Gray
Write-Host "  Output Zip:     $OUTPUT_ZIP" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# STEP 1: Clean and prepare directories
# ============================================================================

Write-Step "Step 1: Cleaning previous build"

if (Test-Path $DIST_DIR) {
    Write-Host "Removing old dist directory..." -ForegroundColor Yellow
    Remove-Item -Path $DIST_DIR -Recurse -Force
}

Write-Host "Creating directory structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $PYTHON_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null
Write-Host "Directories created!" -ForegroundColor Green

# ============================================================================
# STEP 2: Download and extract Python embeddable
# ============================================================================

Write-Step "Step 2: Downloading Python embeddable"

$pythonZip = "$DIST_DIR\python-embed.zip"
Download-File -Url $PYTHON_EMBED_URL -OutputPath $pythonZip

Write-Host ""
Write-Host "Extracting Python runtime..." -ForegroundColor Yellow
Expand-ZipFile -ZipPath $pythonZip -DestinationPath $PYTHON_DIR

# Clean up zip
Remove-Item $pythonZip

# ============================================================================
# STEP 3: Patch python312._pth to enable site-packages
# ============================================================================

Write-Step "Step 3: Patching python312._pth"

$pthFile = Join-Path $PYTHON_DIR "python312._pth"
if (Test-Path $pthFile) {
    Write-Host "Found python312._pth, patching..." -ForegroundColor Yellow

    # Read current content
    $pthContent = Get-Content $pthFile

    # Create new content with site-packages enabled
    $newContent = @(
        "python312.zip",
        ".",
        "",
        "# Enable site-packages for pip and installed packages",
        "Lib\site-packages",
        "",
        "# Uncomment to run site.main() automatically",
        "import site"
    )

    # Write patched content
    $newContent | Out-File -FilePath $pthFile -Encoding ascii -Force
    Write-Host "python312._pth patched successfully!" -ForegroundColor Green
    Write-Host "  - Added: Lib\site-packages" -ForegroundColor Gray
    Write-Host "  - Added: import site" -ForegroundColor Gray
}
else {
    Write-Host "WARNING: python312._pth not found, may need manual configuration" -ForegroundColor Red
}

# ============================================================================
# STEP 4: Download and install pip
# ============================================================================

Write-Step "Step 4: Installing pip into bundled Python"

$getPipScript = "$DIST_DIR\get-pip.py"
Download-File -Url $GET_PIP_URL -OutputPath $getPipScript

Write-Host ""
Write-Host "Installing pip..." -ForegroundColor Yellow
$pythonExe = Join-Path $PYTHON_DIR "python.exe"
& $pythonExe $getPipScript --no-warn-script-location

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install pip" -ForegroundColor Red
    exit 1
}

Write-Host "Pip installed successfully!" -ForegroundColor Green

# Clean up
Remove-Item $getPipScript

# ============================================================================
# STEP 5: Install dependencies from requirements.txt
# ============================================================================

Write-Step "Step 5: Installing Python dependencies"

Write-Host "Reading requirements from: $REQUIREMENTS_FILE" -ForegroundColor Yellow
Write-Host ""

# Install each package using bundled Python
Write-Host "Installing dependencies (this may take several minutes)..." -ForegroundColor Yellow
& $pythonExe -m pip install -r $REQUIREMENTS_FILE --no-warn-script-location --disable-pip-version-check

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All dependencies installed successfully!" -ForegroundColor Green

# TODO: Verify critical packages are installed
Write-Host ""
Write-Host "Verifying critical packages..." -ForegroundColor Yellow
$criticalPackages = @("uvicorn", "fastapi", "llama-cpp-python")
foreach ($package in $criticalPackages) {
    & $pythonExe -m pip show $package | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $package" -ForegroundColor Green
    }
    else {
        Write-Host "  [X] $package (NOT FOUND)" -ForegroundColor Red
    }
}

# ============================================================================
# STEP 6: Download and extract portable Git
# ============================================================================

Write-Step "Step 6: Downloading portable Git (MinGit)"

$gitZip = "$DIST_DIR\mingit.zip"
Download-File -Url $GIT_URL -OutputPath $gitZip

Write-Host ""
Write-Host "Extracting Git runtime..." -ForegroundColor Yellow
Expand-ZipFile -ZipPath $gitZip -DestinationPath $GIT_DIR

# Verify git.exe exists
$gitExe = Join-Path $GIT_DIR "bin\git.exe"
if (Test-Path $gitExe) {
    Write-Host "Git extracted successfully!" -ForegroundColor Green

    # Test git
    & $gitExe --version
    Write-Host "Git version verified!" -ForegroundColor Green
}
else {
    Write-Host "WARNING: git.exe not found at expected location" -ForegroundColor Red
}

# Clean up zip
Remove-Item $gitZip

# ============================================================================
# STEP 7: Copy launcher and config template
# ============================================================================

Write-Step "Step 7: Copying launcher and configuration"

# Copy launcher script
$launcherSource = "launcher_windows.py"
$launcherDest = Join-Path $DIST_DIR "launcher_windows.py"
if (Test-Path $launcherSource) {
    Copy-Item -Path $launcherSource -Destination $launcherDest -Force
    Write-Host "[OK] Copied: launcher_windows.py" -ForegroundColor Green
}
else {
    Write-Host "ERROR: launcher_windows.py not found in current directory" -ForegroundColor Red
    exit 1
}

# Copy config template
$configSource = "localis_runtime_config.json.example"
$configDest = Join-Path $DIST_DIR "localis_runtime_config.json"
if (Test-Path $configSource) {
    Copy-Item -Path $configSource -Destination $configDest -Force
    Write-Host "[OK] Copied: localis_runtime_config.json (from example)" -ForegroundColor Green
    Write-Host "  NOTE: Users must edit this file with their repository URL" -ForegroundColor Yellow
}
else {
    Write-Host "WARNING: localis_runtime_config.json.example not found" -ForegroundColor Yellow
}

# TODO: Optionally copy README or user guide
# Copy-Item -Path "BUILD_WINDOWS.md" -Destination "$DIST_DIR\README.md" -Force

# ============================================================================
# STEP 8: Create distributable zip
# ============================================================================

Write-Step "Step 8: Creating distributable zip"

# Remove old zip if exists
if (Test-Path $OUTPUT_ZIP) {
    Remove-Item $OUTPUT_ZIP -Force
}

# Create zip
Write-Host "Compressing runtime pack..." -ForegroundColor Yellow
Write-Host "This may take several minutes..." -ForegroundColor Yellow
Write-Host ""

# Get all items in dist directory except the zip itself
$itemsToZip = Get-ChildItem -Path $DIST_DIR -Exclude "*.zip"

# Create zip (using .NET for better compression)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal

# Create temp directory for zip structure
$tempZipDir = "$DIST_DIR\LocalisRuntimePack"
if (Test-Path $tempZipDir) {
    Remove-Item $tempZipDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempZipDir -Force | Out-Null

# Copy items to temp directory
foreach ($item in $itemsToZip) {
    Copy-Item -Path $item.FullName -Destination $tempZipDir -Recurse -Force
}

# Create zip from temp directory
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempZipDir, $OUTPUT_ZIP, $compressionLevel, $false)

# Clean up temp directory
Remove-Item $tempZipDir -Recurse -Force

if (Test-Path $OUTPUT_ZIP) {
    $zipSize = (Get-Item $OUTPUT_ZIP).Length / 1MB
    Write-Host "[OK] Runtime pack created: $OUTPUT_ZIP" -ForegroundColor Green
    Write-Host "  Size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Gray
}
else {
    Write-Host "ERROR: Failed to create zip file" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 9: Generate checksum (optional but recommended)
# ============================================================================

Write-Step "Step 9: Generating checksum"

$hash = Get-FileHash -Path $OUTPUT_ZIP -Algorithm SHA256
$checksumFile = "$OUTPUT_ZIP.sha256"
"$($hash.Hash)  LocalisRuntimePack.zip" | Out-File -FilePath $checksumFile -Encoding ascii

Write-Host "[OK] Checksum saved: $checksumFile" -ForegroundColor Green
Write-Host "  SHA256: $($hash.Hash)" -ForegroundColor Gray

# ============================================================================
# BUILD COMPLETE
# ============================================================================

Write-Host ""
Write-Host "========================================================================================" -ForegroundColor Green
Write-Host "                                                                                        " -ForegroundColor Green
Write-Host "                              BUILD COMPLETED SUCCESSFULLY!                             " -ForegroundColor Green
Write-Host "                                                                                        " -ForegroundColor Green
Write-Host "========================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output files:" -ForegroundColor White
Write-Host "  Runtime Pack: $OUTPUT_ZIP" -ForegroundColor Cyan
Write-Host "  Checksum:     $checksumFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Test the runtime pack by extracting and running launcher_windows.py" -ForegroundColor Gray
Write-Host "  2. Verify bundled Python and Git are detected" -ForegroundColor Gray
Write-Host "  3. Distribute the zip file to end users" -ForegroundColor Gray
Write-Host ""
Write-Host "Distribution checklist:" -ForegroundColor Yellow
Write-Host "  [ ] Test on clean Windows VM" -ForegroundColor Gray
Write-Host "  [ ] Verify no system Python required" -ForegroundColor Gray
Write-Host "  [ ] Include BUILD_WINDOWS.md as user guide" -ForegroundColor Gray
Write-Host "  [ ] Update config template with correct repo URL" -ForegroundColor Gray
Write-Host ""

# TODO: Optional - run quick validation test
# Write-Host "Run validation test? (Y/N): " -ForegroundColor Yellow -NoNewline
# $response = Read-Host
# if ($response -eq 'Y' -or $response -eq 'y') {
#     Write-Host "Running validation..." -ForegroundColor Yellow
#     # Extract to temp location and run basic checks
# }
