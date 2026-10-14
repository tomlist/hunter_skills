param(
    [string]$Port = "COM18",
    [int]$Baud = 115200,
    [int]$SizeMB = 2,
    [string]$Layout,
    [switch]$DryRun,
    [switch]$Help,
    [string]$ProjectRoot
)

# Erase an STM32MP135 project's eMMC: writes a block of zeros over the boot image
# + GPT area through the ST eMMC ext-loader chain, so the ROM finds no valid image
# and falls back to serial boot. Prerequisites, why zeros instead of a real erase,
# and the coverage limits are in SKILL.md section 7.

if ($Help) {
    @"
erase_emmc.ps1 - erase an STM32MP135 project's eMMC (destructive)

Usage:
  pwsh -File erase_emmc.ps1 [-ProjectRoot <path>] [-Port COM<n>|usb1] [-Baud <baud>] [-SizeMB 2] [-Layout <tsv>] [-DryRun]

Parameters:
  -ProjectRoot <path>  Project root (default: the directory above this script)
  -Port <port>         COM<n> (default COM18) or usb1 for USB DFU
  -Baud <baud>         UART baud for the serial-boot handoff (default 115200)
  -SizeMB <n>          Size of each zeros block (default 2; the wiped area is
                       2 x this, i.e. 4 MiB by default)
  -Layout <tsv>        Use this flashlayout instead of <project>\erase_emmc.tsv
  -DryRun              Print what would happen, then exit
  -Help                Show this help

Needs the ST ext-loader binaries in <project>\flash\ and a board that is already
offering its bootloader (boot pins b000, or an empty/invalid eMMC).
"@
    exit 0
}

$ErrorActionPreference = "Stop"

$projectRoot = if ($ProjectRoot) { $ProjectRoot } else { Split-Path -Parent $PSScriptRoot }

if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
    throw "erase_emmc.ps1 is Windows-only (needs STM32_Programmer_CLI.exe)."
}

$prog = Get-Command "STM32_Programmer_CLI.exe" -ErrorAction SilentlyContinue
if (-not $prog -and -not $DryRun) {
    throw "STM32_Programmer_CLI.exe not found on PATH."
}
$cli = if ($DryRun) { "STM32_Programmer_CLI.exe" } else { $prog.Path }

# 1. The ST ext-loader chain must be in the project
$openbl = Join-Path $projectRoot "flash\External_Mem_Loader_A7.stm32"
$extLdr = Join-Path $projectRoot "flash\MMC_Ext_Loader.bin"
if (-not (Test-Path $openbl) -or -not (Test-Path $extLdr)) {
    throw "Missing ST eMMC ext-loader binaries in flash\. Copy both from the " +
    "STM32CubeMP13 package: " +
    "%USERPROFILE%\STM32Cube\Repository\STM32Cube_FW_MP13_*\Projects\" +
    "STM32MP13XX_CUSTOM_HW\External_Loader\Prebuild_Binaries\EMMC_Ext_Loader\"
}

if ($SizeMB -lt 1) { throw "-SizeMB must be at least 1." }

# 2. Layout: an existing project file wins over the template
$layoutFull = if ($Layout) {
    if ([System.IO.Path]::IsPathRooted($Layout)) { $Layout }
    else { Join-Path $projectRoot $Layout }
}
else { Join-Path $projectRoot "erase_emmc.tsv" }

$layoutExists = Test-Path $layoutFull
$zeros = Join-Path $projectRoot "erase_zeros.bin"

Write-Host "ERASE  : zeroing the eMMC boot image + GPT area (not a native erase)" -ForegroundColor Yellow
Write-Host "Layout : $layoutFull $(if ($layoutExists) { '(existing)' } else { "(will be generated, $SizeMB MiB x 2)" })"
Write-Host "Zeros  : $zeros ($SizeMB MiB)"
Write-Host "Port   : $Port"

if ($DryRun) { exit 0 }

# 3. Copy the layout template when the project has none, and generate the zeros
#    payload the layout references
if (-not $layoutExists) {
    $template = Join-Path $PSScriptRoot "erase_emmc.tsv"
    if (-not (Test-Path $template)) {
        throw "Layout template not found: $template (it ships next to this script)."
    }
    $tsv = Get-Content -LiteralPath $template -Raw
    # Entry 0x5 goes just past the first block, so the two writes do not overlap.
    # Named group + ${pre}: "$10x..." would be read as group 10.
    $pattern = '(?m)^(?<pre>P\s+0x5\s+\S+\s+\S+\s+mmc1\s+)0x[0-9A-Fa-f]+'
    if ($tsv -match $pattern) {
        $lba2 = '0x{0:X7}' -f ($SizeMB * 2048)
        $tsv = $tsv -replace $pattern, ('${pre}' + $lba2)
    }
    else {
        Write-Warning "Entry 0x5 in the template does not match the expected shape - its offset was left as is."
    }
    [System.IO.File]::WriteAllText($layoutFull, $tsv,
        [System.Text.ASCIIEncoding]::new())
}

[System.IO.File]::WriteAllBytes($zeros, [byte[]]::new($SizeMB * 1MB))

$cliArgs = @("-c", "port=$Port br=$Baud dtr=high", "-w", $layoutFull)

Write-Host "Erasing eMMC..."
$proc = Start-Process -FilePath $cli -ArgumentList $cliArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "eMMC erase failed (exit $($proc.ExitCode))"
}

Write-Host "Done." -ForegroundColor Green
Write-Host "The eMMC has no valid image, so the ROM falls back to serial boot:"
Write-Host "flash normally now (flash.py / do.ps1) without touching the boot pins."
