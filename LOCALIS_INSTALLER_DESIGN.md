# Localis Windows Installer - Complete Design Document

**Generated:** February 1, 2026  
**Purpose:** Production-ready installer for zero-dependency Windows deployment  
**Target User:** Non-technical Windows users with clean machines  
**MVP Scope:** App updates via git, runtime updates via new installer

---

## PART A: ERROR LOG ANALYSIS

### A.1 Error Classification & Triage

#### **BLOCKER ERRORS** (Must fix before any distribution)

| Error ID | Subsystem | Frequency | Root Cause | Severity |
|----------|-----------|-----------|------------|----------|
| **ERR-001** | Build/Dependencies | 1x | `llama-cpp-python` requires C++ compiler to build from source | BLOCKER |
| **ERR-002** | Python Runtime | 1x | BOM character in `python312._pth` prevents encodings module load | BLOCKER |
| **ERR-003** | Archive Structure | 2x | Zip extraction creates wrong directory structure (`python/` instead of `runtime/python/`) | BLOCKER |
| **ERR-004** | Build Script | 1x | `launcher_windows.py` not included in runtime pack archive | BLOCKER |

#### **MAJOR ERRORS** (Affects reliability)

| Error ID | Subsystem | Root Cause | Severity |
|----------|-----------|------------|----------|
| **ERR-005** | Build Script | Pip flag `--no-warn-script-location` not recognized in pip 25.3 | MAJOR |
| **ERR-006** | Build Script | PowerShell syntax errors (fixed by git pull but shows fragility) | MAJOR |
| **ERR-007** | Build Script | Relative path resolution issues when CWD differs | MAJOR |

---

### A.2 Detailed Error Analysis

#### ERR-001: llama-cpp-python Build Dependency

**Error Snippet:**
```
ERROR: Preflight check failed - one or more dependencies lack binary wheels

A dependency has no compatible wheel for Python 3.12.8 on Windows.
Building from source requires Visual Studio build tools (not supported on clean machines).
```

**Root Cause:**  
The requirements.txt includes `llama-cpp-python`, which has no pre-compiled wheels for Python 3.12.8 on Windows. When pip attempts to install it, it tries to build from source, requiring:
- Microsoft Visual C++ 14.0+ (Visual Studio Build Tools)
- CMake
- CUDA toolkit (for GPU support)

**Fix - Option A (Recommended):** Use pre-compiled wheels
```powershell
# Download from abetlen's releases with CPU-only AVX2 support
$WHEEL_URL = "https://github.com/abetlen/llama-cpp-python/releases/download/v0.3.16/llama_cpp_python-0.3.16-cp311-cp311-win_amd64.whl"
```

**Fix - Option B:** Use Python 3.11 which has better wheel coverage
```powershell
$PYTHON_VERSION = "3.11.11"  # Change from 3.12.8
```

**Prevention:**
1. Pin `llama-cpp-python` to specific version with verified wheel availability
2. Add wheel verification step in build script before attempting install
3. Host pre-downloaded wheels in release artifacts

---

#### ERR-002: Python Embeddable Encodings Module Failure

**Error Snippet:**
```
Fatal Python error: init_fs_encoding: failed to get the Python codec of the filesystem encoding
Python runtime state: core initialized
ModuleNotFoundError: No module named 'encodings'

sys.path = [
  'D:\\localis-runtime\\dist\\runtime\\python\\\ufeffpython312.zip',  # <-- BOM character!
  ...
]
```

**Root Cause:**  
The `python312._pth` file was written with a UTF-8 BOM (Byte Order Mark), causing Python to prepend `\ufeff` to the first path entry. This breaks the path resolution for `python312.zip` which contains the `encodings` module.

**Fix (Applied in build script):**
```powershell
# Write without BOM
[System.IO.File]::WriteAllLines($pthFile, $newContent, (New-Object System.Text.UTF8Encoding($false)))
```

**Additional Prevention:**
1. Always force-remove `$PYTHON_DIR` before extraction
2. Add validation after patching to verify no BOM
3. Add runtime check in launcher to detect corrupted _pth files

---

#### ERR-003: Archive Structure Mismatch

**Error Snippet:**
```powershell
# Expected structure:
$dest\runtime\python\python.exe
$dest\launcher_windows.py

# Actual structure after extraction:
$dest\python\python.exe
# (launcher missing entirely)
```

**Root Cause:**  
The ZIP was created incorrectly, not preserving the intended directory structure.

