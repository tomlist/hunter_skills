param(
    [Parameter(Mandatory)]
    [string]$ElfPath,
    [string]$OutputPath,
    [string]$HeaderScript,
    [string]$HeaderVersion = "2.0",
    [string]$BinaryType = "10",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Resolve paths
# -------------------------------------------------------------------
$scriptDir = $PSScriptRoot

# Resolve HeaderScript: explicit param or default relative to this script
if (-not $HeaderScript) {
    $HeaderScript = Join-Path $scriptDir "Python3\Stm32ImageAddHeader.py"
}
if (-not (Test-Path -LiteralPath $HeaderScript -PathType Leaf)) {
    Write-Host "Header script not found: $HeaderScript"
    exit 1
}

$elfFullPath = if ($DryRun) {
    if (Test-Path -LiteralPath $ElfPath -PathType Leaf) {
        (Resolve-Path -LiteralPath $ElfPath).Path
    } else {
        $ElfPath
    }
} else {
    (Resolve-Path -LiteralPath $ElfPath).Path
}

# Derive output path: replace .elf extension with .stm32
$elfDir = Split-Path $elfFullPath -Parent
if (-not $elfDir) { $elfDir = "." }
$stm32File = if ($OutputPath) {
    $OutputPath
} else {
    Join-Path $elfDir "$([IO.Path]::GetFileNameWithoutExtension($elfFullPath)).stm32"
}
$binFile = Join-Path (Split-Path $stm32File -Parent) "$([IO.Path]::GetFileNameWithoutExtension($stm32File))_postbuild.bin"

# -------------------------------------------------------------------
# Find toolchain (objcopy + readelf)
# -------------------------------------------------------------------
function Find-ArmTool {
    param([string]$Name)
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if ($found) { return $found.Path }
    if (Test-Path "C:\ST") {
        $patterns = @(
            "C:\ST\STM32CubeCLT_*\GNU-tools-for-STM32\bin\$Name",
            "C:\ST\STM32CubeIDE_*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32*\tools\bin\$Name"
        )
        foreach ($pattern in $patterns) {
            $candidates = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
            if ($candidates) { return $candidates[0].FullName }
        }
    }
    throw "Cannot find $Name"
}

# -------------------------------------------------------------------
# Find Python
# -------------------------------------------------------------------
$pythonExe = if (Get-Command python -ErrorAction SilentlyContinue) { "python" }
             elseif (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" }
             else { $null }

# -------------------------------------------------------------------
# Dry-run report
# -------------------------------------------------------------------
Write-Host "ELF          : $elfFullPath"
Write-Host "Binary       : $binFile"
Write-Host "Output       : $stm32File"
Write-Host "Header script: $HeaderScript"
Write-Host "Python       : $pythonExe"
Write-Host "Header ver   : $HeaderVersion"
Write-Host "Binary type  : $BinaryType"

if ($DryRun) { exit 0 }

# -------------------------------------------------------------------
# Check prerequisites
# -------------------------------------------------------------------
if (-not $pythonExe) {
    Write-Host "Python not found in PATH"
    exit 1
}

$readelf = Find-ArmTool "arm-none-eabi-readelf.exe"
$objcopy = Find-ArmTool "arm-none-eabi-objcopy.exe"

# -------------------------------------------------------------------
# Extract entry point
# -------------------------------------------------------------------
$epLine = & $readelf -h $elfFullPath | Select-String "Entry point address"
if (-not $epLine) { Write-Host "Failed to read entry point from ELF"; exit 1 }
$epMatch = [regex]::Match($epLine.Line, '0x([0-9A-Fa-f]+)')
if (-not $epMatch.Success) { Write-Host "Failed to parse entry point"; exit 1 }
$entryPoint = "0x" + $epMatch.Groups[1].Value.ToUpper().PadLeft(8, '0')

Write-Host "Entry point  : $entryPoint"

# -------------------------------------------------------------------
# ELF to binary
# -------------------------------------------------------------------
& $objcopy -O binary $elfFullPath $binFile
if ($LASTEXITCODE -ne 0) { Write-Host "objcopy failed"; exit 1 }

# -------------------------------------------------------------------
# Add STM32 header
# -------------------------------------------------------------------
& $pythonExe $HeaderScript $binFile $stm32File -hv $HeaderVersion -bt $BinaryType -ep $entryPoint
if ($LASTEXITCODE -ne 0) { Write-Host "Stm32ImageAddHeader failed"; exit 1 }

# Cleanup intermediate binary
Remove-Item $binFile -Force

Write-Host "Done: $stm32File" -ForegroundColor Green
exit 0
