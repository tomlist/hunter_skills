param(
    [string]$Port = "USB1",
    [string]$Config = "Debug",
    [switch]$Clean,
    [switch]$NoStart,
    [switch]$NoMonitor,
    [switch]$MonitorOnly,
    [int]$Baud = 921600,
    [int]$MonitorBaud = 115200,
    [string]$DoneMarker = "<<<DONE>>>",
    [int]$Timeout = 600,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptsDir = Join-Path $PSScriptRoot "scripts"

# -------------------------------------------------------------------
# Helper: find build directory and artifact
# -------------------------------------------------------------------
function Resolve-BuildInfo {
    param([string]$Config)

    $searchPaths = @(
        { Join-Path (Join-Path $PSScriptRoot "Application") $args[0] },
        { Join-Path $PSScriptRoot $args[0] }
    )

    foreach ($pathBuilder in $searchPaths) {
        $candidate = & $pathBuilder $Config
        $makefile = Join-Path $candidate "makefile"
        if (Test-Path -LiteralPath $makefile -PathType Leaf) {
            $buildDir = (Resolve-Path -LiteralPath $candidate).Path
            $artifactName = $null
            $artifactExt = $null
            foreach ($line in (Get-Content -LiteralPath $makefile)) {
                if (-not $artifactName -and $line -match "^BUILD_ARTIFACT_NAME\s*:?=\s*(.+)$") { $artifactName = $Matches[1].Trim() }
                if (-not $artifactExt -and $line -match "^BUILD_ARTIFACT_EXTENSION\s*:?=\s*(.*)$") { $artifactExt = $Matches[1].Trim() }
                if ($artifactName -and $artifactExt -ne $null) { break }
            }
            $ext = if ($artifactExt) { $artifactExt } else { "elf" }
            $elfName = if ($artifactName) { "$artifactName.$ext" } else { "project.elf" }
            $elfPath = Join-Path $buildDir $elfName
            $stm32Path = Join-Path $buildDir "$([IO.Path]::GetFileNameWithoutExtension($elfName)).stm32"
            return @{
                BuildDir  = $buildDir
                Config    = $Config
                ElfPath   = $elfPath
                Stm32Path = $stm32Path
            }
        }
    }
    return $null
}

$buildInfo = Resolve-BuildInfo -Config $Config
$dryFlag = if ($DryRun) { "-DryRun" } else { "" }

Write-Host "=== stm32mp135_build_flash ==="
Write-Host "Project root : $PSScriptRoot"
Write-Host "Port         : $Port"
Write-Host ""

if (-not $buildInfo) {
    Write-Host "No STM32CubeIDE build directory found."
    Write-Host "Expected $Config/makefile under '$PSScriptRoot/Application' or '$PSScriptRoot'."
    if (-not $DryRun) { exit 1 }
    Write-Host "[DryRun] Would exit with error."
    exit 0
}

Write-Host "Build dir    : $($buildInfo.BuildDir)"
Write-Host "ELF          : $($buildInfo.ElfPath)"
Write-Host "STM32        : $($buildInfo.Stm32Path)"
Write-Host ""

# -------------------------------------------------------------------
# MonitorOnly mode
# -------------------------------------------------------------------
if ($MonitorOnly) {
    if ($Port -eq "USB1") {
        Write-Host "MonitorOnly requires a COM port (use -Port COMx)"
        exit 1
    }
    Write-Host "Skipping build and flash (MonitorOnly)."
    Write-Host ""
    $monitorArgs = @(
        $Port,
        "--repo-root", $PSScriptRoot,
        "--done-marker", $DoneMarker,
        "--timeout", "$Timeout",
        "--baud", "$MonitorBaud"
    )
    if ($DryRun) { $monitorArgs += "--dry-run" }
    & python (Join-Path $ScriptsDir "monitor-uart.py") @monitorArgs
    exit $LASTEXITCODE
}

# -------------------------------------------------------------------
# Step 1: Build
# -------------------------------------------------------------------
Write-Host "--- Build ---"
$buildArgs = @(
    "-RepoRoot", $PSScriptRoot,
    "-Config", $Config
)
if ($Clean)   { $buildArgs += "-Clean" }
if ($DryRun)  { $buildArgs += "-DryRun" }

& pwsh -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir "build-elf.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""

# -------------------------------------------------------------------
# Step 2: Generate .stm32 header
# -------------------------------------------------------------------
Write-Host "--- Generate STM32 header ---"
$genArgs = @("-ElfPath", $buildInfo.ElfPath)
if ($DryRun) { $genArgs += "-DryRun" }

& pwsh -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir "gen-stm32-header.ps1") @genArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""

# -------------------------------------------------------------------
# Step 3: Flash
# -------------------------------------------------------------------
Write-Host "--- Flash ---"
$flashArgs = @(
    "-ImagePath", $buildInfo.Stm32Path,
    "-Port", $Port,
    "-RepoRoot", $PSScriptRoot,
    "-Baud", $Baud
)
if ($NoStart)  { $flashArgs += "-NoStart" }
if ($DryRun)   { $flashArgs += "-DryRun" }

& pwsh -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir "flash-target.ps1") @flashArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""

# -------------------------------------------------------------------
# Step 4: Monitor (optional)
# -------------------------------------------------------------------
if (-not $NoMonitor -and $Port -ne "USB1") {
    Write-Host "--- Monitor ---"
    $monitorArgs = @(
        $Port,
        "--repo-root", $PSScriptRoot,
        "--done-marker", $DoneMarker,
        "--timeout", "$Timeout",
        "--baud", "$MonitorBaud"
    )
    if ($DryRun) { $monitorArgs += "--dry-run" }
    & python (Join-Path $ScriptsDir "monitor-uart.py") @monitorArgs
    exit $LASTEXITCODE
}

Write-Host "Done." -ForegroundColor Green
exit 0
