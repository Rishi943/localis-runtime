# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec file for Localis Launcher

Builds a thin launcher executable that relies on the runtime/ folder being
installed alongside Localis.exe by the installer (not embedded in the exe).

Usage:
    pyinstaller LocalisLauncher.spec

Output:
    dist/Localis.exe

The installer should place:
    - Localis.exe at the install root
    - runtime/ folder alongside Localis.exe
    - localis_runtime_config.json alongside Localis.exe
"""

import os

# ============================================================================
# File Path Resolution and Validation
# ============================================================================
# Resolve all paths relative to the spec file directory to avoid CWD issues
# Note: SPECPATH is a PyInstaller built-in variable that contains the spec file's directory

spec_dir = SPECPATH  # PyInstaller built-in variable (same as os.path.dirname(os.path.abspath(spec_file)))

# Version info file (OPTIONAL)
ver_file = os.path.join(spec_dir, "file_version_info.txt")
ver_arg = ver_file if os.path.exists(ver_file) else None

# Main launcher script (REQUIRED)
launcher_script = os.path.join(spec_dir, "launcher_windows.py")
if not os.path.exists(launcher_script):
    raise RuntimeError(
        f"REQUIRED FILE MISSING: launcher_windows.py\n"
        f"Expected location: {launcher_script}\n"
        f"This is the main application script and must be present to build."
    )

# Icon file (OPTIONAL)
# If you want to add an icon, create 'icon.ico' in the same directory as this spec file
icon_file_name = "icon.ico"  # Change this if you want a different icon filename
icon_file = os.path.join(spec_dir, icon_file_name)
icon_arg = icon_file if os.path.exists(icon_file) else None

block_cipher = None

a = Analysis(
    [launcher_script],  # Using validated path
    pathex=[spec_dir],  # Include spec directory for imports
    binaries=[],
    datas=[],
    hiddenimports=[],
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
    exclude_binaries=True,
    name='Localis',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # Keep console visible since launcher logs to 'localis_launcher.log' in cwd, not install_root/logs/
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    version=ver_arg,  # Optional: uses file_version_info.txt if present, None otherwise
    icon=icon_arg,  # Optional: uses icon.ico if present, None otherwise
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Localis',
)

# ==============================================================================
# NOTES FOR INSTALLER PACKAGING
# ==============================================================================
#
# After building with PyInstaller:
#
# 1. The output is in dist/Localis/:
#    - Localis.exe (thin launcher, ~10-20 MB)
#    - Various Python runtime DLLs and dependencies
#
# 2. The installer (e.g., Inno Setup) should bundle:
#    - dist/Localis/* (all PyInstaller output)
#    - runtime/ folder (from LocalisRuntimePack.zip)
#    - localis_runtime_config.json
#
# 3. Installation layout:
#    C:\Program Files\Localis\
#    ├── Localis.exe
#    ├── python*.dll (PyInstaller dependencies)
#    ├── runtime\
#    │   ├── python\
#    │   │   └── python.exe (embedded Python 3.11.x)
#    │   └── git\
#    │       └── bin\git.exe
#    └── localis_runtime_config.json
#
# 4. User data will be stored at:
#    %LOCALAPPDATA%\Localis\
#    ├── app\       (cloned application repo)
#    ├── models\    (GGUF model files)
#    ├── data\      (SQLite database)
#    └── logs\      (application logs)
#
# ==============================================================================
# VERSION INFO (Optional)
# ==============================================================================
#
# To add version information to Localis.exe:
#
# Option 1: Use pyi-grab_version (Windows only):
#   pyi-grab_version SomeApp.exe
#   # Edit file_version_info.txt with your version info
#   # Uncomment the version= line above
#
# Option 2: Create file_version_info.txt manually:
#
# VSVersionInfo(
#   ffi=FixedFileInfo(
#     filevers=(1, 0, 0, 0),
#     prodvers=(1, 0, 0, 0),
#     mask=0x3f,
#     flags=0x0,
#     OS=0x40004,
#     fileType=0x1,
#     subtype=0x0,
#     date=(0, 0)
#   ),
#   kids=[
#     StringFileInfo(
#       [
#       StringTable(
#         u'040904B0',
#         [StringStruct(u'CompanyName', u'YourCompany'),
#         StringStruct(u'FileDescription', u'Localis Launcher'),
#         StringStruct(u'FileVersion', u'1.0.0.0'),
#         StringStruct(u'InternalName', u'Localis'),
#         StringStruct(u'LegalCopyright', u'Copyright (c) 2025'),
#         StringStruct(u'OriginalFilename', u'Localis.exe'),
#         StringStruct(u'ProductName', u'Localis'),
#         StringStruct(u'ProductVersion', u'1.0.0.0')])
#       ]),
#     VarFileInfo([VarStruct(u'Translation', [1033, 1200])])
#   ]
# )
#
# ==============================================================================