**Fix:**
```powershell
# Use explicit entry paths when adding files to zip archive
$itemsToZip = @(
    @{Source = "$DIST_DIR\runtime"; ArchivePath = "runtime" }
    @{Source = "$DIST_DIR\launcher_windows.py"; ArchivePath = "launcher_windows.py" }
    @{Source = "$DIST_DIR\localis_runtime_config.json"; ArchivePath = "localis_runtime_config.json" }
)
```

---

#### ERR-004: Missing launcher_windows.py in Archive

**Error Snippet:**
```powershell
PS D:\localis-runtime> Get-ChildItem $dest -Recurse -Filter launcher_windows.py -ErrorAction SilentlyContinue | Select-Object FullName
# (no results)
```

**Root Cause:**  
The build script copied `launcher_windows.py` from the build directory using a relative path, but the launcher actually lives in the app repository.

**Fix:**
```powershell
# Copy from app repo
$launcherSource = Join-Path $env:LOCALIS_APP_REPO_PATH "launcher_windows.py"
$launcherDest = Join-Path $DIST_DIR "launcher_windows.py"
Copy-Item $launcherSource $launcherDest
```

---

## PART B: FAILURE MODE ANALYSIS

### B.1 Installation Failures (8 Scenarios)

| ID | Scenario | Impact | Mitigation |
|----|----------|--------|------------|
| **F01** | Antivirus blocks Python.exe | Installation fails | Digital signature + documented exceptions |
| **F02** | Insufficient disk space | Installation fails | Pre-check 2GB free before extraction |
| **F03** | %LOCALAPPDATA% missing | Installation fails | Fallback to %USERPROFILE%\AppData\Local |
| **F04** | Path length >260 chars | File operations fail | Enable long paths, use shorter install path |
| **F05** | Corrupted download | Extraction fails | SHA256 verification before extraction |
| **F06** | Port 8000 in use | Server won't start | Auto-select alternative port (8000-8010 range) |
| **F07** | Another instance running | Port conflict | Mutex/lock file detection |
| **F08** | Unicode in paths | Various failures | Path validation, ASCII fallback option |

### B.2 First Launch Failures (5 Scenarios)

| ID | Scenario | Impact | Mitigation |
|----|----------|--------|------------|
| **F09** | Python dependencies missing | Import errors | Verify critical packages post-install |
| **F10** | Git clone fails (network) | No app | Retry with exponential backoff |
| **F11** | Git clone fails (auth) | No app | Clear error with documentation link |
| **F12** | Browser won't open | User confusion | Display URL in console as fallback |
| **F13** | Database init fails | App crashes | Error handling, temp DB fallback |

### B.3 Model Download Failures (4 Scenarios)

| ID | Scenario | Impact | Mitigation |
|----|----------|--------|------------|
| **F14** | Hugging Face rate limit | Download fails | Retry with exponential backoff |
| **F15** | Partial download | Corrupted model | Resume support + checksum verification |
| **F16** | Disk full mid-download | Download fails | Pre-check space, monitor during download |
| **F17** | Model file locked by AV | Can't load model | Retry with delay, clear error message |

### B.4 App Update Failures (5 Scenarios)

| ID | Scenario | Impact | Mitigation |
|----|----------|--------|------------|
| **F18** | Git pull fails (conflicts) | Update blocked | Clear error, guide to resolve conflicts |
| **F19** | Git pull fails (network) | Update blocked | Retry, continue with current version |
| **F20** | New version breaks app | App crashes | Rollback via git reset |
| **F21** | User modified app files | Conflicts | Warn before update, offer backup |
| **F22** | Bundled git not found | Update blocked | Fall back to system git if available |

### B.5 Runtime Update Failures (Phase 2) (5 Scenarios)

**NOTE:** Runtime updates are NOT in MVP. MVP users upgrade runtime by downloading and installing the latest installer.

| ID | Scenario | Impact | Phase |
|----|----------|--------|-------|
| **F23** | Partial runtime download | Corrupted update | Phase 2 |
| **F24** | Power loss during update | Broken installation | Phase 2 |
| **F25** | Update breaks compatibility | App won't start | Phase 2 |
| **F26** | Rollback fails | Dead installation | Phase 2 |
| **F27** | New runtime needs deps | Import errors | Phase 2 |

**MVP Approach:** Runtime updates delivered via new installer (manual download/reinstall).

---

## PART C: INSTALLER & UPDATER ARCHITECTURE OPTIONS

### C.1 MVP Update Strategy

**App Updates (IN MVP):**
- **Method:** Git-based updates via launcher or `/update` API endpoint
- **Mechanism:** 
  - Launcher performs `git fetch` and `git pull --ff-only` on startup
  - FastAPI app exposes `/update/status` and `/update/apply` endpoints
  - Small updates (code changes only), fast, no reinstall needed
