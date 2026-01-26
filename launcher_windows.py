#!/usr/bin/env python3
"""
Windows Bootstrap Launcher for LocalMind
Handles installation, git cloning, and server startup.
"""

import os
import sys
import platform
import logging
import subprocess
import time
import webbrowser
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
        print("  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000")
        print("=" * 60)
        sys.exit(1)


def get_install_root():
    """Determine installation root directory."""
    # Allow override via environment variable
    override = os.environ.get('LOCALIS_INSTALL_ROOT')
    if override:
        install_root = Path(override)
        logger.info(f"Using custom install root from LOCALIS_INSTALL_ROOT: {install_root}")
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


def find_git_executable(install_root):
    """
    Locate git executable.
    First checks PATH, then looks for bundled git.
    Returns path to git.exe or None if not found.
    """
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
        logger.info("Git not found in PATH, checking for bundled git...")

    # Try bundled git
    bundled_git = install_root / 'runtime' / 'git' / 'bin' / 'git.exe'
    if bundled_git.exists():
        logger.info(f"Found bundled git at: {bundled_git}")
        return str(bundled_git)

    return None


def get_repo_config():
    """Get repository URL and branch from environment."""
    repo_url = os.environ.get('LOCALIS_APP_REPO_URL')
    if not repo_url:
        logger.error("LOCALIS_APP_REPO_URL environment variable is required")
        print("\n" + "=" * 60)
        print("ERROR: Missing required environment variable")
        print("=" * 60)
        print("\nPlease set LOCALIS_APP_REPO_URL to the git repository URL.")
        print("Example:")
        print("  set LOCALIS_APP_REPO_URL=https://github.com/user/localis.git")
        print("=" * 60)
        sys.exit(1)

    branch = os.environ.get('LOCALIS_APP_BRANCH', 'release')

    logger.info(f"Repository URL: {repo_url}")
    logger.info(f"Branch: {branch}")

    return repo_url, branch


def clone_repository(git_exe, repo_url, branch, app_dir):
    """Clone the repository if not already cloned."""
    git_dir = app_dir / '.git'

    if git_dir.exists():
        logger.info(f"Repository already cloned at: {app_dir}")
        return

    logger.info(f"Cloning repository into: {app_dir}")
    logger.info(f"This may take a few minutes...")

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
        print("=" * 60)
        sys.exit(1)


def get_server_config():
    """Get server host and port configuration."""
    host = os.environ.get('LOCALIS_HOST', '127.0.0.1')
    port = os.environ.get('LOCALIS_PORT', '8000')

    logger.info(f"Server will run on: {host}:{port}")

    return host, port


def launch_server(install_root, app_dir, host, port):
    """Launch the uvicorn server with proper environment variables."""
    # Prepare environment variables for the child process
    env = os.environ.copy()
    env['MODEL_PATH'] = str(install_root / 'models')
    env['LOCALIS_DATA_DIR'] = str(install_root / 'data')

    logger.info(f"Setting MODEL_PATH={env['MODEL_PATH']}")
    logger.info(f"Setting LOCALIS_DATA_DIR={env['LOCALIS_DATA_DIR']}")

    # Build uvicorn command
    cmd = [
        sys.executable,  # Use the same Python interpreter
        '-m', 'uvicorn',
        'app.main:app',
        '--host', host,
        '--port', port,
        '--reload'
    ]

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
        print("\nPlease ensure uvicorn is installed:")
        print("  pip install uvicorn")
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

    # Step 2: Get install root
    install_root = get_install_root()

    # Step 3: Ensure directories
    ensure_directories(install_root)

    # Step 4: Find git
    git_exe = find_git_executable(install_root)
    if not git_exe:
        logger.error("Git executable not found")
        print("\n" + "=" * 60)
        print("ERROR: Git not found")
        print("=" * 60)
        print("\nGit is required to download the application.")
        print("\nPlease either:")
        print("  1. Install Git and add it to your PATH")
        print("     Download from: https://git-scm.com/download/win")
        print(f"\n  2. Place portable Git at:")
        print(f"     {install_root}\\runtime\\git\\bin\\git.exe")
        print("=" * 60)
        sys.exit(1)

    # Step 5: Get repo configuration
    repo_url, branch = get_repo_config()

    # Step 6: Clone repository if needed
    app_dir = install_root / 'app'
    clone_repository(git_exe, repo_url, branch, app_dir)

    # Step 7: Get server configuration
    host, port = get_server_config()
    server_url = f"http://{host}:{port}"

    # Step 8: Launch server
    logger.info("=" * 60)
    logger.info("Launching LocalMind server...")
    logger.info("=" * 60)
    process = launch_server(install_root, app_dir, host, port)

    # Step 9: Open browser
    open_browser(server_url)

    # Step 10: Stream output
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
