param(
    [switch]$DryRun,
    [switch]$AsObject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Platform detection
# -------------------------------------------------------------------
$IsWin = $IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6) -or (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue))

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
function Add-CandidatePath {
    param([Parameter(Mandatory)][System.Collections.IList]$List, [string]$Path)
    if (-not $Path) { return }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        if (-not $List.Contains($resolved)) { [void]$List.Add($resolved) }
    }
}

function Find-ArmGcc {
    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($IsWin) {
        # 1. STM32CubeCLT
        foreach ($clt in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeCLT_*" -ErrorAction SilentlyContinue) {
            Add-CandidatePath -List $candidates -Path (Join-Path $clt.FullName "GNU-tools-for-STM32\bin\arm-none-eabi-gcc.exe")
        }
        # 2. STM32CubeIDE
        foreach ($ide in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeIDE_*" -ErrorAction SilentlyContinue) {
            $pluginsDir = Join-Path $ide.FullName "STM32CubeIDE\plugins"
            if (-not (Test-Path $pluginsDir)) { continue }
            foreach ($plugin in Get-ChildItem $pluginsDir -Directory -Filter "com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32*" -ErrorAction SilentlyContinue) {
                Add-CandidatePath -List $candidates -Path (Join-Path $plugin.FullName "tools\bin\arm-none-eabi-gcc.exe")
            }
        }
        # 3. PATH
        foreach ($item in @(Get-Command "arm-none-eabi-gcc.exe" -ErrorAction SilentlyContinue)) {
            if ($item) { Add-CandidatePath -List $candidates -Path $item.Path }
        }
    } else {
        # Linux
        foreach ($clt in Get-ChildItem "/opt/st/stm32cubeclt" -Directory -ErrorAction SilentlyContinue) {
            Add-CandidatePath -List $candidates -Path (Join-Path $clt.FullName "GNU-tools-for-STM32/bin/arm-none-eabi-gcc")
        }
        foreach ($item in @(Get-Command "arm-none-eabi-gcc" -ErrorAction SilentlyContinue)) {
            if ($item) { Add-CandidatePath -List $candidates -Path $item.Path }
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    # Prefer CubeCLT over CubeIDE, then PATH
    return ($candidates | Sort-Object {
        $score = 0
        if ($_ -match "STM32CubeCLT") { $score += 10 }
        -$score
    } | Select-Object -First 1)
}

function Find-Make {
    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($IsWin) {
        # 1. STM32CubeCLT bundled make
        foreach ($clt in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeCLT_*" -ErrorAction SilentlyContinue) {
            foreach ($makeDir in Get-ChildItem $clt.FullName -Directory -Filter "make-*" -ErrorAction SilentlyContinue) {
                Add-CandidatePath -List $candidates -Path (Join-Path $makeDir.FullName "bin\make.exe")
            }
        }
        # 2. GnuWin32
        Add-CandidatePath -List $candidates -Path "C:\Program Files (x86)\GnuWin32\bin\make.exe"
        # 3. PATH
        foreach ($cmd in @("make.exe", "mingw32-make.exe")) {
            foreach ($item in @(Get-Command $cmd -ErrorAction SilentlyContinue)) {
                if ($item) { Add-CandidatePath -List $candidates -Path $item.Path }
            }
        }
    } else {
        foreach ($item in @(Get-Command "make" -ErrorAction SilentlyContinue)) {
            if ($item) { Add-CandidatePath -List $candidates -Path $item.Path }
        }
    }

    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object { if ($_ -match "GnuWin32|STM32CubeCLT") { 0 } else { 1 } })[0]
}

# -------------------------------------------------------------------
# Resolve
# -------------------------------------------------------------------
$armGccPath = Find-ArmGcc
$makePath = Find-Make

$armGccDir = if ($armGccPath) { Split-Path -Parent $armGccPath } else { "" }
$armGccExe = if ($armGccPath) { $armGccPath } else { "" }
$makeExe = if ($makePath) { $makePath } else { "" }

if ($AsObject) {
    return @{
        ARM_GCC_DIR = $armGccDir
        ARM_GCC_EXE = $armGccExe
        MAKE_EXE    = $makeExe
    }
}

Write-Host "ARM_GCC_DIR=$armGccDir"
Write-Host "ARM_GCC_EXE=$armGccExe"
Write-Host "MAKE_EXE=$makeExe"

if (-not $DryRun) {
    $missing = @()
    if (-not $armGccPath) {
        if ($IsWin) {
            $missing += "arm-none-eabi-gcc not found. Searched C:\ST\STM32CubeCLT_*, C:\ST\STM32CubeIDE_*, and PATH. Install STM32CubeCLT or STM32CubeIDE."
        } else {
            $missing += "arm-none-eabi-gcc not found. Searched /opt/st/stm32cubeclt/* and PATH. Install STM32CubeCLT."
        }
    }
    if (-not $makePath) {
        if ($IsWin) {
            $missing += "make not found. Searched STM32CubeCLT, GnuWin32, and PATH. Install GnuWin32 make or add make.exe to PATH."
        } else {
            $missing += "make not found on PATH."
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host ($missing -join "`n")
        exit 1
    }
}

exit 0