- **User Experience:** Automatic on launch, or manual via UI button

**Runtime Updates (PHASE 2):**
- **Method:** New installer download (manual reinstall/upgrade)
- **Mechanism:**
  - User downloads latest LocalisSetup.exe from website/GitHub
  - Run installer, which preserves user data during upgrade
  - Runtime (Python, Git, dependencies) replaced atomically
- **User Experience:** Manual check for updates, download new installer, run to upgrade
- **Why not MVP:** Complex atomic swap logic, rollback, staging = 2-3 extra dev days

### C.2 Comparison of Installer Technologies

#### **Option 1: Inno Setup + Git-Based Updates** ⭐ RECOMMENDED FOR MVP

**Pros:**
- Mature, stable (25+ years)
- Native Windows integration (Start Menu, Add/Remove Programs)
- Flexible scripting
- Works on Windows 7-11
- Easy code signing
- Free hosting (GitHub Releases)
- Fast to implement (2-3 days for working installer)

**Cons:**
- No built-in runtime auto-update (OK for MVP, use git for app updates)
- Manual version management

**Update Mechanism:**
- **App updates:** Launcher uses bundled git to pull latest code (automatic, fast)
- **Runtime updates:** Download new installer and reinstall (Phase 2)

**Why This is Best for MVP:**
- Satisfies all non-negotiable requirements (clean Windows machine, no CLI)
- App updates work automatically via git (small, frequent updates)
- Runtime updates deferred to Phase 2 (infrequent, better to perfect)
- Fastest path to working installer (critical for Jan 26 deadline)

#### **Option 2: MSIX + App Installer** ❌ NOT RECOMMENDED

**Pros:**
- Native Win10/11 auto-updates
- Automatic delta updates
- Sandboxed

**Cons:**
- Requires Win10 1809+ (excludes Win7/8)
- **Filesystem virtualization breaks git operations and model downloads**
- Expensive EV cert required ($300+/year)
- Complex debugging

**Verdict:** Filesystem restrictions are a dealbreaker for Localis.

#### **Option 3: Squirrel.Windows / Velopack** ⚠️ COMPLEX

**Pros:**
- Excellent delta updates
- Used by Slack/Discord

**Cons:**
- Designed for .NET apps
- Requires significant adaptation for Python
- Learning curve

**Verdict:** Complexity outweighs benefits for MVP. Revisit in Phase 2 if runtime auto-update demand is high.

#### **Option 4: WiX Toolset** ❌ OVERKILL

**Pros:**
- MSI for enterprise deployment
- Full control

**Cons:**
- Steep learning curve
- No built-in in-place updates
- User data preservation tricky

**Verdict:** Too complex for marginal benefits.

---

## PART D: RECOMMENDED INSTALLER IMPLEMENTATION

### D.1 Installation Layout

```
C:\Users\<user>\AppData\Local\Localis\
├─ runtime\
│  ├─ python\          (embeddable Python 3.11.11)
│  │  ├─ python.exe
│  │  ├─ python311.zip
│  │  └─ python311._pth
│  └─ git\             (MinGit portable)
│     └─ bin\
│        └─ git.exe
├─ app\                (git cloned on first launch)
│  ├─ app\
│  │  ├─ main.py
│  │  ├─ updater.py
│  │  └─ ...
│  └─ requirements.txt
├─ models\             (user downloads models here)
├─ data\               (database, persistent data)
│  └─ chat_history.db
├─ logs\
├─ Localis.exe         (launcher)
├─ localis_runtime_config.json
└─ version.txt
```

### D.2 Launcher Responsibilities

The `Localis.exe` launcher (built from `launcher_windows.py` via PyInstaller):

1. **Find bundled runtime**
   - Locate `runtime/python/python.exe`
   - Locate `runtime/git/bin/git.exe`

2. **Clone/update app repository**
   - First run: Clone app repo using bundled git
   - Subsequent runs: `git pull --ff-only` to get latest code

3. **Pass bundled git to server process**
   - Set `LOCALIS_GIT_EXE` environment variable for server process
   - Add git directory to PATH for server subprocess
   - Server can now perform git operations without system git installed

4. **Start FastAPI server**
   - Run `python -m uvicorn app.main:app`
   - Set environment variables (MODEL_PATH, LOCALIS_DATA_DIR, LOCALIS_GIT_EXE)

5. **Open browser**
   - Wait 3 seconds
   - Open `http://127.0.0.1:8000`

### D.3 Update Flows

#### App Updates (MVP - Automatic)

**Scenario 1: Update on Launch**
1. User launches `Localis.exe`
2. Launcher checks for app updates (`git fetch`, `git pull --ff-only`)
3. If updates found, pulls changes (fast, <10 seconds)
4. Starts server with updated code
5. User sees latest version automatically

