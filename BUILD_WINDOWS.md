# Running LocalMind on Windows

This document covers running LocalMind on Windows using the bundled runtime pack.

## For End Users

**No installation required!** LocalMind comes with everything you need - no need to install Python, pip, Visual Studio Build Tools, cmake, or uvicorn.

### Quick Start

1. **Download and Extract**
   - Download `LocalisRuntimePack.zip`
   - Extract to a folder (e.g., `C:\LocalMind`)

2. **Configure Repository**
   - Edit `localis_runtime_config.json` and set your repository URL:
     ```json
     {
       "repo_url": "https://github.com/yourusername/localis.git",
       "branch": "release"
     }
     ```

3. **Run the Launcher**
   - Double-click `launcher_windows.py` (or run via command prompt)
   - The launcher will:
     - Clone the application repository
     - Start the local server
     - Open your browser automatically

4. **Enjoy!**
   - Application runs at `http://127.0.0.1:8000`
   - Press `Ctrl+C` in the console to stop

### What's Included

The runtime pack contains:
- **launcher_windows.py**: Bootstrap launcher
- **runtime\python\**: Embeddable Python 3.11.x with all dependencies
- **runtime\git\**: Portable Git for repository management
- **localis_runtime_config.json**: Configuration file

### Installation Location

LocalMind installs to: **`%LOCALAPPDATA%\Localis`**

Typical path: `C:\Users\<YourUsername>\AppData\Local\Localis`

#### Directory Layout

```
%LOCALAPPDATA%\Localis\
├── app\              # Cloned application repository (auto-updated)
├── models\           # Place your GGUF model files here
├── data\             # SQLite database, user data
├── runtime\          # Can copy runtime here for portability
└── logs\             # Application logs
```

### Configuration Options

Edit `localis_runtime_config.json` for custom settings:

```json
{
  "repo_url": "https://github.com/yourusername/localis.git",
  "branch": "release",
  "host": "127.0.0.1",
  "port": 8000
}
```

**Configuration keys**:
- `repo_url`: Git repository URL for the application
- `branch`: Git branch to use (default: "main")
- `host`: Server host address (default: "127.0.0.1")
- `port`: Server port number (default: 8000)

### Automatic Updates

The launcher automatically updates the application on each run:
- If the repository exists: runs `git fetch --depth=1` then `git pull --ff-only`
- If the repository doesn't exist: clones it fresh with `git clone --depth=1 --branch <branch>`

The launcher uses fast-forward-only pulls to avoid merge conflicts. If the local repository has diverged from the remote, the update will fail gracefully and continue with the existing local copy.

To disable updates (for development), manually manage the repository in `%LOCALAPPDATA%\Localis\app`.

### Adding Models

1. Download GGUF model files (e.g., from Hugging Face)
2. Place them in: `%LOCALAPPDATA%\Localis\models\`
3. The application will detect them automatically

## Troubleshooting

### Issue: "Runtime payload missing"

**Error Message**:
```
ERROR: Runtime payload missing
The bundled Python runtime is required but not found.
```

**Cause**: The `runtime\python\` folder is missing or incomplete.

**Solution**:
1. Ensure you extracted the complete zip file
2. Verify `runtime\python\python.exe` exists in the launcher directory
3. Re-download the runtime pack if corrupted

---

### Issue: "Git not found"

**Error Message**:
```
ERROR: Git not found
Git is required to download the application.
```

**Cause**: The `runtime\git\` folder is missing.

**Solution**:
1. Ensure `runtime\git\bin\git.exe` exists in the launcher directory
2. Or install Git system-wide: [git-scm.com](https://git-scm.com/download/win)
3. Re-download the runtime pack if needed

---

### Issue: Failed to clone repository

**Error Message**:
```
ERROR: Failed to clone repository
```

**Possible Causes**:
- Invalid repository URL in config file
- Network connectivity issues
- Private repository requiring authentication

**Solutions**:

1. **Check repository URL**:
   - Verify the URL in `localis_runtime_config.json`
   - Ensure it ends with `.git`
   - Example: `https://github.com/user/localis.git`

2. **For private repositories**:
   - Use HTTPS URL with personal access token:
     ```
     https://username:TOKEN@github.com/user/localis.git
     ```
   - Or use SSH URL (requires SSH key setup):
     ```
     git@github.com:user/localis.git
     ```

3. **Check network**:
   - Ensure internet connection is active
   - Try cloning manually to verify access:
     ```cmd
     cd %LOCALAPPDATA%\Localis
     git clone https://github.com/user/localis.git app
     ```

---

### Issue: Port already in use

**Error Message**:
```
Address already in use
```

**Cause**: Another application is using port 8000.

**Solution**:
1. Change port in `localis_runtime_config.json`:
   ```json
   {
     "port": 8001
   }
   ```
2. Or the launcher will automatically find the next available port

---

### Issue: Browser doesn't open automatically

**Cause**: Default browser not configured or system restriction.

**Solution**:
- Manually open your browser to: `http://127.0.0.1:8000`
- The application is running even if the browser didn't open

