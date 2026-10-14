param(
    [switch]$Clean,
    [string]$Config = "Debug",
    [int]$MonitorTimeout = 30,
    [switch]$NoMonitor,
    [string]$ConfigPath,
    [switch]$Help,
    [string]$ProjectRoot
)

if ($Help) {
    @"
do.ps1 - one-shot pipeline for an STM32MP135 project: build -> reset -> flash -> monitor

Usage:
  pwsh -File do.ps1 [-ProjectRoot <path>] [-Clean] [-Config Debug|Release] [-MonitorTimeout <sec>] [-NoMonitor] [-ConfigPath <path>]

Parameters:
  -ProjectRoot <path>     Project root (default: the directory above this script)
  -Clean                  Clean rebuild
  -Config <name>          Build configuration: Debug (default) or Release
  -MonitorTimeout <sec>   Seconds to monitor the UART (default 30)
  -NoMonitor              Skip the UART monitor step
  -ConfigPath <path>      config.yaml override (default: ./config.yaml, then script dir)
  -Help                   Show this help

Device settings (flash/monitor ports, baud, DTR, reset method) come from
config.yaml - not from command-line switches.

Steps: build.ps1 -> reset.py -> flash.py -> monitor.py; stops at the first failure.
"@
    exit 0
}

$ErrorActionPreference = "Stop"
$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = if ($ProjectRoot) { $ProjectRoot } else { Split-Path -Parent $scriptsDir }

Push-Location $projectRoot

try {
    # Discover artifact name from makefile
    $makefile = Join-Path $projectRoot "Application\$Config\makefile"
    if (-not (Test-Path $makefile)) {
        $makefile = Join-Path $projectRoot "$Config\makefile"
    }
    $artifactName = $null
    foreach ($line in (Get-Content $makefile)) {
        if ($line -match "^BUILD_ARTIFACT_NAME\s*:?=\s*(.+)$") {
            $artifactName = $Matches[1].Trim()
            break
        }
    }
    if (-not $artifactName) {
        throw "Could not determine artifact name from $makefile"
    }
    $stm32 = "Application\$Config\$artifactName.stm32"

    # 1. Build
    Write-Host "=== Build ===" -ForegroundColor Cyan
    $buildArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $scriptsDir "build.ps1"), "-ProjectRoot", $projectRoot)
    if ($Clean) { $buildArgs += "-Clean" }
    if ($Config -ne "Debug") { $buildArgs += @("-Config", $Config) }
    pwsh @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)" }

    # 2. Reset — method from config.yaml: "gpio" (debugprobe two-step) or "uart_rts"
    Write-Host "=== Reset ===" -ForegroundColor Cyan
    $resetArgs = @((Join-Path $scriptsDir "reset.py"))
    if ($ConfigPath) { $resetArgs += @("--config", $ConfigPath) }
    python @resetArgs
    if ($LASTEXITCODE -ne 0) { throw "Reset failed (exit $LASTEXITCODE)" }

    # 3. Flash — interface/port/baud/DTR/RTS come from config.yaml
    Write-Host "=== Flash ===" -ForegroundColor Cyan
    $flashArgs = @((Join-Path $scriptsDir "flash.py"), "--image", $stm32)
    if ($ConfigPath) { $flashArgs += @("--config", $ConfigPath) }
    python @flashArgs
    if ($LASTEXITCODE -ne 0) { throw "Flash failed (exit $LASTEXITCODE)" }

    # 4. Monitor — port/baud/DTR come from config.yaml
    if (-not $NoMonitor) {
        Write-Host "=== Monitor ===" -ForegroundColor Cyan
        $monArgs = @((Join-Path $scriptsDir "monitor.py"), "-t", $MonitorTimeout)
        if ($ConfigPath) { $monArgs += @("--config", $ConfigPath) }
        python @monArgs
        if ($LASTEXITCODE -ne 0) { throw "Monitor failed (exit $LASTEXITCODE)" }
    }
}
finally {
    Pop-Location
}
