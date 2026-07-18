param(
    [Parameter(Mandatory)]
    [string]$ElfPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Resolve paths
# -------------------------------------------------------------------
if ($DryRun) {
    # In dry-run mode, don't require the ELF to exist
    $elfFullPath = if (Test-Path -LiteralPath $ElfPath -PathType Leaf) {
        (Resolve-Path -LiteralPath $ElfPath).Path
    } else {
        $ElfPath
    }
} else {
    $elfFullPath = (Resolve-Path -LiteralPath $ElfPath).Path
}

$postbuildScript = Join-Path $PSScriptRoot "imageheader\postbuild.ps1"

if (-not (Test-Path -LiteralPath $postbuildScript -PathType Leaf)) {
    Write-Host "Postbuild script not found: $postbuildScript"
    exit 1
}

$elfDir = Split-Path $elfFullPath -Parent
if (-not $elfDir) { $elfDir = "." }
$stm32Output = Join-Path $elfDir "$([IO.Path]::GetFileNameWithoutExtension($elfFullPath)).stm32"

Write-Host "ELF          : $elfFullPath"
Write-Host "Output       : $stm32Output"

if ($DryRun) {
    Write-Host "Postbuild    : $postbuildScript"
    Write-Host "Command      : pwsh -File '$postbuildScript' -ElfPath '$elfFullPath' -OutputPath '$stm32Output'"
    exit 0
}

# -------------------------------------------------------------------
# Invoke postbuild
# -------------------------------------------------------------------
pwsh -ExecutionPolicy Bypass -File $postbuildScript -ElfPath $elfFullPath -OutputPath $stm32Output
if ($LASTEXITCODE -ne 0) {
    Write-Host "Postbuild failed (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $stm32Output -PathType Leaf)) {
    Write-Host "Expected .stm32 image was not generated: $stm32Output"
    exit 1
}

Write-Host "STM32 image  : $stm32Output" -ForegroundColor Green
exit 0