---

### Issue: Application shows errors about missing models

**Cause**: No GGUF model files in the models directory.

**Solution**:
1. Download a GGUF model file
2. Place in: `%LOCALAPPDATA%\Localis\models\`
3. Restart the application

---

### Issue: Failed to update repository (git pull errors)

**Error Message**:
```
Failed to update repository
```

**Cause**: Local changes conflict with remote updates, or branch diverged.

**Solution**:
1. The launcher continues with existing repository state
2. Manually fix in `%LOCALAPPDATA%\Localis\app`:
   ```cmd
   cd %LOCALAPPDATA%\Localis\app
   git status
   git stash  # If you have local changes
   git pull origin release
   ```

---

### Issue: Server starts but shows dependency errors

**Cause**: Incomplete or corrupted Python runtime dependencies.

**Solution**:
1. Delete `%LOCALAPPDATA%\Localis` completely
2. Re-extract the runtime pack
3. Run launcher again for fresh installation

---

## For Developers

### Prerequisites (Development Only)

To build the runtime pack or run as a development script:

- **Python 3.10+** installed on your development machine
- **PowerShell** (for running build script)
- **Internet connection** (to download embeddable Python and portable Git)

### Running as Development Script

```cmd
REM Install Python on your dev machine first
python --version

REM Create a config file
copy localis_runtime_config.json.example localis_runtime_config.json
notepad localis_runtime_config.json

REM Run the launcher with your system Python (will still look for bundled runtime)
python launcher_windows.py
```

**Note**: Even in dev mode, the launcher prefers bundled runtime. To use system Python, temporarily rename `runtime\python\` or set launcher to fallback mode.

### Building the Runtime Pack

See `build_runtime_pack_windows.ps1` for the automated build script.

**Quick build**:

```powershell
# Set path to your local Localis app repo
$env:LOCALIS_APP_REPO_PATH = "C:\dev\localis"

# Run build script (requires PowerShell 5.1+)
.\build_runtime_pack_windows.ps1

# Output: dist\LocalisRuntimePack.zip
```

The script will:
1. Download Python 3.11.x embeddable
2. Download portable Git
3. Install Python dependencies from `requirements.txt`
4. Install llama-cpp-python from precompiled wheel
5. Patch `python311._pth` to enable site-packages (UTF-8 without BOM)
6. Package everything into a distributable zip
7. Run verification tests (unless `-SkipVerify` is used)

### Building the PyInstaller Executable

To create the standalone `Localis.exe` launcher:

**Prerequisites**:
- Python 3.10+ installed
- PyInstaller installed: `pip install pyinstaller`

**Build commands**:

```powershell
# Install PyInstaller
pip install pyinstaller

# Build the executable using the provided spec file
pyinstaller LocalisLauncher.spec

# Output: dist\Localis\Localis.exe
```

**What gets built**:
- `dist\Localis\Localis.exe` - Thin launcher executable (~10-20 MB)
- `dist\Localis\*.dll` - Required Python runtime DLLs
- Various other PyInstaller support files

**Note**: The executable is "thin" - it does NOT include the Python/Git runtime. The runtime must be installed alongside it (handled by the installer).

### Building the Windows Installer

After building both the runtime pack and PyInstaller executable, you can create a complete installer.

**Prerequisites**:
- **Inno Setup 6.x** installed from [jrsoftware.org/isdl.php](https://jrsoftware.org/isdl.php)
- `dist\LocalisRuntimePack.zip` OR `dist\runtime\` exists (from runtime pack build)
- `dist\Localis\Localis.exe` exists (from PyInstaller build)

**Build commands**:

```powershell
# Basic build (auto-detects version from git or env var)
.\scripts\build_installer.ps1

# Build with explicit version
.\scripts\build_installer.ps1 -Version "1.0.0"

# Or set version via environment variable
$env:LOCALIS_VERSION = "1.2.3"
.\scripts\build_installer.ps1
```

**Expected output**:

```
===================================================================
  Step 1: Verifying build outputs
===================================================================
[OK] Found Localis.exe
[OK] Found runtime pack zip: dist\LocalisRuntimePack.zip
[OK] Found installer script: installer.iss

===================================================================
  Step 2: Preparing runtime directory
===================================================================
[INFO] Extracting runtime pack to dist\runtime...
[OK] Runtime pack extracted successfully
[OK] Runtime directory validated

===================================================================
  Step 3: Determining version
===================================================================
[INFO] Using version from git: 1.0.0
Installer Version: 1.0.0

===================================================================
  Step 4: Locating Inno Setup Compiler
===================================================================
[OK] Found ISCC at default location

===================================================================
  Step 5: Building installer
===================================================================
[INFO] Invoking Inno Setup Compiler...
[OK] Installer compiled successfully

===================================================================
  Build Complete
===================================================================

Installer created successfully!

Output file:
  C:\path\to\output\LocalisSetup-1.0.0.exe

Size: 52.34 MB
Version: 1.0.0

