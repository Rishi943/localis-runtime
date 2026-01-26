# Running LocalMind on Windows

This document covers running LocalMind on Windows using the bundled runtime pack.

## For End Users

**No installation required!** LocalMind comes with everything you need - no need to install Python, pip, Visual Studio Build Tools, cmake, or uvicorn.

### Quick Start

1. **Download and Extract**
   - Download `LocalisRuntimePack.zip`
   - Extract to a folder (e.g., `C:\LocalMind`)

2. **Configure Repository**
   - Copy `localis_runtime_config.json.example` to `localis_runtime_config.json`
   - Edit the file and set your repository URL:
     ```json
     {
       "app_repo_url": "https://github.com/yourusername/localis.git",
       "app_branch": "release"
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
- **runtime\python\**: Embeddable Python 3.12 with all dependencies
- **runtime\git\**: Portable Git for repository management
- **localis_runtime_config.json.example**: Configuration template

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
  "app_repo_url": "https://github.com/yourusername/localis.git",
  "app_branch": "release",
  "host": "127.0.0.1",
  "port": 8000,
  "install_root": "C:\\Users\\YourUsername\\AppData\\Local\\Localis"
}
```

**Configuration Priority**: Environment variables override config file values.

#### Optional Environment Variables

For advanced users, you can override config via environment variables:

```cmd
set LOCALIS_APP_REPO_URL=https://github.com/user/localis.git
set LOCALIS_APP_BRANCH=main
set LOCALIS_HOST=127.0.0.1
set LOCALIS_PORT=8080
set LOCALIS_INSTALL_ROOT=D:\MyApps\Localis
```

### Automatic Updates

The launcher automatically updates the application on each run:
- If the repository exists: runs `git fetch`, `git checkout <branch>`, `git pull --ff-only`
- If the repository doesn't exist: clones it fresh

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
2. Or set environment variable:
   ```cmd
   set LOCALIS_PORT=8001
   ```

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

REM Optional: Enable auto-reload for development
set LOCALIS_DEV_RELOAD=1
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
1. Download Python 3.12 embeddable
2. Download portable Git
3. Install Python dependencies from `requirements.txt`
4. Patch `python312._pth` to enable site-packages
5. Package everything into a distributable zip

### Development Workflow

1. **Test locally**:
   ```cmd
   python launcher_windows.py
   ```

2. **Build runtime pack**:
   ```powershell
   .\build_runtime_pack_windows.ps1
   ```

3. **Test packaged build**:
   - Extract `dist\LocalisRuntimePack.zip` to test folder
   - Run launcher from extracted folder
   - Verify bundled runtime is used

4. **Distribute**:
   - Upload `LocalisRuntimePack.zip` for end users
   - Include setup instructions

### Optional: PyInstaller Packaging

For a standalone executable (not required, but optional):

```bash
pip install pyinstaller
pyinstaller --onedir --name LocalMind --console launcher_windows.py
```

Then manually add `runtime\` folder to `dist\LocalMind\` before distribution.

---

## Test Checklist

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
   - Console shows "Updating repository..."
   - Shows "git fetch", "git checkout", "git pull"
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

### Test 5: Environment Variable Override

1. Set in `localis_runtime_config.json`: `"port": 8000`
2. Set environment variable: `set LOCALIS_PORT=9000`
3. Run launcher
4. **Expected**:
   - Server runs on port 9000 (env var overrides config)

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

### Test 8: Development Reload Mode

1. Set `LOCALIS_DEV_RELOAD=1`
2. Run launcher
3. **Expected**:
   - Console shows "Development mode: --reload enabled"
   - Server watches for file changes

---

## Support

For issues:
1. Check console output for error messages
2. Review logs in `%LOCALAPPDATA%\Localis\logs\`
3. Verify `localis_runtime_config.json` is valid JSON
4. Ensure complete runtime pack extraction
5. Try fresh install (delete `%LOCALAPPDATA%\Localis` and re-run)
