param(
    [Parameter(Mandatory)]
    [string]$ElfPath,
    [string]$OutputPath,
    [string]$HeaderVersion = "2.0",
    [string]$BinaryType = "10"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot

# --- Find toolchain ---
function Find-ARMExecutable {
    param([string]$Name)

    # Check PATH first
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if ($found) { return $found.Path }

    # Check STM32CubeCLT / STM32CubeIDE
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

$readelf = Find-ARMExecutable "arm-none-eabi-readelf.exe"
$objcopy = Find-ARMExecutable "arm-none-eabi-objcopy.exe"

# --- Extract entry point ---
$epLine = & $readelf -h $ElfPath | Select-String "Entry point address"
if (-not $epLine) { throw "Failed to read entry point from ELF" }
$epMatch = [regex]::Match($epLine.Line, '0x([0-9A-Fa-f]+)')
if (-not $epMatch.Success) { throw "Failed to parse entry point" }
$entryPoint = "0x" + $epMatch.Groups[1].Value.ToUpper().PadLeft(8, '0')

# --- ELF to binary ---
$baseName = if ($OutputPath) {
    Join-Path (Split-Path $OutputPath -Parent) ([IO.Path]::GetFileNameWithoutExtension($OutputPath))
} else {
    Join-Path (Split-Path $ElfPath -Parent) ([IO.Path]::GetFileNameWithoutExtension($ElfPath))
}
$binFile = "${baseName}_postbuild.bin"
$stm32File = if ($OutputPath) { $OutputPath } else { "${baseName}.stm32" }

Write-Host "ELF        : $ElfPath"
Write-Host "Entry point: $entryPoint"
Write-Host "Binary     : $binFile"
Write-Host "Output     : $stm32File"

& $objcopy -O binary $ElfPath $binFile
if ($LASTEXITCODE -ne 0) { throw "objcopy failed" }

# --- Add STM32 header ---
$pyScript = Join-Path $scriptDir "Python3\Stm32ImageAddHeader.py"
if (-not (Test-Path $pyScript)) { throw "Missing: $pyScript" }

$pyCmd = if (Get-Command python -ErrorAction SilentlyContinue) { "python" }
         elseif (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" }
         else { throw "Python not found in PATH" }

& $pyCmd $pyScript $binFile $stm32File -hv $HeaderVersion -bt $BinaryType -ep $entryPoint
if ($LASTEXITCODE -ne 0) { throw "Stm32ImageAddHeader failed" }

# Cleanup intermediate binary
Remove-Item $binFile -Force

Write-Host "Done: $stm32File"