Next steps:
  1. Test the installer on a clean Windows machine
  2. Verify installation to %LOCALAPPDATA%\Localis
  3. Test launch, updates, and uninstall
```

**Installer features**:
- Per-user installation (no UAC required)
- Installs to `%LOCALAPPDATA%\Localis`
- Creates Start Menu and optional Desktop shortcuts
- "Launch Localis" checkbox at end of installation
- Smart uninstall: prompts to keep or delete user data

### Development Workflow

Complete workflow from source to installer:

```powershell
# 1. Build the runtime pack
$env:LOCALIS_APP_REPO_PATH = "C:\path\to\localis-app"
.\build_runtime_pack_windows.ps1

# 2. Build the PyInstaller executable
pip install pyinstaller
pyinstaller LocalisLauncher.spec

# 3. Build the Windows installer
.\scripts\build_installer.ps1 -Version "1.0.0"

# Output: output\LocalisSetup-1.0.0.exe
```

---

## Installer Test Checklist

Test the installer on a **clean Windows VM** (no Python, Git, or previous installations):

### Test 1: Fresh Installation

1. Double-click `LocalisSetup-1.0.0.exe`
2. **Expected**:
   - ✓ Installer runs without UAC prompt
   - ✓ No terminal/console window appears
   - ✓ Installation completes to `%LOCALAPPDATA%\Localis`

### Test 2: Shortcuts

1. Check Start Menu
2. **Expected**:
   - ✓ "Localis" shortcut present in Start Menu
   - ✓ Clicking shortcut launches application

3. If Desktop shortcut was selected during install:
   - ✓ Desktop shortcut works

### Test 3: First Launch

1. Check "Launch Localis" at end of installer
2. **Expected**:
   - ✓ Application launches
   - ✓ Browser opens to `http://127.0.0.1:8000`
   - ✓ Repository clones on first run
   - ✓ Application loads successfully

### Test 4: Second Launch

1. Close application (Ctrl+C or close window)
2. Launch again from Start Menu
3. **Expected**:
   - ✓ Second launch is faster (no clone, just update)
   - ✓ Git update runs (`git fetch` + `git pull`)
   - ✓ Application loads normally

### Test 5: Uninstall Behavior

1. Uninstall via Windows Settings or Control Panel
2. **Expected**:
   - ✓ Prompt asks: "Delete personal data?"
   - ✓ Choosing "No": Keeps models, data, config
   - ✓ Choosing "Yes": Removes everything
   - ✓ Silent uninstall defaults to keeping data

### Test 6: Reinstall (After Partial Uninstall)

1. Uninstall but keep data
2. Reinstall
3. **Expected**:
   - ✓ Previous models still present
   - ✓ Previous chat history intact
   - ✓ Config settings preserved

---

## Test Checklist (Runtime Pack Only)

### Test 1: Fresh Install with Config File

1. Delete `%LOCALAPPDATA%\Localis`
2. Place `localis_runtime_config.json` next to launcher with valid repo URL
3. Run `launcher_windows.py`
4. **Expected**:
   - Repository cloned
   - Server starts with bundled Python
   - Browser opens

### Test 2: Automatic Repository Update

1. Run launcher (creates initial clone)
2. Stop server (Ctrl+C)
3. Run launcher again
4. **Expected**:
   - Console shows "Updating existing repository..."
   - Shows "git fetch --depth=1" and "git pull --ff-only"
   - Server starts with latest code

### Test 3: Bundled Runtime Detection

1. Check console output when launching
2. **Expected**:
   - "Using bundled Python at: ...\runtime\python\python.exe"
   - "Using bundled git at: ...\runtime\git\bin\git.exe"
   - NOT using system Python

### Test 4: Config File Search Order

1. Create different configs:
   - `localis_runtime_config.json` next to launcher (port 8001)
   - `%LOCALAPPDATA%\Localis\localis_runtime_config.json` (port 8002)
2. Run launcher
3. **Expected**:
   - Uses launcher directory config (port 8001 takes precedence)

### Test 5: Port Configuration

1. Set in `localis_runtime_config.json`: `"port": 8001`
2. Run launcher
3. **Expected**:
   - Server runs on port 8001
   - If port 8001 is in use, launcher finds next available port

### Test 6: Missing Runtime Payload Error

1. Temporarily rename `runtime\python\` folder
2. Run launcher
3. **Expected**:
   - Clear error: "Runtime payload missing"
   - Lists expected locations
   - Exits gracefully

### Test 7: Data Persistence

1. Run application, complete tutorial
2. Place model in `%LOCALAPPDATA%\Localis\models\`
3. Stop server
4. Run launcher again
5. **Expected**:
   - Model still present
   - Tutorial completion status preserved
   - Database intact

---

## Support

For issues:
1. Check console output for error messages
2. Review logs in `%LOCALAPPDATA%\Localis\logs\`
3. Verify `localis_runtime_config.json` is valid JSON
4. Ensure complete runtime pack extraction
5. Try fresh install (delete `%LOCALAPPDATA%\Localis` and re-run)
