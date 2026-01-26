#!/usr/bin/env python3
"""
Windows Bootstrap Launcher for LocalMind
Handles installation, git cloning/updating, and server startup using bundled runtime.

SELF-TEST CHECKLIST (validate on Windows):
□ Test 1: Fresh install with config file
  - Delete %LOCALAPPDATA%\Localis
  - Place localis_runtime_config.json next to launcher with valid repo_url
  - Run launcher → should clone repo and start server

□ Test 2: Bundled Python runtime
  - Verify launcher uses runtime\python\python.exe (not system Python)
  - Check console: "Using bundled Python at: ..."

□ Test 3: Bundled Git runtime
  - Remove git from PATH
  - Ensure runtime\git\bin\git.exe exists
  - Run launcher → should use bundled git

□ Test 4: Repository update (git pull)
  - Run launcher twice in a row
  - Second run should show "Updating repository..." and git pull

□ Test 5: Config file search order
  - Place different configs at launcher dir vs %LOCALAPPDATA%\Localis
  - Launcher dir should take precedence

□ Test 6: Environment variable overrides
  - Set LOCALIS_APP_REPO_URL env var
  - Should override config file repo_url

□ Test 7: Missing runtime payload
  - Remove runtime\python\python.exe
  - Should show clear error about missing runtime

□ Test 8: Dev reload mode
  - Set LOCALIS_DEV_RELOAD=1
  - Server should start with --reload flag
"""

import os
import sys
import platform
import logging
import subprocess
import time
import webbrowser
import json
from pathlib import Path


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def check_windows():
    """Verify running on Windows, exit gracefully if not."""
    if platform.system() != 'Windows':
        print("=" * 60)
        print("ERROR: This launcher is designed for Windows only.")
        print(f"Detected OS: {platform.system()}")
        print("=" * 60)
        print("\nFor other operating systems, please run the application directly:")
        print("  uvicorn app.main:app --host 0.0.0.0 --port 8000")
        print("=" * 60)
        sys.exit(1)


def get_bundle_root():
    """Get the directory containing this launcher executable/script."""
    if getattr(sys, 'frozen', False):
        # Running as PyInstaller bundle
        bundle_root = Path(sys.executable).parent
    else:
        # Running as script
        bundle_root = Path(__file__).parent

    logger.info(f"Bundle root: {bundle_root}")
    return bundle_root


def load_config(bundle_root):
    """
    Load configuration from JSON file.
    Search order:
    1. Same directory as launcher (bundle_root)
    2. %LOCALAPPDATA%\Localis\localis_runtime_config.json

    Returns dict with config values, empty dict if no config found.
    """
    config = {}

    # Search locations
    config_paths = [
        bundle_root / 'localis_runtime_config.json',
    ]

    # Add %LOCALAPPDATA%\Localis location if available
    local_app_data = os.environ.get('LOCALAPPDATA')
    if local_app_data:
        config_paths.append(Path(local_app_data) / 'Localis' / 'localis_runtime_config.json')

    # Try each location
    for config_path in config_paths:
        if config_path.exists():
            try:
                with open(config_path, 'r') as f:
                    config = json.load(f)
                logger.info(f"Loaded config from: {config_path}")
                return config
            except Exception as e:
                logger.warning(f"Failed to load config from {config_path}: {e}")

    logger.info("No config file found, will use environment variables")
    return config


def get_install_root(config):
    """Determine installation root directory."""
    # Priority: env var > config > default
    override = os.environ.get('LOCALIS_INSTALL_ROOT')
    if override:
        install_root = Path(override)
        logger.info(f"Using install root from LOCALIS_INSTALL_ROOT env: {install_root}")
    elif 'install_root' in config:
        install_root = Path(config['install_root'])
        logger.info(f"Using install root from config: {install_root}")
    else:
        # Default: %LOCALAPPDATA%\Localis
        local_app_data = os.environ.get('LOCALAPPDATA')
        if not local_app_data:
            logger.error("LOCALAPPDATA environment variable not found")
            sys.exit(1)
        install_root = Path(local_app_data) / 'Localis'
        logger.info(f"Using default install root: {install_root}")

    return install_root


def ensure_directories(install_root):
    """Create necessary subdirectories if they don't exist."""
    subdirs = ['app', 'models', 'data', 'runtime', 'logs']

    for subdir in subdirs:
        dir_path = install_root / subdir
        dir_path.mkdir(parents=True, exist_ok=True)
        logger.info(f"Ensured directory exists: {dir_path}")


def find_bundled_python(install_root, bundle_root):
    """
    Locate bundled Python runtime.
    Search order:
    1. <install_root>\runtime\python\python.exe
    2. <bundle_root>\runtime\python\python.exe

    Returns path to python.exe or None if not found.
    """
    search_paths = [
        install_root / 'runtime' / 'python' / 'python.exe',
        bundle_root / 'runtime' / 'python' / 'python.exe',
    ]

    for python_path in search_paths:
        if python_path.exists():
            logger.info(f"Using bundled Python at: {python_path}")
            return str(python_path)

    return None


