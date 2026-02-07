#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ZipPath = ".\dist\LocalisRuntimePack.zip",
    [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

function Write-Section($title) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Pass($msg) { Write-Host "[PASS] $msg" -ForegroundColor Green }
function Fail($msg, $detail = $null) {
    Write-Host "[FAIL] $msg" -ForegroundColor Red
    if ($detail) { Write-Host "       $detail" -ForegroundColor Yellow }
    $script:AllPassed = $false
    # PowerShell 5.1 compatible: replace ternary operator with if/else
    if (-not $script:FirstFailure) {
        if ($null -ne $detail -and $detail -ne "") {
            $script:FirstFailure = $detail
        } else {
            $script:FirstFailure = $msg
        }
    }
}

function Assert-ZipNoAbsoluteEntries($zipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $bad = $z.Entries | Where-Object {
            $_.FullName -match '^[A-Za-z]:|^[A-Za-z][\\/]' -or
            $_.FullName.StartsWith('\') -or $_.FullName.StartsWith('/')
        } | Select-Object -First 1
        if ($bad) {
            Fail "zip contains no absolute-like entries" ("Bad entry example: " + $bad.FullName)
            return $false
        } else {
            Pass "zip contains no absolute-like entries"
            return $true
        }
    } finally {
        $z.Dispose()
    }
}

function Extract-ZipDotNet($zipPath, $destDir) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $destDir) {
        Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destDir)
}

function Test-FileExists($root, $relativePath) {
    $full = Join-Path $root $relativePath
    if (Test-Path $full) {
        Pass "$relativePath exists"
        return $true
    } else {
        Fail "$relativePath exists" ("File not found: " + $full)
        return $false
    }
}

function Check-NoUtf8Bom($filePath, $label) {
    if (-not (Test-Path $filePath)) {
        Fail $label ("File not found: " + $filePath)
        return $false
    }
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $hasBOM = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBOM) {
        Fail $label "BOM detected (EF BB BF)"
        return $false
    } else {
        Pass $label
        return $true
    }
}

function Run-Python($pythonExe, $code, $label) {
    try {
        $out = & $pythonExe -c $code 2>&1
        if ($LASTEXITCODE -eq 0) {
            Pass $label
            return @{ ok = $true; out = $out }
        } else {
            Fail $label ("Output: " + $out)
            return @{ ok = $false; out = $out }
        }
    } catch {
        Fail $label ("Failed: " + $_.Exception.Message)
        return @{ ok = $false; out = $_.Exception.Message }
    }
}

$script:AllPassed = $true
$script:FirstFailure = $null

Write-Section "Localis Runtime Pack Verification"

if (-not (Test-Path $ZipPath)) {
    Fail "runtime pack zip exists" ("Zip not found: " + $ZipPath)
    exit 1
} else {
    Pass "runtime pack zip exists"
}

$zipSizeMB = [math]::Round(((Get-Item $ZipPath).Length / 1MB), 2)
Write-Host "Zip: $ZipPath" -ForegroundColor Gray
Write-Host "Size: $zipSizeMB MB" -ForegroundColor Gray

# temp dir
$tempDir = Join-Path $env:TEMP ("localis_verify_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Write-Host ""
Write-Host "Extracting to: $tempDir" -ForegroundColor Gray

# Structural check + extract
if (-not (Assert-ZipNoAbsoluteEntries $ZipPath)) {
    Write-Host ""
    Write-Host "Temp directory preserved for inspection:" -ForegroundColor Yellow
    Write-Host "  $tempDir" -ForegroundColor Cyan
    exit 1
}

try {
    Extract-ZipDotNet -zipPath $ZipPath -destDir $tempDir
} catch {
    Fail "zip extraction succeeds" $_.Exception.Message
    Write-Host ""
    Write-Host "Temp directory preserved for inspection:" -ForegroundColor Yellow
    Write-Host "  $tempDir" -ForegroundColor Cyan
    exit 1
}

Write-Host ""
Write-Host "Running verification tests..." -ForegroundColor Cyan
Write-Host ""

# Required files
$pythonOk   = Test-FileExists $tempDir "runtime\python\python.exe"
$gitOk      = Test-FileExists $tempDir "runtime\git\bin\git.exe"   # canonical launcher path
$launcherOk = Test-FileExists $tempDir "launcher_windows.py"
$configOk   = Test-FileExists $tempDir "localis_runtime_config.json"

# _pth BOM check
$pthPath = Join-Path $tempDir "runtime\python\python311._pth"
Check-NoUtf8Bom -filePath $pthPath -label "python311._pth has NO UTF-8 BOM" | Out-Null

# Python checks
if ($pythonOk) {
    $pythonExe = Join-Path $tempDir "runtime\python\python.exe"

    # Version check
    try {
        $ver = & $pythonExe --version 2>&1
        if ($ver -match "Python 3\.11\.") { Pass "Python version is 3.11.x" }
        else { Fail "Python version is 3.11.x" ("Got: " + $ver) }
    } catch {
        Fail "Python version is 3.11.x" $_.Exception.Message
    }

    # Git sanity
    if ($gitOk) {
        $gitExe = Join-Path $tempDir "runtime\git\bin\git.exe"
        try {
            $gv = & $gitExe --version 2>&1
            if ($LASTEXITCODE -eq 0) { Pass "git --version runs" }
            else { Fail "git --version runs" ("Output: " + $gv) }
        } catch {
            Fail "git --version runs" $_.Exception.Message
        }
    }

    # Imports
    Run-Python $pythonExe "import fastapi; print('ok')"  "import fastapi"  | Out-Null
    Run-Python $pythonExe "import uvicorn; print('ok')"  "import uvicorn"  | Out-Null

    # llama_cpp diagnostics
    $llamaDll = Join-Path $tempDir "runtime\python\Lib\site-packages\llama_cpp\lib\llama.dll"
    if (Test-Path $llamaDll) { Pass "llama.dll present" }
    else { Fail "llama.dll present" ("Expected: " + $llamaDll) }

    $r = Run-Python $pythonExe "import llama_cpp; print('ok')" "import llama_cpp"
    if (-not $r.ok -and (Test-Path $llamaDll)) {
        Write-Host "       Hint: llama.dll exists but failed to load. This is commonly missing VC++ runtime (2015-2022 x64) or another dependent DLL." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

if ($script:AllPassed) {
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host ""
    if (-not $KeepTemp) {
        try { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    } else {
        Write-Host "Temp directory preserved:" -ForegroundColor Yellow
        Write-Host "  $tempDir" -ForegroundColor Cyan
    }
    exit 0
} else {
    Write-Host "  VERIFICATION FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "First error: $script:FirstFailure" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Temp directory preserved for inspection:" -ForegroundColor Yellow
    Write-Host "  $tempDir" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
