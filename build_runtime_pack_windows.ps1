# build_runtime_pack_windows.ps1
# PowerShell script to build Localis Windows Runtime Pack
# Phase 1 Implementation - Canonical Build Script
# Requires: PowerShell 5.1+, Internet connection

# ============================================================================
# ACCEPTANCE TESTS (Phase 1)
# ============================================================================
# These tests verify that the runtime pack is built correctly:
#
# TEST 1: Clean build produces dist\LocalisRuntimePack.zip
#   Verify: dist\LocalisRuntimePack.zip exists after successful build
#
# TEST 2: Extracted zip contains required structure
#   Extract the zip and verify presence of:
#   - runtime\python\python.exe
#   - runtime\git\bin\git.exe
#   - launcher_windows.py (at root of extracted directory)
#   - localis_runtime_config.json (at root)
#
# TEST 3: llama-cpp-python imports successfully
#   From extracted runtime pack, run:
#     dist\runtime\python\python.exe -c "import llama_cpp; print('ok')"
#   Expected output: "ok"
#   Expected exit code: 0
#
# ============================================================================

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$SkipVerify
)


$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

# FIXED: Use Python 3.11 for better wheel availability
$PYTHON_VERSION = "3.11.9"
$PYTHON_EMBED_URL = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
$GET_PIP_URL = "https://bootstrap.pypa.io/get-pip.py"

# llama-cpp-python: install prebuilt wheels from the official wheel index
$LLAMA_CPP_VERSION = "0.3.2"
$LLAMA_CPP_CPU_INDEX = "https://abetlen.github.io/llama-cpp-python/whl/cpu"

# Visual C++ 2015-2022 Redistributable (required for llama.dll)
$VC_REDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

# Derive Python version tag for file names (e.g., "3.11" -> "311")
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
    # FALLBACK: If not set, assume we're in the app repo itself
    if (Test-Path "requirements.txt") {
        $APP_REPO_PATH = Get-Location
        Write-Host "Using current directory as app repo: $APP_REPO_PATH" -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: LOCALIS_APP_REPO_PATH environment variable not set" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please set the path to your local Localis application repository:" -ForegroundColor Yellow
        Write-Host '  $env:LOCALIS_APP_REPO_PATH = "C:\path\to\localis"' -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Or run this script from within the app repository directory." -ForegroundColor Yellow
        exit 1
    }
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
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutputPath
    )

    Write-Host "Downloading (Invoke-WebRequest): $Url" -ForegroundColor Yellow

    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    }

    $ext = [System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant()

    try {
        # Improve compatibility with PS 5.1 + some hosts
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec 600 `
            -Headers @{ "User-Agent" = "Mozilla/5.0" } -ErrorAction Stop

        if (-not (Test-Path $OutputPath)) { throw "File not created: $OutputPath" }

        $size = (Get-Item $OutputPath).Length
        if ($size -lt 1024) { throw "Downloaded file too small ($size bytes)" }

        if ($ext -in @(".zip", ".whl")) {
            Assert-ZipMagic -Path $OutputPath -Label "Downloaded file"
        }

        return
    } catch {
        Write-Host "Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "Downloading (curl.exe): $Url" -ForegroundColor Yellow

    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
    }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw "Download failed: curl.exe not found and Invoke-WebRequest failed. URL=$Url"
    }

    & $curl.Source --fail --location --retry 5 --retry-all-errors --connect-timeout 30 `
        -A "Mozilla/5.0" $Url -o $OutputPath

    if ($LASTEXITCODE -ne 0) {
        throw "curl.exe failed (exit=$LASTEXITCODE). URL=$Url"
    }

    if (-not (Test-Path $OutputPath)) { throw "File not created by curl: $OutputPath" }

    $size = (Get-Item $OutputPath).Length
    if ($size -lt 1024) { throw "curl produced an invalid file (too small): $OutputPath ($size bytes)" }

    if ($ext -in @(".zip", ".whl")) {
        Assert-ZipMagic -Path $OutputPath -Label "Downloaded file"
    }
}




# Ch (paste artifact - removed to fix parse error)


function Expand-ZipFile {
    param(
        [Parameter(Mandatory=$true)][string]$ZipPath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )

    Write-Host "Extracting: $ZipPath" -ForegroundColor Yellow
    Write-Host "        to: $DestinationPath" -ForegroundColor Yellow

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path $DestinationPath) {
        Remove-Item $DestinationPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null

    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinationPath)
    Write-Host "Extraction complete!" -ForegroundColor Green
}

