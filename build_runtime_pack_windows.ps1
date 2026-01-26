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

# Derive Python version tag for file names (e.g., "3.12" -> "312")
$pyMajorMinor = $PYTHON_VERSION.Substring(0, $PYTHON_VERSION.LastIndexOf('.'))
$pyTag = $pyMajorMinor.Replace('.', '')

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

Write-Step "Step 3: Patching python$pyTag._pth"

$pthFile = Join-Path $PYTHON_DIR "python$pyTag._pth"
if (Test-Path $pthFile) {
    Write-Host "Found python$pyTag._pth, patching..." -ForegroundColor Yellow

    # Read current content
    $pthContent = Get-Content $pthFile

    # Create new content with site-packages enabled
    $newContent = @(
        "python$pyTag.zip",
        ".",
        "",
        "# Enable site-packages for pip and installed packages",
        "Lib\site-packages",
        "",
        "# Uncomment to run site.main() automatically",
        "import site"
    )

    # Write patched content
    $newContent | Out-File -FilePath $pthFile -Encoding utf8 -Force
    Write-Host "python$pyTag._pth patched successfully!" -ForegroundColor Green
    Write-Host "  - Added: Lib\site-packages" -ForegroundColor Gray
    Write-Host "  - Added: import site" -ForegroundColor Gray
}
else {
    Write-Host "WARNING: python$pyTag._pth not found, may need manual configuration" -ForegroundColor Red
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

# Filter out llama-cpp-python to avoid source builds requiring VS build tools
Write-Host "Filtering requirements (excluding llama-cpp-python)..." -ForegroundColor Yellow
$filteredRequirements = @()
$requirementLines = Get-Content $REQUIREMENTS_FILE
foreach ($line in $requirementLines) {
    $trimmedLine = $line.Trim()
    # Skip blank lines, comments, and llama-cpp-python
    if ($trimmedLine -eq "" -or $trimmedLine.StartsWith("#")) {
        continue
    }
    if ($trimmedLine -match "^llama-cpp-python") {
        Write-Host "  Skipping: $trimmedLine (will install from wheel)" -ForegroundColor Gray
        continue
    }
    $filteredRequirements += $line
}

# Write filtered requirements to temp file
$filteredReqFile = "$DIST_DIR\requirements.filtered.txt"
$filteredRequirements | Out-File -FilePath $filteredReqFile -Encoding utf8
Write-Host "Filtered requirements written to: $filteredReqFile" -ForegroundColor Gray
Write-Host ""

# Preflight check: verify all dependencies have binary wheels available
Write-Host "Preflight: Checking binary wheel availability..." -ForegroundColor Yellow
$wheelhouseDir = Join-Path $DIST_DIR "wheelhouse"
New-Item -ItemType Directory -Path $wheelhouseDir -Force | Out-Null
& $pythonExe -m pip download -r $filteredReqFile -d $wheelhouseDir --only-binary=:all: --prefer-binary --no-deps --disable-pip-version-check --no-warn-script-location

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Preflight check failed - one or more dependencies lack binary wheels" -ForegroundColor Red
    Write-Host ""
    Write-Host "A dependency has no compatible wheel for Python $PYTHON_VERSION on Windows." -ForegroundColor Yellow
    Write-Host "Building from source requires Visual Studio build tools (not supported on clean machines)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Remediation options:" -ForegroundColor Cyan
    Write-Host "  1. Pin the problematic dependency to a version that has wheels" -ForegroundColor Gray
    Write-Host "  2. Install Visual Studio build tools on the build machine" -ForegroundColor Gray
    Write-Host "  3. Use a different Python version that has better wheel coverage" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Review the error output above to identify which package failed." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
Write-Host "Preflight passed - all dependencies have binary wheels available" -ForegroundColor Green
Write-Host ""

# Install filtered requirements using bundled Python
Write-Host "Installing dependencies (this may take several minutes)..." -ForegroundColor Yellow
& $pythonExe -m pip install -r $filteredReqFile --no-warn-script-location --disable-pip-version-check

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Base dependencies installed successfully!" -ForegroundColor Green

# Install llama-cpp-python from prebuilt wheel
Write-Host ""
Write-Host "Installing llama-cpp-python from prebuilt wheel..." -ForegroundColor Yellow

$llamaWheel = $env:LOCALIS_LLAMA_WHEEL
if (-not $llamaWheel) {
    Write-Host "ERROR: LOCALIS_LLAMA_WHEEL environment variable not set" -ForegroundColor Red
    Write-Host ""
    Write-Host "llama-cpp-python cannot be built from source on clean Windows" -ForegroundColor Yellow
    Write-Host "without Visual Studio build tools and cmake." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please set LOCALIS_LLAMA_WHEEL to one of the following:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Official index (CPU-only):" -ForegroundColor Cyan
    Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "INDEX_CPU"' -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Official index (CUDA):" -ForegroundColor Cyan
    Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "INDEX_CUDA_cu121"  # or cu122, cu123, cu124, cu125' -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  3. URL to .whl file:" -ForegroundColor Cyan
    Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "https://github.com/.../llama_cpp_python-0.x.x-cp312-win_amd64.whl"' -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  4. Local path to .whl file:" -ForegroundColor Cyan
    Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "C:\wheels\llama_cpp_python-0.x.x-cp312-win_amd64.whl"' -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Check if special index value, URL, or local path
if ($llamaWheel -eq "INDEX_CPU") {
    # Install from official CPU index
    Write-Host "Wheel source: INDEX_CPU (official index)" -ForegroundColor Gray
    Write-Host "Installing llama-cpp-python from CPU index (wheel-only, no source builds)..." -ForegroundColor Yellow
    & $pythonExe -m pip install llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu --only-binary llama-cpp-python --prefer-binary --no-cache-dir --no-warn-script-location --disable-pip-version-check

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install llama-cpp-python from CPU index" -ForegroundColor Red
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  - pip may have attempted to build from source (sdist)" -ForegroundColor Yellow
        Write-Host "  - No compatible wheel available for your Python version/platform" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Solutions:" -ForegroundColor Cyan
        Write-Host "  1. Set LOCALIS_LLAMA_WHEEL to an explicit .whl URL:" -ForegroundColor Cyan
        Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "https://github.com/.../llama_cpp_python-x.x.x-cp312-win_amd64.whl"' -ForegroundColor Gray
        Write-Host ""
        Write-Host "  2. Set LOCALIS_LLAMA_WHEEL to a local .whl path:" -ForegroundColor Cyan
        Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "C:\wheels\llama_cpp_python-x.x.x-cp312-win_amd64.whl"' -ForegroundColor Gray
        Write-Host ""
        Write-Host "Debug command:" -ForegroundColor Cyan
        Write-Host "  $pythonExe -m pip debug --verbose" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}
elseif ($llamaWheel -match "^INDEX_CUDA_(cu\d+)$") {
    # Install from official CUDA index
    $cudaSuffix = $matches[1]
    Write-Host "Wheel source: INDEX_CUDA_$cudaSuffix (official index)" -ForegroundColor Gray
    Write-Host "Installing llama-cpp-python from CUDA $cudaSuffix index (wheel-only, no source builds)..." -ForegroundColor Yellow
    $indexUrl = "https://abetlen.github.io/llama-cpp-python/whl/$cudaSuffix"
    & $pythonExe -m pip install llama-cpp-python --extra-index-url $indexUrl --only-binary llama-cpp-python --prefer-binary --no-cache-dir --no-warn-script-location --disable-pip-version-check

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install llama-cpp-python from CUDA $cudaSuffix index" -ForegroundColor Red
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  - pip may have attempted to build from source (sdist)" -ForegroundColor Yellow
        Write-Host "  - No compatible wheel available for your Python version/platform" -ForegroundColor Yellow
        Write-Host "  - CUDA version mismatch (you specified $cudaSuffix)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Solutions:" -ForegroundColor Cyan
        Write-Host "  1. Try a different CUDA version (cu121, cu122, cu123, cu124, cu125):" -ForegroundColor Cyan
        Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "INDEX_CUDA_cu122"' -ForegroundColor Gray
        Write-Host ""
        Write-Host "  2. Set LOCALIS_LLAMA_WHEEL to an explicit .whl URL:" -ForegroundColor Cyan
        Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "https://github.com/.../llama_cpp_python-x.x.x-cp312-win_amd64.whl"' -ForegroundColor Gray
        Write-Host ""
        Write-Host "  3. Set LOCALIS_LLAMA_WHEEL to a local .whl path:" -ForegroundColor Cyan
        Write-Host '     $env:LOCALIS_LLAMA_WHEEL = "C:\wheels\llama_cpp_python-x.x.x-cp312-win_amd64.whl"' -ForegroundColor Gray
        Write-Host ""
        Write-Host "Debug command:" -ForegroundColor Cyan
        Write-Host "  $pythonExe -m pip debug --verbose" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}
elseif ($llamaWheel -match "^https?://") {
    # Download from URL
    Write-Host "Wheel source: $llamaWheel" -ForegroundColor Gray
    $wheelFile = "$DIST_DIR\llama_cpp_python.whl"
    Write-Host "Downloading wheel from URL..." -ForegroundColor Yellow
    Download-File -Url $llamaWheel -OutputPath $wheelFile
    $wheelToInstall = $wheelFile

    # Install the wheel
    Write-Host "Installing llama-cpp-python wheel..." -ForegroundColor Yellow
    & $pythonExe -m pip install $wheelToInstall --no-warn-script-location --disable-pip-version-check

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install llama-cpp-python wheel" -ForegroundColor Red
        exit 1
    }
}
else {
    # Local path
    Write-Host "Wheel source: $llamaWheel" -ForegroundColor Gray
    if (-not (Test-Path $llamaWheel)) {
        Write-Host "ERROR: Wheel file not found at: $llamaWheel" -ForegroundColor Red
        exit 1
    }
    Write-Host "Using local wheel file" -ForegroundColor Gray
    $wheelToInstall = $llamaWheel

    # Install the wheel
    Write-Host "Installing llama-cpp-python wheel..." -ForegroundColor Yellow
    & $pythonExe -m pip install $wheelToInstall --no-warn-script-location --disable-pip-version-check

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install llama-cpp-python wheel" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "llama-cpp-python installed successfully!" -ForegroundColor Green

# Verify critical packages are installed
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