**Scenario 2: Manual Update via UI**
1. User clicks "Check for Updates" button in app
2. App calls `/update/status` endpoint
3. If updates available, user clicks "Update Now"
4. App calls `/update/apply` endpoint (git pull)
5. App prompts user to restart (or auto-restart if supported)

**Key Advantages:**
- No full reinstall needed
- Small downloads (only changed files)
- Fast (git is very efficient)
- Rollback available via `git reset`

#### Runtime Updates (Phase 2 - Manual Reinstall)

**Scenario: Upgrade Python/Git/Dependencies**
1. User visits Localis website or GitHub Releases
2. Downloads latest `LocalisSetup.exe`
3. Runs installer
4. Installer detects existing installation
5. Installer preserves `data/`, `models/`, and `app/` directories
6. Installer replaces `runtime/` directory with new version
7. Installer updates `version.txt`
8. User launches app as normal

**Why Deferred to Phase 2:**
- Runtime updates are infrequent (quarterly or less)
- App updates are frequent (weekly/daily), so those are prioritized for MVP
- Atomic runtime swapping requires 2-3 days of careful development
- Manual reinstall is acceptable for infrequent runtime upgrades

---

## PART E: PHASED IMPLEMENTATION PLAN

### E.1 Phase 1: Fix Critical Blockers

**Duration:** 1-2 days  
**Goal:** Working runtime pack that can be extracted and tested

#### Task 1.1: Fix llama-cpp-python Build Issue

**Problem:** No pre-compiled wheel for Python 3.12.8, requires Visual C++ build tools.

**Solution:**
```powershell
# Option A: Use Python 3.11.11 with better wheel availability
$PYTHON_VERSION = "3.11.11"
$PYTHON_URL = "https://www.python.org/ftp/python/3.11.11/python-3.11.11-embed-amd64.zip"

# Option B: Download pre-compiled wheel
$WHEEL_URL = "https://github.com/abetlen/llama-cpp-python/releases/download/v0.3.16/llama_cpp_python-0.3.16-cp311-cp311-win_amd64.whl"
pip install $WHEEL_URL
```

**Verification:**
```powershell
# Test import
& ".\runtime\python\python.exe" -c "import llama_cpp; print(llama_cpp.__version__)"
```

#### Task 1.2: Fix BOM in python._pth File

**Problem:** UTF-8 BOM breaks Python path resolution.

**Solution (Already Applied):**
```powershell
# Line 173 in build script
[System.IO.File]::WriteAllLines($pthFile, $newContent, (New-Object System.Text.UTF8Encoding($false)))
```

**Verification:**
```powershell
# Check for BOM
$bytes = [System.IO.File]::ReadAllBytes("python311._pth")
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Error "BOM detected!"
} else {
    Write-Host "No BOM - OK"
}
```

#### Task 1.3: Fix Archive Structure

**Problem:** ZIP extracts with wrong directory hierarchy.

**Solution:**
```powershell
# Use explicit entry paths when creating zip
foreach ($item in $itemsToZip) {
    $zipEntry = $zip.CreateEntry($item.ArchivePath)
    # Copy file content to entry
}
```

**Verification:**
```powershell
# List zip contents
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("LocalisRuntimePack.zip")
$zip.Entries | Select-Object FullName
# Should show: runtime/python/python.exe, launcher_windows.py, etc.
```

#### Task 1.4: Copy Launcher from App Repo

**Problem:** Launcher script not included in runtime pack.

**Solution:**
```powershell
# Copy from app repository
$env:LOCALIS_APP_REPO_PATH = "D:\localis-app"
$launcherSource = Join-Path $env:LOCALIS_APP_REPO_PATH "launcher_windows.py"
$launcherDest = Join-Path $DIST_DIR "launcher_windows.py"
Copy-Item $launcherSource $launcherDest -ErrorAction Stop
```

**Verification:**
```powershell
Test-Path ".\dist\LocalisRuntimePack\launcher_windows.py"  # Should be TRUE
```

#### Task 1.5: Add SHA256 Verification

**Problem:** No integrity checking for downloads.

**Solution:**
```powershell
# After downloading Python embed zip
$expectedHash = "abc123..."  # Get from Python.org
$actualHash = (Get-FileHash -Path $PYTHON_EMBED_ZIP -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Checksum mismatch!"
}
```

**Acceptance Criteria:**
- ✅ Build completes without errors
- ✅ Runtime pack has correct structure (`runtime/python/python.exe` at root level)
- ✅ `launcher_windows.py` included
- ✅ SHA256 verification passes
- ✅ Test extraction works on clean Windows 10 VM