function Assert-ZipMagic {
    param([string]$Path, [string]$Label)

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $b1 = $fs.ReadByte()
        $b2 = $fs.ReadByte()
    } finally {
        $fs.Dispose()
    }

    # ZIP files start with 'PK' (0x50 0x4B)
    if ($b1 -ne 0x50 -or $b2 -ne 0x4B) {
        throw "$Label is not a valid zip-based file (missing PK header): $Path"
    }
}

function Verify-FileHash {
    param(
        [string]$FilePath,
        [string]$ExpectedHash = $null
    )

    if (-not (Test-Path $FilePath)) {
        Write-Host "ERROR: File not found: $FilePath" -ForegroundColor Red
        return $false
    }

    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    Write-Host "  SHA256: $actualHash" -ForegroundColor Gray

    if ($ExpectedHash) {
        if ($actualHash -eq $ExpectedHash) {
            Write-Host "  [OK] Checksum verified" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [X] Checksum mismatch!" -ForegroundColor Red
            Write-Host "    Expected: $ExpectedHash" -ForegroundColor Red
            Write-Host "    Got:      $actualHash" -ForegroundColor Red
            return $false
        }
    }

    return $true
}

function Test-VCRedistX64Installed {
    <#
    .SYNOPSIS
    Checks if Visual C++ 2015-2022 x64 Redistributable is installed.

    .DESCRIPTION
    Queries the registry for VC++ runtime version 14.0 (covers 2015-2022).
    Returns $true if installed, $false otherwise.
    #>

    $regPath = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"

    if (Test-Path $regPath) {
        try {
            $installed = Get-ItemProperty -Path $regPath -Name "Installed" -ErrorAction SilentlyContinue
            if ($installed.Installed -eq 1) {
                return $true
            }
        } catch {
            return $false
        }
    }

    return $false
}

function Ensure-VCRedistX64 {
    <#
    .SYNOPSIS
    Ensures Visual C++ 2015-2022 x64 Redistributable is installed.

    .DESCRIPTION
    Checks registry for VC++ runtime. If not found, downloads and installs silently.
    Validates installation after install. Throws on failure.
    #>

    Write-Host ""
    Write-Host "Checking Visual C++ 2015-2022 Redistributable (x64)..." -ForegroundColor Yellow

    if (Test-VCRedistX64Installed) {
        Write-Host "[OK] VC++ Redistributable already installed" -ForegroundColor Green
        return
    }

    Write-Host "VC++ Redistributable not detected, installing..." -ForegroundColor Yellow

    # Download redistributable
    $vcRedistPath = Join-Path $DIST_DIR "vc_redist.x64.exe"

    if (-not (Test-Path $vcRedistPath)) {
        Download-File -Url $VC_REDIST_URL -OutputPath $vcRedistPath
    } else {
        Write-Host "Using cached vc_redist.x64.exe" -ForegroundColor Gray
    }

    # Install silently (no reboot, no UI)
    Write-Host "Installing VC++ Redistributable (silent mode)..." -ForegroundColor Yellow
    Write-Host "  Command: vc_redist.x64.exe /install /quiet /norestart" -ForegroundColor Gray

    $installProc = Start-Process -FilePath $vcRedistPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru -NoNewWindow
    $exitCode = $installProc.ExitCode

    Write-Host "  Exit code: $exitCode" -ForegroundColor Gray

    # Exit codes: 0 = success, 3010 = success but reboot required
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        throw "VC++ Redistributable installation failed with exit code: $exitCode"
    }

    if ($exitCode -eq 3010) {
        Write-Host "  [!] Installation successful but reboot required" -ForegroundColor Yellow
    }

    # Re-check registry
    if (Test-VCRedistX64Installed) {
        Write-Host "[OK] VC++ Redistributable installed successfully" -ForegroundColor Green
    } else {
        throw "VC++ Redistributable installation completed but registry check failed. A reboot may be required."
    }

    # Keep vc_redist.x64.exe in dist/ for installer bundling (do NOT delete)
    Write-Host "  Kept vc_redist.x64.exe in dist/ for installer bundling" -ForegroundColor Gray
}

