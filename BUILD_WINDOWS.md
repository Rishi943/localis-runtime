# Building and Running LocalMind on Windows

This document covers running and packaging the LocalMind Windows launcher.

## Prerequisites

### Required

- **Python 3.8 or higher** (Python 3.10+ recommended)
  - Download from [python.org](https://www.python.org/downloads/)
  - Ensure "Add Python to PATH" is checked during installation
  - Verify: `python --version`

- **pip** (included with Python)
  - Verify: `pip --version`

### Optional

- **Git** (for cloning the application repository)
  - Download from [git-scm.com](https://git-scm.com/download/win)
  - Verify: `git --version`
  - **Alternative**: Can use bundled portable Git (see Installation Structure below)

### Python Dependencies

For script usage:
```bash
pip install uvicorn
```

For packaging:
```bash
pip install pyinstaller
```

## Installation Structure

LocalMind installs to: **`%LOCALAPPDATA%\Localis`**

Typical path: `C:\Users\<YourUsername>\AppData\Local\Localis`

### Directory Layout

```
%LOCALAPPDATA%\Localis\
├── app\              # Git repository clone (application code)
├── models\           # GGUF model files (user-managed)
├── data\             # SQLite database, user data
├── runtime\          # Optional bundled dependencies
│   └── git\          # Optional portable Git
│       └── bin\
│           └── git.exe
└── logs\             # Application logs
```

## Running as a Script (Development/Testing)

### 1. Set Required Environment Variables

The launcher requires the repository URL. Open Command Prompt or PowerShell:

```cmd
REM Set repository URL (required)
set LOCALIS_APP_REPO_URL=https://github.com/yourusername/localis.git

REM Set branch (optional, defaults to 'release')
set LOCALIS_APP_BRANCH=main

REM Run the launcher
python launcher_windows.py
```

Or in PowerShell:

```powershell
# Set repository URL (required)
$env:LOCALIS_APP_REPO_URL = "https://github.com/yourusername/localis.git"

# Set branch (optional, defaults to 'release')
$env:LOCALIS_APP_BRANCH = "main"

# Run the launcher
python launcher_windows.py
```

### 2. Optional Configuration

Override default installation location:
```cmd
set LOCALIS_INSTALL_ROOT=D:\MyApps\Localis
```

Override server host/port:
```cmd
set LOCALIS_HOST=0.0.0.0
set LOCALIS_PORT=8080
```

### 3. First Run Behavior

On first run, the launcher will:
1. Create directory structure in `%LOCALAPPDATA%\Localis`
2. Clone the repository to `app\` subdirectory
3. Launch the uvicorn server
4. Open your default browser to `http://127.0.0.1:8000`

### 4. Stopping the Server

Press `Ctrl+C` in the terminal to stop the server gracefully.

## Packaging with PyInstaller

### Recommended Approach (v1): One-Directory Build

This creates a folder with the executable and dependencies.

#### 1. Install PyInstaller

```bash
pip install pyinstaller
```

#### 2. Create the Package

```bash
pyinstaller --onedir --name LocalMind --console launcher_windows.py
```

Options explained:
- `--onedir`: Creates a folder (easier to bundle runtime dependencies)
- `--name LocalMind`: Output name
- `--console`: Shows console window (helpful for debugging)

#### 3. Output Location

The executable will be in:
```
dist\LocalMind\
├── LocalMind.exe       # Main executable
├── _internal\          # Python runtime and dependencies
└── ...
```

#### 4. Distribution

Distribute the entire `dist\LocalMind\` folder. Users run `LocalMind.exe`.

### Advanced: One-File Build (v2)

For a single executable (slower startup):

```bash
pyinstaller --onefile --name LocalMind --console launcher_windows.py
```

Output: `dist\LocalMind.exe`

### Bundling Portable Git (Optional)

If you want to bundle Git with your distribution:

1. Download PortableGit from [git-scm.com](https://git-scm.com/download/win)
2. Extract to `dist\LocalMind\runtime\git\`
3. Ensure `git.exe` is at `dist\LocalMind\runtime\git\bin\git.exe`

The launcher will automatically detect and use bundled Git.

## Environment Variable Configuration

### For Script Usage

Create a batch file (e.g., `launch_localis.bat`):

```batch
@echo off
set LOCALIS_APP_REPO_URL=https://github.com/yourusername/localis.git
set LOCALIS_APP_BRANCH=release
python launcher_windows.py
pause
```

### For Packaged Executable

Create a batch file (e.g., `LocalMind.bat`) next to the executable:

```batch
@echo off
set LOCALIS_APP_REPO_URL=https://github.com/yourusername/localis.git
set LOCALIS_APP_BRANCH=release
LocalMind.exe
pause
```

Or set system-wide environment variables:
1. Open System Properties → Advanced → Environment Variables
2. Add `LOCALIS_APP_REPO_URL` under User variables
3. Optionally add `LOCALIS_APP_BRANCH`

## Test Checklist

### Test 1: First Install

**Goal**: Verify clean installation and initial clone.

1. Delete `%LOCALAPPDATA%\Localis` if it exists
2. Set `LOCALIS_APP_REPO_URL` environment variable
3. Run launcher (script or packaged)
4. **Expected**:
   - Directories created in `%LOCALAPPDATA%\Localis`
   - Repository cloned to `app\`
   - Server starts successfully
   - Browser opens to application
   - Console shows "Repository cloned successfully"

### Test 2: Rerun (Repository Already Exists)

**Goal**: Verify launcher skips cloning on subsequent runs.

1. Close the server (Ctrl+C)
2. Run launcher again
3. **Expected**:
   - No cloning occurs
   - Console shows "Repository already cloned at: ..."
   - Server starts immediately
   - Browser opens again

### Test 3: Update via Git Pull

**Goal**: Verify application updates work.

1. Stop the server
2. Manually update the repository:
   ```cmd
   cd %LOCALAPPDATA%\Localis\app
   git pull origin release
   ```
3. Run launcher again
4. **Expected**:
   - Updated code is used
   - Server runs with latest changes

**Future Enhancement**: Add auto-update support to launcher.

### Test 4: Persistence of Models and Data

**Goal**: Verify user data persists across runs.

1. Run the application
2. Place a GGUF model file in `%LOCALAPPDATA%\Localis\models\`
3. Complete the tutorial (creates `chat_history.db` in `data\`)
4. Have a conversation (adds messages to database)
5. Stop the server
6. Run launcher again
7. **Expected**:
   - Model still present in `models\`
   - Database still present in `data\`
   - Chat history loads correctly
   - Tutorial completion status preserved

### Test 5: Custom Install Root

**Goal**: Verify custom installation directory works.

1. Set `LOCALIS_INSTALL_ROOT=C:\CustomLocalis`
2. Run launcher
3. **Expected**:
   - Installation occurs in `C:\CustomLocalis`
   - All subdirectories created there
   - Application runs normally

### Test 6: Git Not in PATH (Bundled Git)

**Goal**: Verify bundled Git fallback works.

1. Temporarily rename/remove Git from PATH
2. Place portable Git at `%LOCALAPPDATA%\Localis\runtime\git\bin\git.exe`
3. Run launcher with clean install
4. **Expected**:
   - Console shows "Found bundled git at: ..."
   - Repository clones successfully using bundled Git

### Test 7: Error Handling - Missing Repository URL

**Goal**: Verify clear error message when LOCALIS_APP_REPO_URL not set.

1. Unset `LOCALIS_APP_REPO_URL`
2. Run launcher
3. **Expected**:
   - Clear error message displayed
   - Instructions on how to set the variable
   - Launcher exits gracefully

### Test 8: Error Handling - No Git Available

**Goal**: Verify clear error when Git is unavailable.

1. Remove Git from PATH
2. Ensure no bundled Git at runtime location
3. Run launcher
4. **Expected**:
   - Clear error message about missing Git
   - Instructions to install Git or use bundled Git
   - Launcher exits gracefully

## Troubleshooting

### Issue: "LOCALIS_APP_REPO_URL environment variable is required"

**Solution**: Set the environment variable before running:
```cmd
set LOCALIS_APP_REPO_URL=https://github.com/yourusername/localis.git
```

### Issue: "Git executable not found"

**Solution**: Either:
1. Install Git and add to PATH: [git-scm.com](https://git-scm.com/download/win)
2. Place portable Git at `%LOCALAPPDATA%\Localis\runtime\git\bin\git.exe`

### Issue: "Failed to start server" / "uvicorn not found"

**Solution**: Install uvicorn in the repository:
```bash
cd %LOCALAPPDATA%\Localis\app
pip install -r requirements.txt
```

### Issue: Application runs but shows errors about missing models

**Solution**: Place GGUF model files in `%LOCALAPPDATA%\Localis\models\`

### Issue: Browser doesn't open automatically

**Solution**: Manually navigate to `http://127.0.0.1:8000` in your browser.

### Issue: Port already in use

**Solution**: Change the port:
```cmd
set LOCALIS_PORT=8001
```

## Advanced: Creating an Installer

For future versions, consider using:
- **Inno Setup**: Create a Windows installer (.exe)
- **WiX Toolset**: Create an MSI installer
- **NSIS**: Lightweight installer creator

These can:
- Create Start Menu shortcuts
- Set environment variables automatically
- Handle uninstallation
- Bundle all dependencies

## Version Control Best Practices

When packaging for distribution:

1. **Tag releases** in git:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

2. **Use the release branch** for stable builds:
   - Set `LOCALIS_APP_BRANCH=release` by default
   - Keep `main` or `develop` for development

3. **Test packaged executables** before distributing:
   - Run all tests from the checklist
   - Test on a clean Windows VM if possible

## Support

For issues or questions:
- Check logs in `%LOCALAPPDATA%\Localis\logs\`
- Review console output for error messages
- Ensure all prerequisites are met