---

### E.2 Phase 2: Packaging Prototype

**Duration:** 2-3 days  
**Goal:** Working installer that deploys on clean Windows machines

#### Task 2.1: Create PyInstaller Launcher Executable

**Goal:** Build `Localis.exe` from `launcher_windows.py`

**File:** `launcher_windows.spec`

```python
# launcher_windows.spec
# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['launcher_windows.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['uvicorn', 'fastapi', 'pydantic', 'httpx', 'sqlite3'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='Localis',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # No console window
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='app_icon.ico',  # Your app icon
    version='file_version_info.txt'
)
```

**Build Command:**
```powershell
# Install PyInstaller
pip install pyinstaller

# Build executable
pyinstaller launcher_windows.spec

# Result: dist\Localis\Localis.exe (~10-15MB)
```

**Verification:**
```powershell
# Test executable
.\dist\Localis\Localis.exe
# Should launch and attempt to find runtime
```

#### Task 2.2: Create Inno Setup Installer Script

**Goal:** Package runtime + launcher into `LocalisSetup.exe`

**File:** `installer.iss`

```inno
; Localis Installer Script for Inno Setup 6.x

#define MyAppName "Localis"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Localis Team"
#define MyAppURL "https://localis.ai"
#define MyAppExeName "Localis.exe"

[Setup]
AppId={{YOUR-GUID-HERE}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Localis
DisableProgramGroupPage=yes
LicenseFile=LICENSE.txt
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=LocalisSetup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Launcher executable
Source: "dist\Localis\Localis.exe"; DestDir: "{app}"; Flags: ignoreversion

; Runtime (Python + Git)
Source: "dist\runtime\*"; DestDir: "{app}\runtime"; Flags: ignoreversion recursesubdirs createallsubdirs

; Config template
Source: "localis_runtime_config.json"; DestDir: "{app}"; Flags: ignoreversion

; Version tracking
Source: "version.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\app"
Type: filesandordirs; Name: "{app}\logs"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  // Check Windows version (minimum Windows 10)
  if (GetWindowsVersion shr 24) < 10 then
  begin
    MsgBox('This application requires Windows 10 or later.', mbError, MB_OK);
    Result := False;
    Exit;
  end;

  // Check if another instance is running
  if CheckForMutexes('Local\LocalisRunningMutex') then
  begin
    MsgBox('Localis is currently running. Please close it before installing.', mbInformation, MB_OK);
    Result := False;
    Exit;
  end;

  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  // Pre-install checks
  
  // Check disk space (need at least 2GB free)
  if GetSpaceOnDisk(ExpandConstant('{app}'), False, nil, nil, nil) < (2 * 1024 * 1024 * 1024) then
  begin
    Result := 'Insufficient disk space. At least 2GB free space required.';
    Exit;
  end;

  Result := '';
end;
```

**Build Command:**
```powershell
# Install Inno Setup from https://jrsoftware.org/isdl.php

# Build installer
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

# Result: dist\LocalisSetup-1.0.0.exe (~450MB)
```

**Verification:**
```powershell
# Test installer on clean Windows 10 VM
# 1. Run LocalisSetup-1.0.0.exe
# 2. Complete installation wizard
# 3. Launch from Start Menu
# 4. Verify app launches and opens browser
```

#### Task 2.3: Test End-to-End on Clean Machine

**VM Setup:**
- Windows 10 (clean install, no dev tools)
- No Python installed
- No Git installed
- No Visual Studio build tools

**Test Steps:**
1. Download `LocalisSetup-1.0.0.exe`
2. Run installer
3. Click through wizard
4. Choose "Launch Localis" at completion
5. Wait for first launch (clones repo, installs model)
6. Browser should open to `http://127.0.0.1:8000`
7. Close app
8. Launch again from Start Menu (should be faster)

**Acceptance Criteria:**
- ✅ Installation completes in <2 minutes
- ✅ Shortcuts work (Start Menu, Desktop)
- ✅ First launch clones repo successfully
- ✅ Browser opens automatically
- ✅ Second launch skips clone, just pulls updates (<10 seconds)

---

### E.3 Phase 3: App Update Integration (MVP)

**Duration:** 1-2 days  
**Goal:** Users can update app code without reinstalling

#### Task 3.1: Ensure Launcher Passes Bundled Git to Server

**Problem:** Server needs git for `/update` endpoints, but git is bundled, not in system PATH.

**Solution:** Modify `launcher_windows.py` to pass bundled git to server process.

**Changes:**