# ============================================================================
# MAIN BUILD PROCESS
# ============================================================================

Write-Host ""
Write-Host "========================================================================================" -ForegroundColor Magenta
Write-Host "                                                                                        " -ForegroundColor Magenta
Write-Host "                    Localis Windows Runtime Pack Builder                               " -ForegroundColor Magenta
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
Write-Host "Verifying download..." -ForegroundColor Yellow
Verify-FileHash -FilePath $pythonZip

Write-Host ""
Write-Host "Extracting Python runtime..." -ForegroundColor Yellow
Expand-ZipFile -ZipPath $pythonZip -DestinationPath $PYTHON_DIR

# Clean up zip
Remove-Item $pythonZip

# ============================================================================
# STEP 3: Patch python3XX._pth to enable site-packages
# ============================================================================

Write-Step "Step 3: Patching python$pyTag._pth"

$pthFile = Join-Path $PYTHON_DIR "python$pyTag._pth"
if (Test-Path $pthFile) {
    Write-Host "Found python$pyTag._pth, patching..." -ForegroundColor Yellow

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

    # FIXED: Write patched content UTF-8 WITHOUT BOM
    [System.IO.File]::WriteAllLines($pthFile, $newContent, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "python$pyTag._pth patched successfully!" -ForegroundColor Green
    Write-Host "  - Added: Lib\site-packages" -ForegroundColor Gray
    Write-Host "  - Added: import site" -ForegroundColor Gray

    # VERIFY: Check no BOM was written
    $bytes = [System.IO.File]::ReadAllBytes($pthFile)
    if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host "  [X] WARNING: BOM detected in _pth file!" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "  [OK] No BOM in _pth file" -ForegroundColor Green
    }
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

# FIXED: Removed --no-warn-script-location flag (not supported in pip 25.3+)
& $pythonExe $getPipScript

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install pip" -ForegroundColor Red
    exit 1
}

Write-Host "Pip installed successfully!" -ForegroundColor Green

# Clean up
Remove-Item $getPipScript

# ============================================================================
# STEP 5: Install Python dependencies
# ============================================================================

Write-Step "Step 5: Installing Python dependencies"

Write-Host "Reading requirements from: $REQUIREMENTS_FILE" -ForegroundColor Gray
Write-Host ""

# Create filtered requirements (exclude llama-cpp-python - we'll install from wheel)
$requirements = Get-Content $REQUIREMENTS_FILE
$filtered = $requirements | Where-Object { $_ -notmatch "^llama-cpp-python" -and $_.Trim() -ne "" -and -not $_.StartsWith("#") }
$filteredFile = "$DIST_DIR\requirements.filtered.txt"
$filtered | Out-File -FilePath $filteredFile -Encoding utf8

Write-Host "Filtering requirements (excluding llama-cpp-python)..." -ForegroundColor Yellow
Write-Host "  Skipping: llama-cpp-python (will install from pre-compiled wheel)" -ForegroundColor Gray
Write-Host "Filtered requirements written to: $filteredFile" -ForegroundColor Gray
Write-Host ""

# Install non-binary dependencies
Write-Host "Installing dependencies (this may take several minutes)..." -ForegroundColor Yellow

# FIXED: Removed --no-warn-script-location flag
& $pythonExe -m pip install -r $filteredFile --disable-pip-version-check

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies" -ForegroundColor Red
    exit 1
}

Write-Host "Dependencies installed successfully!" -ForegroundColor Green

# ============================================================================

# STEP 6: Install llama-cpp-python from pinned Windows wheel
# ============================================================================
Write-Step "Step 6: Installing llama-cpp-python (pinned wheel for Windows cp$pyTag)"

