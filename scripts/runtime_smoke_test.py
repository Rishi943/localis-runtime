#!/usr/bin/env python3
"""
Localis Runtime Smoke Test

Tests that the embedded Python runtime has all critical packages installed
and can import them successfully. Used by verify_runtime_pack.ps1 and for
manual verification during development.

Exit codes:
  0 = All imports successful
  1 = Import failure or other error
"""

import sys


def main():
    """Run smoke test on the Python runtime."""
    print("=" * 70)
    print("Localis Runtime Smoke Test")
    print("=" * 70)
    print()

    # Print Python version info
    print(f"Python version: {sys.version}")
    print(f"Executable: {sys.executable}")
    print()

    # Critical packages to test
    packages = [
        ("llama_cpp", "llama-cpp-python"),
        ("fastapi", "FastAPI"),
        ("uvicorn", "Uvicorn"),
    ]

    print("Testing critical package imports...")
    print()

    failed = []

    for module_name, package_name in packages:
        try:
            __import__(module_name)
            print(f"  [OK] {package_name}")
        except ImportError as e:
            print(f"  [FAIL] {package_name}")
            print(f"         Error: {e}")
            failed.append(package_name)
        except Exception as e:
            print(f"  [ERROR] {package_name}")
            print(f"          Unexpected error: {e}")
            failed.append(package_name)

    print()
    print("=" * 70)

    if failed:
        print("SMOKE_TEST_FAILED")
        print()
        print(f"Failed to import {len(failed)} package(s): {', '.join(failed)}")
        print()
        print("Troubleshooting:")
        print("  1. Verify the runtime pack was built successfully")
        print("  2. Check that python311._pth includes 'Lib\\site-packages'")
        print("  3. Ensure all dependencies were installed during build")
        print()
        return 1
    else:
        print("SMOKE_TEST_OK")
        print()
        print("All critical packages imported successfully!")
        print("Runtime is ready for use.")
        print()
        return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nUnexpected error during smoke test: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