```python
# In launch_server() function, add git environment variables

def launch_server(python_exe, install_root, app_dir, host, port, git_exe):
    """Launch the uvicorn server with proper environment variables."""
    env = os.environ.copy()
    env['MODEL_PATH'] = str(install_root / 'models')
    env['LOCALIS_DATA_DIR'] = str(install_root / 'data')
    
    # Pass bundled git to server process
    if git_exe and git_exe != 'git':
        # Absolute path to bundled git
        env['LOCALIS_GIT_EXE'] = git_exe
        
        # Add git bin directory to PATH for subprocess calls
        git_bin = str(Path(git_exe).parent)
        env['PATH'] = git_bin + os.pathsep + env.get('PATH', '')
        
        logger.info(f"Setting LOCALIS_GIT_EXE={git_exe}")
        logger.info(f"Adding to PATH: {git_bin}")
    else:
        # System git or not found
        env['LOCALIS_GIT_EXE'] = 'git'
    
    # ... rest of launch_server code
```

**Update main() to pass git_exe:**
```python
# In main(), update launch_server call
process = launch_server(python_exe, install_root, app_dir, host, port, git_exe)
```

#### Task 3.2: Update `updater.py` to Use Bundled Git

**Problem:** `updater.py` currently hard-codes `git` command, which fails if git not in PATH.

**Solution:** Read `LOCALIS_GIT_EXE` environment variable.

**Changes to `updater.py`:**

```python
import os
from pathlib import Path

# At module level, determine git executable
_GIT_EXE = None

def _get_git_exe() -> str:
    """Get git executable path from environment or fallback to 'git'."""
    global _GIT_EXE
    if _GIT_EXE is None:
        git_path = os.environ.get('LOCALIS_GIT_EXE', 'git')
        
        # If absolute path, verify it exists
        if git_path != 'git':
            if not Path(git_path).exists():
                # Fallback to 'git' if specified path doesn't exist
                _GIT_EXE = 'git'
            else:
                _GIT_EXE = git_path
        else:
            _GIT_EXE = 'git'
    
    return _GIT_EXE

def _git_available() -> bool:
    try:
        git_exe = _get_git_exe()
        subprocess.run([git_exe, "--version"], capture_output=True, text=True, check=True)
        return True
    except Exception:
        return False

def _run_git(root: Path, args: list[str]) -> subprocess.CompletedProcess:
    git_exe = _get_git_exe()
    return subprocess.run([git_exe] + args, cwd=str(root), capture_output=True, text=True)
```

**Why This Works:**
- Launcher sets `LOCALIS_GIT_EXE` to bundled git path
- Server process inherits this environment variable
- `updater.py` reads it and uses bundled git
- If not set, falls back to system git (backward compatible)

#### Task 3.3: Test App Updates on Clean Machine

**Test Scenario:**
1. Install Localis on clean Windows VM (no system git)
2. Launch app
3. Open DevTools, check console for `/update/status` API
4. Should return `{"supported": true, ...}`
5. Make a commit to app repo (test change)
6. In app UI, click "Check for Updates"
7. Should detect new commit
8. Click "Update Now"
9. Should call `/update/apply` and succeed
10. Restart app, verify changes applied

**Acceptance Criteria:**
- ✅ `/update/status` returns `supported: true` (not `git_not_found`)
- ✅ Updates detected correctly
- ✅ `git pull` succeeds without requiring system git
- ✅ App restarts with updated code

---

### E.4 Phase 4: Hardening & Polish

**Duration:** 2-3 days  
**Goal:** Production-ready installer with error handling and UX improvements

#### Task 4.1: Comprehensive Error Handling

**Add to Installer:**
- Disk space checks before extraction
- Running instance detection (mutex)
- Detailed error messages with recovery hints

**Add to Launcher:**
- Better error messages for common issues
- Automatic port selection if 8000 in use
- Retry logic for network operations

**Add to App:**
- Graceful degradation if git unavailable
- User-friendly error dialogs
- Recovery mode for database corruption

#### Task 4.2: Preflight Checks in Installer

**Checks:**
1. Windows version (minimum Win10)
2. Disk space (need 2GB free)
3. Write permissions to install directory
4. No running instances
5. Network connectivity (optional, for first launch clone)

**Display Results:**
- Green checkmarks for passed checks
- Warning/error icons for failures
- Help text for failed checks

#### Task 4.3: UX Improvements

**During Installation:**
- Progress bar with stages ("Extracting Python runtime...", "Copying files...", etc.)
- Estimated time remaining
- Option to create desktop shortcut

**First Launch:**
- Splash screen with Localis logo
- Progress indicator during repo clone
- "First run setup" wizard (optional model selection)

**System Tray Icon:**
- Show status (running, updating, idle)
- Right-click menu (Open, Check for Updates, Quit)