# Build filename using current embedded Python tag (311)
$wheelFileName = "llama_cpp_python-$LLAMA_CPP_VERSION-cp$pyTag-cp$pyTag-win_amd64.whl"
$LLAMA_WHEEL_URL = "https://github.com/abetlen/llama-cpp-python/releases/download/v$LLAMA_CPP_VERSION/$wheelFileName"

# IMPORTANT: save using the real wheel filename (pip requires it)
$wheelPath = Join-Path $DIST_DIR $wheelFileName

Download-File -Url $LLAMA_WHEEL_URL -OutputPath $wheelPath

# Install the wheel (allow deps if any; they are pure python)
& $pythonExe -m pip install --force-reinstall $wheelPath --disable-pip-version-check
if ($LASTEXITCODE -ne 0) { throw "llama-cpp-python wheel install failed" }

# Hard check: confirm dll exists
$llamaDll = Join-Path $PYTHON_DIR "Lib\site-packages\llama_cpp\lib\llama.dll"
if (-not (Test-Path $llamaDll)) {
    throw "llama.dll missing after wheel install: $llamaDll"
}

# Ensure Visual C++ Redistributable is installed (required for llama.dll)
Ensure-VCRedistX64

# Quick import test
Write-Host ""
Write-Host "Testing llama_cpp import..." -ForegroundColor Yellow
& $pythonExe -c "import llama_cpp; print('ok')"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: llama_cpp import failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Diagnostic information:" -ForegroundColor Yellow
    Write-Host "  - llama.dll exists at: $llamaDll" -ForegroundColor Gray
    Write-Host "  - VC++ Redistributable check passed" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  1. A system reboot may be required after VC++ installation" -ForegroundColor Gray
    Write-Host "  2. Missing additional runtime dependencies (rare)" -ForegroundColor Gray
    Write-Host "  3. GPU/CUDA driver issues (if using CUDA build)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Recommended action:" -ForegroundColor Yellow
    Write-Host "  - Reboot your system and re-run this build script" -ForegroundColor Cyan
    Write-Host ""
    throw "llama_cpp import failed - see diagnostic information above"
}
Write-Host "[OK] llama_cpp imported successfully" -ForegroundColor Green

# ============================================================================
# STEP 7: Install Portable Git (MinGit) + normalize to runtime\git\bin\git.exe
# ============================================================================
Write-Step "Step 7: Installing portable Git (MinGit)"

$gitZip = Join-Path $DIST_DIR "mingit.zip"

