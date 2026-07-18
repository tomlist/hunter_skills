param(
    [Parameter(Mandatory)]
    [string]$ImagePath,
    [string]$Port = "USB1",
    [string]$RepoRoot = ".",
    [int]$Baud = 921600,
    [string]$PartitionId = "0x01",
    [switch]$NoStart,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Platform guard
# -------------------------------------------------------------------
if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
    Write-Host "flash-target.ps1 is only supported on Windows"
    exit 1
}

# -------------------------------------------------------------------
# Check STM32_Programmer_CLI
# -------------------------------------------------------------------
if (-not $DryRun) {
    $cliFound = Get-Command "STM32_Programmer_CLI.exe" -ErrorAction SilentlyContinue
    if (-not $cliFound) {
        Write-Host "STM32_Programmer_CLI.exe not found on PATH. Install STM32CubeProgrammer."
        exit 1
    }
    $programmerCli = $cliFound.Path
} else {
    $programmerCli = "STM32_Programmer_CLI.exe"
}

# -------------------------------------------------------------------
# Resolve paths
# -------------------------------------------------------------------
if ($DryRun) {
    $imageFullPath = if (Test-Path -LiteralPath $ImagePath -PathType Leaf) {
        (Resolve-Path -LiteralPath $ImagePath).Path
    } else {
        $ImagePath
    }
} else {
    $imageFullPath = (Resolve-Path -LiteralPath $ImagePath).Path
}
$repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
$testStm32 = Join-Path $repoRootPath "test.stm32"

Write-Host "Image        : $imageFullPath"
Write-Host "Port         : $Port"
Write-Host "Baud         : $Baud"
Write-Host "Staging      : $testStm32"
Write-Host "Programmer   : $programmerCli"

# -------------------------------------------------------------------
# Build CLI arguments
# -------------------------------------------------------------------
if ($Port -eq "USB1") {
    $cliArgs = @("-c", "port=USB1", "-d", "test.stm32", $PartitionId)
    if (-not $NoStart) { $cliArgs += @("-g", $PartitionId) }
} else {
    $cliArgs = @("-c", "port=$Port br=$Baud", "-d", "test.stm32", $PartitionId)
    if (-not $NoStart) { $cliArgs += @("-g", $PartitionId) }
}

Write-Host "CLI command  : $programmerCli $($cliArgs -join ' ')"

if ($DryRun) { exit 0 }

# -------------------------------------------------------------------
# RTS reset for UART mode
# -------------------------------------------------------------------
if ($Port -ne "USB1") {
    Write-Host "Resetting MPU via RTS on $Port..."
    try {
        $uart = New-Object System.IO.Ports.SerialPort $Port, 115200, "None", 8, "One"
        $uart.RtsEnable = $false
        $uart.Open()
        Start-Sleep -Milliseconds 50
        $uart.RtsEnable = $true
        Start-Sleep -Milliseconds 200
        $uart.RtsEnable = $false
        Start-Sleep -Milliseconds 200
        $uart.Close()
        $uart.Dispose()
    } catch {
        Write-Host "Failed to reset MPU via RTS: $_"
        exit 1
    }
}

# -------------------------------------------------------------------
# Stage image
# -------------------------------------------------------------------
Copy-Item -LiteralPath $imageFullPath -Destination $testStm32 -Force

# -------------------------------------------------------------------
# Flash
# -------------------------------------------------------------------
Write-Host "Flashing target via $Port..."
$proc = Start-Process -FilePath $programmerCli -ArgumentList $cliArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Host "Flash failed (exit code $($proc.ExitCode))"
    exit $proc.ExitCode
}

if (-not $NoStart) {
    Write-Host "Flash completed, target started." -ForegroundColor Green
} else {
    Write-Host "Flash completed (target not started)." -ForegroundColor Green
}

exit 0