def find_git_executable(install_root, bundle_root):
    """
    Locate git executable.
    Search order:
    1. <install_root>\runtime\git\bin\git.exe
    2. <bundle_root>\runtime\git\bin\git.exe
    3. git in PATH

    Returns path to git.exe or None if not found.
    """
    search_paths = [
        install_root / 'runtime' / 'git' / 'bin' / 'git.exe',
        bundle_root / 'runtime' / 'git' / 'bin' / 'git.exe',
    ]

    # Try bundled git first
    for git_path in search_paths:
        if git_path.exists():
            logger.info(f"Using bundled git at: {git_path}")
            return str(git_path)

    # Try git from PATH
    try:
        result = subprocess.run(
            ['git', '--version'],
            capture_output=True,
            text=True,
            check=True
        )
        logger.info(f"Found git in PATH: {result.stdout.strip()}")
        return 'git'
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    return None


def get_repo_config(config):
    """Get repository URL and branch from env vars or config."""
    # Priority: env vars > config file
    repo_url = os.environ.get('LOCALIS_APP_REPO_URL')
    if repo_url:
        logger.info("Using repo URL from LOCALIS_APP_REPO_URL env var")
    elif 'app_repo_url' in config:
        repo_url = config['app_repo_url']
        logger.info("Using repo URL from config file")
    else:
        logger.error("Repository URL not provided")
        print("\n" + "=" * 60)
        print("ERROR: Missing repository URL")
        print("=" * 60)
        print("\nPlease provide the repository URL either:")
        print("  1. In localis_runtime_config.json:")
        print('     {"app_repo_url": "https://github.com/user/localis.git"}')
        print("\n  2. Via environment variable:")
        print("     set LOCALIS_APP_REPO_URL=https://github.com/user/localis.git")
        print("=" * 60)
        sys.exit(1)

    branch = os.environ.get('LOCALIS_APP_BRANCH')
    if branch:
        logger.info("Using branch from LOCALIS_APP_BRANCH env var")
    elif 'app_branch' in config:
        branch = config['app_branch']
        logger.info("Using branch from config file")
    else:
        branch = 'release'
        logger.info("Using default branch: release")

    logger.info(f"Repository URL: {repo_url}")
    logger.info(f"Branch: {branch}")

    return repo_url, branch


def update_repository(git_exe, repo_url, branch, app_dir):
    """
    Update repository if it exists, otherwise clone it.
    If .git exists: fetch, checkout branch, pull
    Otherwise: clone
    """
    git_dir = app_dir / '.git'

    if git_dir.exists():
        logger.info(f"Repository exists at: {app_dir}")
        logger.info("Updating repository...")

        try:
            # Fetch updates
            logger.info("Running: git fetch --prune")
            subprocess.run(
                [git_exe, 'fetch', '--prune'],
                cwd=str(app_dir),
                check=True,
                capture_output=True,
                text=True
            )

            # Checkout branch
            logger.info(f"Running: git checkout {branch}")
            subprocess.run(
                [git_exe, 'checkout', branch],
                cwd=str(app_dir),
                check=True,
                capture_output=True,
                text=True
            )

            # Pull changes
            logger.info("Running: git pull --ff-only")
            result = subprocess.run(
                [git_exe, 'pull', '--ff-only'],
                cwd=str(app_dir),
                check=True,
                capture_output=True,
                text=True
            )
            logger.info("Repository updated successfully")
            if result.stdout:
                logger.info(f"Git output: {result.stdout.strip()}")

        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to update repository: {e}")
            logger.warning(f"Git stderr: {e.stderr}")
            logger.warning("Continuing with existing repository state...")
    else:
        logger.info(f"Cloning repository into: {app_dir}")
        logger.info("This may take a few minutes...")

        try:
            # Clone with specific branch
            subprocess.run(
                [git_exe, 'clone', '-b', branch, repo_url, str(app_dir)],
                check=True,
                capture_output=True,
                text=True
            )
            logger.info("Repository cloned successfully")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to clone repository: {e}")
            logger.error(f"Git stderr: {e.stderr}")
            print("\n" + "=" * 60)
            print("ERROR: Failed to clone repository")
            print("=" * 60)
            print(f"\nCommand: {' '.join(e.cmd)}")
            print(f"Error: {e.stderr}")
            print("\nPossible issues:")
            print("  - Invalid repository URL")
            print("  - Network connectivity problems")
            print("  - Authentication required (try HTTPS URL with token)")
            print("=" * 60)
            sys.exit(1)


def get_server_config(config):
    """Get server host and port configuration."""
    # Priority: env vars > config file > defaults
    host = os.environ.get('LOCALIS_HOST')
    if not host:
        host = config.get('host', '127.0.0.1')

    port = os.environ.get('LOCALIS_PORT')
    if not port:
        port = str(config.get('port', 8000))

    logger.info(f"Server will run on: {host}:{port}")

    return host, port