# Clean previous
if (Test-Path $GIT_DIR) {
    Remove-Item $GIT_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $GIT_DIR -Force | Out-Null

Write-Host "Downloading MinGit..." -ForegroundColor Yellow
Write-Host "  URL: $GIT_URL" -ForegroundColor Gray
Download-File -Url $GIT_URL -OutputPath $gitZip

Write-Host "Extracting MinGit..." -ForegroundColor Yellow
Expand-ZipFile -ZipPath $gitZip -DestinationPath $GIT_DIR

# Normalize if the zip extracted into a single top-level folder
# (some zips contain a wrapper directory)
$top = Get-ChildItem -Path $GIT_DIR -Force
if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
    $maybeRoot = $top[0].FullName
    if (Test-Path (Join-Path $maybeRoot "cmd\git.exe")) {
        Write-Host "Normalizing MinGit layout (flattening top folder)..." -ForegroundColor Yellow
        Get-ChildItem -Path $maybeRoot -Force | ForEach-Object {
            $dest = Join-Path $GIT_DIR $_.Name
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -Path $_.FullName -Destination $GIT_DIR -Force
        }
        Remove-Item $maybeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Locate git.exe in typical MinGit layouts
$gitExeCandidates = @(
    (Join-Path $GIT_DIR "cmd\git.exe"),
    (Join-Path $GIT_DIR "mingw64\bin\git.exe"),
    (Join-Path $GIT_DIR "usr\bin\git.exe"),
    (Join-Path $GIT_DIR "bin\git.exe")
)

$gitExe = $null
foreach ($p in $gitExeCandidates) {
    if (Test-Path $p) { $gitExe = $p; break }
}

if (-not $gitExe) {
    $found = Get-ChildItem -Path $GIT_DIR -Recurse -File -Filter git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $gitExe = $found.FullName }
}

if (-not $gitExe -or -not (Test-Path $gitExe)) {
    throw "Portable Git install failed: could not locate git.exe under $GIT_DIR"
}

Write-Host "Found git.exe:" -ForegroundColor Green
Write-Host "  $gitExe" -ForegroundColor Gray

# Ensure launcher-compatible canonical path: runtime\git\bin\git.exe
$canonicalBinDir = Join-Path $GIT_DIR "bin"
New-Item -ItemType Directory -Path $canonicalBinDir -Force | Out-Null
$canonicalGit = Join-Path $canonicalBinDir "git.exe"

# Prefer copying cmd\git.exe into bin\git.exe (works because both are one level under root)
$preferredSource = Join-Path $GIT_DIR "cmd\git.exe"
$sourceGit = if (Test-Path $preferredSource) { $preferredSource } else { $gitExe }

Copy-Item -Path $sourceGit -Destination $canonicalGit -Force
$gitExe = $canonicalGit

Write-Host "Canonical git.exe created:" -ForegroundColor Green
Write-Host "  $gitExe" -ForegroundColor Gray

# Sanity check
$gv = & $gitExe --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Git sanity check failed at canonical path. Output: $gv"
}
Write-Host $gv -ForegroundColor Gray

# Cleanup zip
Remove-Item $gitZip -Force -ErrorAction SilentlyContinue


# ============================================================================
# STEP 8: Copy launcher and config template FROM APP REPO
# ============================================================================

Write-Step "Step 8: Copying launcher and configuration"

# FIXED: Copy launcher from app repo (not current directory)
$launcherSource = Join-Path $APP_REPO_PATH "launcher_windows.py"
$launcherDest = Join-Path $DIST_DIR "launcher_windows.py"

if (Test-Path $launcherSource) {
    Copy-Item -Path $launcherSource -Destination $launcherDest -Force
    Write-Host "[OK] Copied launcher from: $launcherSource" -ForegroundColor Green
} else {
    Write-Host "ERROR: launcher_windows.py not found at: $launcherSource" -ForegroundColor Red
    Write-Host "  Expected location: <APP_REPO_PATH>\launcher_windows.py" -ForegroundColor Yellow
    Write-Host "  Current APP_REPO_PATH: $APP_REPO_PATH" -ForegroundColor Yellow
    exit 1
}

# Copy config template (also from app repo)
$configSource = Join-Path $APP_REPO_PATH "localis_runtime_config.json.example"
$configDest = Join-Path $DIST_DIR "localis_runtime_config.json"

if (Test-Path $configSource) {
    Copy-Item -Path $configSource -Destination $configDest -Force
    Write-Host "[OK] Copied config from: $configSource" -ForegroundColor Green
} else {
    Write-Host "WARNING: localis_runtime_config.json.example not found, creating default" -ForegroundColor Yellow

    # Create default config
    @{
        app_repo_url = "https://github.com/user/localis-app.git"
        app_branch = "release"
        host = "127.0.0.1"
        port = 8000
    } | ConvertTo-Json | Out-File -FilePath $configDest -Encoding utf8

    Write-Host "[OK] Created default config" -ForegroundColor Green
}

# Optionally copy README
$readmeSource = Join-Path $APP_REPO_PATH "BUILD_WINDOWS.md"
if (Test-Path $readmeSource) {
    Copy-Item -Path $readmeSource -Destination "$DIST_DIR\README.md" -Force
    Write-Host "[OK] Copied README" -ForegroundColor Green
}


# ============================================================================
# STEP 9: Create distributable zip
# ============================================================================

Write-Step "Step 9: Creating distributable zip"

if (Test-Path $OUTPUT_ZIP) { Remove-Item $OUTPUT_ZIP -Force }