**Better Update UI:**
- Toast notification when updates available
- Download progress bar
- Release notes preview
- One-click update + restart

#### Task 4.4: Documentation & Support

**User Documentation:**
- Installation guide (with screenshots)
- Troubleshooting common issues
- Update guide
- Uninstall guide (preserving data)

**Developer Documentation:**
- Build script documentation
- Installer customization guide
- Release checklist

**Acceptance Criteria:**
- ✅ All preflight checks work correctly
- ✅ Error messages are clear and actionable
- ✅ First-run experience is smooth
- ✅ System tray integration works
- ✅ Documentation is complete

---

## PART F: TESTING & VALIDATION

### F.1 Installation Tests

| Test ID | Scenario | Expected Result | Status |
|---------|----------|----------------|--------|
| **T01** | Fresh install on clean Win10 | Installs successfully in <2 min | ☐ |
| **T02** | Fresh install on clean Win11 | Installs successfully in <2 min | ☐ |
| **T03** | Install with desktop icon unchecked | No desktop icon created | ☐ |
| **T04** | Install to custom directory | Works correctly | ☐ |
| **T05** | Install while instance running | Blocks with error message | ☐ |
| **T06** | Install with insufficient disk space | Errors before extraction | ☐ |
| **T07** | Reinstall over existing | Preserves data, upgrades runtime | ☐ |
| **T08** | Silent install (`/SILENT` flag) | Installs without UI | ☐ |

### F.2 Launch Tests

| Test ID | Scenario | Expected Result | Status |
|---------|----------|----------------|--------|
| **T11** | First launch (no app repo) | Clones repo, starts server, opens browser | ☐ |
| **T12** | Second launch (repo exists) | Pulls updates, starts server (<10s) | ☐ |
| **T13** | Launch from Start Menu | Works correctly | ☐ |
| **T14** | Launch from desktop shortcut | Works correctly | ☐ |
| **T15** | Launch with port 8000 occupied | Finds alternative port, works | ☐ |
| **T16** | Launch without network | Shows error, continues offline | ☐ |
| **T17** | Multiple launch attempts | Detects running instance, shows error | ☐ |

### F.3 App Update Tests (MVP)

| Test ID | Scenario | Expected Result | Status |
|---------|----------|----------------|--------|
| **T21** | Check for updates (newer available) | Shows "Update Available" | ☐ |
| **T22** | Check for updates (up-to-date) | Shows "Up to date" | ☐ |
| **T23** | Download update (with progress) | Progress bar shows download | ☐ |
| **T24** | Apply update (clean working tree) | Update succeeds, prompts restart | ☐ |
| **T25** | Apply update (dirty working tree) | Blocks with error message | ☐ |
| **T26** | Git pull fails (network) | Shows error, retry option | ☐ |
| **T27** | Automatic update on launch | Pulls latest code without user action | ☐ |

### F.4 Uninstall Tests

| Test ID | Scenario | Expected Result | Status |
|---------|----------|----------------|--------|
| **T31** | Uninstall via Add/Remove Programs | Uninstaller runs | ☐ |
| **T32** | Uninstall with "keep data" option | Removes app, preserves data/models | ☐ |
| **T33** | Uninstall with "remove all" option | Removes everything | ☐ |
| **T34** | Reinstall after uninstall | Works correctly | ☐ |

---

## PART G: DEPLOYMENT CHECKLIST

### G.1 Pre-Release Checklist

- [ ] All blocker errors fixed (ERR-001 through ERR-007)
- [ ] Build script runs cleanly on Windows 10/11
- [ ] Runtime pack structure verified
- [ ] Launcher executable built and tested
- [ ] Installer built and tested on clean VMs
- [ ] All installation tests passing (T01-T08)
- [ ] All launch tests passing (T11-T17)
- [ ] All app update tests passing (T21-T27)
- [ ] All uninstall tests passing (T31-T34)
- [ ] Code signing certificate acquired
- [ ] Launcher.exe signed with Authenticode
- [ ] LocalisSetup.exe signed with Authenticode
- [ ] Documentation complete (installation, troubleshooting, updates)
- [ ] Release notes written
- [ ] GitHub Release created with:
  - [ ] LocalisSetup.exe
  - [ ] SHA256 checksums
  - [ ] Release notes
  - [ ] Installation instructions

### G.2 Post-Release Monitoring

**First 48 Hours:**
- Monitor GitHub Issues for installation problems
- Check telemetry (if implemented) for crash rates
- Watch for antivirus false positives

**First Week:**
- Gather user feedback on installation UX
- Track update success rates
- Identify most common support issues