def launch_server(python_exe, install_root, app_dir, host, port):
    """Launch the uvicorn server with proper environment variables."""
    # Prepare environment variables for the child process
    env = os.environ.copy()
    env['MODEL_PATH'] = str(install_root / 'models')
    env['LOCALIS_DATA_DIR'] = str(install_root / 'data')

    logger.info(f"Setting MODEL_PATH={env['MODEL_PATH']}")
    logger.info(f"Setting LOCALIS_DATA_DIR={env['LOCALIS_DATA_DIR']}")

    # Build uvicorn command
    cmd = [
        python_exe,  # Use bundled Python
        '-m', 'uvicorn',
        'app.main:app',
        '--host', host,
        '--port', port,
    ]

    # Only enable reload in dev mode
    dev_reload = os.environ.get('LOCALIS_DEV_RELOAD')
    if dev_reload == '1':
        cmd.append('--reload')
        logger.info("Development mode: --reload enabled")

    logger.info(f"Starting server: {' '.join(cmd)}")
    logger.info(f"Working directory: {app_dir}")

    try:
        # Launch server as subprocess
        process = subprocess.Popen(
            cmd,
            cwd=str(app_dir),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        return process
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        print("\n" + "=" * 60)
        print("ERROR: Failed to start server")
        print("=" * 60)
        print(f"\nError: {e}")
        print("\nPossible issues:")
        print("  - Bundled Python runtime is incomplete")
        print("  - Required dependencies not installed in runtime")
        print("  - Port already in use (try different port)")
        print("=" * 60)
        sys.exit(1)


def open_browser(url, delay=3):
    """Open browser to the application URL after a short delay."""
    logger.info(f"Will open browser to {url} in {delay} seconds...")
    time.sleep(delay)

    try:
        webbrowser.open(url)
        logger.info(f"Browser opened to: {url}")
    except Exception as e:
        logger.warning(f"Could not open browser automatically: {e}")
        logger.info(f"Please open your browser manually to: {url}")


def stream_output(process):
    """Stream server output to console."""
    try:
        for line in process.stdout:
            print(line, end='')
    except KeyboardInterrupt:
        logger.info("\nShutting down server...")
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            logger.warning("Server did not terminate gracefully, forcing...")
            process.kill()
        logger.info("Server stopped")


def main():
    """Main launcher entry point."""
    logger.info("=" * 60)
    logger.info("LocalMind Windows Launcher")
    logger.info("=" * 60)

    # Step 1: Check OS
    check_windows()

    # Step 2: Get bundle root
    bundle_root = get_bundle_root()

    # Step 3: Load configuration
    config = load_config(bundle_root)

    # Step 4: Get install root
    install_root = get_install_root(config)

    # Step 5: Ensure directories
    ensure_directories(install_root)

    # Step 6: Find bundled Python
    python_exe = find_bundled_python(install_root, bundle_root)
    if not python_exe:
        logger.error("Bundled Python runtime not found")
        print("\n" + "=" * 60)
        print("ERROR: Runtime payload missing")
        print("=" * 60)
        print("\nThe bundled Python runtime is required but not found.")
        print("\nExpected locations:")
        print(f"  1. {install_root}\\runtime\\python\\python.exe")
        print(f"  2. {bundle_root}\\runtime\\python\\python.exe")
        print("\nPlease ensure you have the complete runtime pack.")
        print("Contact support or re-download the distribution.")
        print("=" * 60)
        sys.exit(1)

    # Step 7: Find git
    git_exe = find_git_executable(install_root, bundle_root)
    if not git_exe:
        logger.error("Git executable not found")
        print("\n" + "=" * 60)
        print("ERROR: Git not found")
        print("=" * 60)
        print("\nGit is required to download the application.")
        print("\nExpected locations:")
        print(f"  1. {install_root}\\runtime\\git\\bin\\git.exe")
        print(f"  2. {bundle_root}\\runtime\\git\\bin\\git.exe")
        print("  3. git in system PATH")
        print("\nPlease ensure you have the complete runtime pack,")
        print("or install Git from: https://git-scm.com/download/win")
        print("=" * 60)
        sys.exit(1)

    # Step 8: Get repo configuration
    repo_url, branch = get_repo_config(config)

    # Step 9: Update or clone repository
    app_dir = install_root / 'app'
    update_repository(git_exe, repo_url, branch, app_dir)

    # Step 10: Get server configuration
    host, port = get_server_config(config)
    server_url = f"http://{host}:{port}"

    # Step 11: Launch server
    logger.info("=" * 60)
    logger.info("Launching LocalMind server...")
    logger.info("=" * 60)
    process = launch_server(python_exe, install_root, app_dir, host, port)

    # Step 12: Open browser
    open_browser(server_url)

    # Step 13: Stream output
    logger.info("\nServer is running. Press Ctrl+C to stop.")
    logger.info("=" * 60)
    stream_output(process)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("\nLauncher interrupted by user")
        sys.exit(0)
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        sys.exit(1)