# Stage into a clean folder so ZIP entries are guaranteed relative
$STAGE_DIR = Join-Path $DIST_DIR "_stage_pack"
if (Test-Path $STAGE_DIR) { Remove-Item $STAGE_DIR -Recurse -Force }
New-Item -ItemType Directory -Path $STAGE_DIR | Out-Null

# Copy runtime/ as runtime/
Copy-Item -Path $RUNTIME_DIR -Destination (Join-Path $STAGE_DIR "runtime") -Recurse -Force

# Copy root files
Copy-Item -Path (Join-Path $DIST_DIR "launcher_windows.py") -Destination (Join-Path $STAGE_DIR "launcher_windows.py") -Force
Copy-Item -Path (Join-Path $DIST_DIR "localis_runtime_config.json") -Destination (Join-Path $STAGE_DIR "localis_runtime_config.json") -Force
if (Test-Path (Join-Path $DIST_DIR "README.md")) {
    Copy-Item -Path (Join-Path $DIST_DIR "README.md") -Destination (Join-Path $STAGE_DIR "README.md") -Force
}

Write-Host "Creating zip from stage folder..." -ForegroundColor Yellow
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($STAGE_DIR, $OUTPUT_ZIP, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# Remove staging folder
Remove-Item $STAGE_DIR -Recurse -Force

# Sanity check: detect accidental absolute-path entries
$z = [System.IO.Compression.ZipFile]::OpenRead($OUTPUT_ZIP)
$bad = $z.Entries | Where-Object { $_.FullName -match '^[A-Za-z]:|^[A-Za-z][\\/]' }
$first10 = $z.Entries | Select-Object -First 10 -ExpandProperty FullName
$z.Dispose()

Write-Host ""
Write-Host "First 10 entries:" -ForegroundColor Gray
$first10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

if ($bad) { throw "ZIP contains invalid absolute-like entry: $($bad[0].FullName)" }

$zipSize = (Get-Item $OUTPUT_ZIP).Length / 1MB
Write-Host ""
Write-Host "[OK] Runtime pack created: $OUTPUT_ZIP" -ForegroundColor Green
Write-Host "  Size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Gray


# ============================================================================
# STEP 10: Generate checksum
# ============================================================================

Write-Step "Step 10: Generating checksum"

$hash = Get-FileHash -Path $OUTPUT_ZIP -Algorithm SHA256
$checksumFile = "$OUTPUT_ZIP.sha256"
"$($hash.Hash)  LocalisRuntimePack.zip" | Out-File -FilePath $checksumFile -Encoding ascii

Write-Host "[OK] Checksum saved: $checksumFile" -ForegroundColor Green
Write-Host "  SHA256: $($hash.Hash)" -ForegroundColor Gray

# ============================================================================
# STEP 11: Optional post-build verification
# ============================================================================

$verifyScript = "scripts\verify_runtime_pack.ps1"
if ((Test-Path $verifyScript) -and -not $SkipVerify) {
    Write-Step "Step 11: Running post-build verification"

    Write-Host "Invoking: $verifyScript" -ForegroundColor Yellow
    Write-Host ""

    & $verifyScript -ZipPath $OUTPUT_ZIP

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Post-build verification failed" -ForegroundColor Red
        Write-Host "The runtime pack was created but did not pass verification checks." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To skip verification, use: -SkipVerify" -ForegroundColor Gray
        exit 1
    }

    Write-Host ""
    Write-Host "Post-build verification passed!" -ForegroundColor Green
} elseif ($SkipVerify) {
    Write-Host ""
    Write-Host "Skipping post-build verification (-SkipVerify flag set)" -ForegroundColor Yellow
}

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
Write-Host "  3. Build installer with Inno Setup" -ForegroundColor Gray
Write-Host ""
Write-Host "Quick test command:" -ForegroundColor Yellow
Write-Host '  Expand-Archive -Path ".\dist\LocalisRuntimePack.zip" -DestinationPath ".\test" -Force' -ForegroundColor Cyan
Write-Host '  & ".\test\runtime\python\python.exe" ".\test\launcher_windows.py"' -ForegroundColor Cyan
Write-Host ""