**First Month:**
- Analyze which failure modes occurred in production
- Prioritize fixes for next release
- Evaluate if Phase 2 (runtime auto-update) is needed

---

## APPENDIX A: QUICK START (5 Minutes)

```powershell
# Step 1: Set environment variable
$env:LOCALIS_APP_REPO_PATH = "D:\localis-app"

# Step 2: Run fixed build script
.\build_runtime_pack_windows.ps1

# Step 3: Verify structure
Expand-Archive .\dist\LocalisRuntimePack.zip -DestinationPath .\test -Force
Test-Path .\test\runtime\python\python.exe  # Should be TRUE
Test-Path .\test\launcher_windows.py         # Should be TRUE

# Step 4: Test launcher
& ".\test\runtime\python\python.exe" ".\test\launcher_windows.py"
```

**Expected:** Build completes without errors, launcher starts successfully.

---

## APPENDIX B: MVP vs Phase 2 Features

| Feature | MVP (Days 1-5) | Phase 2 (Post-MVP) |
|---------|----------------|-------------------|
| **Installation** | ✅ Inno Setup installer | ✅ Same |
| **Clean Windows machine** | ✅ No dev tools needed | ✅ Same |
| **Bundled runtime** | ✅ Python + Git | ✅ Same |
| **App updates** | ✅ Git-based (automatic) | ✅ Same |
| **Runtime updates** | ⏸️ Manual reinstall | ✅ In-app with rollback |
| **Update frequency** | App: daily/weekly | App: same, Runtime: quarterly |
| **User experience** | App: seamless, Runtime: manual download | App: seamless, Runtime: seamless |
| **Dev complexity** | Low (git pull) | High (atomic swap, rollback) |
| **Time to implement** | 5 days | +3 days |

**MVP Philosophy:** 
- Ship fast with app updates (frequent, important)
- Defer runtime updates (infrequent, complex)
- Validate user demand before investing 3 extra days

---

## APPENDIX C: Key Commands Reference

### Build Commands

```powershell
# Build runtime pack
.\build_runtime_pack_windows.ps1

# Build launcher executable
pyinstaller launcher_windows.spec

# Build installer
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
```

### Test Commands

```powershell
# Test runtime pack
Expand-Archive .\dist\LocalisRuntimePack.zip -DestinationPath .\test -Force
& ".\test\runtime\python\python.exe" ".\test\launcher_windows.py"

# Test launcher executable
.\dist\Localis\Localis.exe

# Test installer (on VM)
.\dist\LocalisSetup-1.0.0.exe
```

### Verification Commands

```powershell
# Check Python runtime
& ".\runtime\python\python.exe" -c "import sys; print(sys.version)"

# Check llama-cpp-python
& ".\runtime\python\python.exe" -c "import llama_cpp; print(llama_cpp.__version__)"

# Check git
.\runtime\git\bin\git.exe --version

# Check for BOM in _pth file
$bytes = [System.IO.File]::ReadAllBytes("runtime\python\python311._pth")
$bytes[0..2]  # Should NOT be: 239, 187, 191 (UTF-8 BOM)
```

---

## APPENDIX D: Troubleshooting Guide

### Issue: "Python module 'encodings' not found"

**Cause:** BOM in python._pth file

**Fix:**
```powershell
# Recreate _pth file without BOM
$pthFile = "runtime\python\python311._pth"
$content = @"
python311.zip
.

import site
"@
[System.IO.File]::WriteAllLines($pthFile, $content.Split("`n"), (New-Object System.Text.UTF8Encoding($false)))
```

### Issue: "llama_cpp module not found"

**Cause:** Missing or failed to install llama-cpp-python

**Fix:**
```powershell
# Download pre-compiled wheel
$url = "https://github.com/abetlen/llama-cpp-python/releases/download/v0.3.16/llama_cpp_python-0.3.16-cp311-cp311-win_amd64.whl"
Invoke-WebRequest -Uri $url -OutFile "llama_cpp_python.whl"

# Install wheel
& ".\runtime\python\python.exe" -m pip install "llama_cpp_python.whl"
```

### Issue: "/update/status returns git_not_found"

**Cause:** Server process doesn't have access to bundled git

**Fix:** Verify launcher is setting `LOCALIS_GIT_EXE` environment variable

```python
# In launcher_windows.py launch_server()
env['LOCALIS_GIT_EXE'] = git_exe  # Should be absolute path to bundled git
```

### Issue: "Port 8000 already in use"

**Cause:** Another process using port 8000

**Fix:** Set different port
```powershell
$env:LOCALIS_PORT = "8001"
.\Localis.exe
```

---

**END OF DOCUMENT**
