param(
    [string]$Config = "Debug",
    [switch]$Clean,
    [switch]$DryRun,
    [switch]$Help,
    [string]$ProjectRoot
)

if ($Help) {
    @"
build.ps1 - build an STM32MP135 CubeIDE project and generate the .stm32 image

Usage:
  pwsh -File build.ps1 [-ProjectRoot <path>] [-Config Debug|Release] [-Clean] [-DryRun]

Parameters:
  -ProjectRoot <path>  Project root (default: the directory above this script)
  -Config <name>       Build configuration: Debug (default) or Release
  -Clean               Clean before building
  -DryRun              Print what would happen, then exit
  -Help                Show this help

Steps:
  1. locate arm-none-eabi-gcc and make
  2. find the build directory (Application\<Config>\ or <Config>\)
  3. optionally clean
  4. rebuild objects.list from the subdir.mk files
  5. run make
  6. objcopy the .elf and add the ST V2.0 header -> <project>.stm32
"@
    exit 0
}

$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# 1. Find toolchain
# -------------------------------------------------------------------
function Find-ArmGcc {
    $candidates = @()
    foreach ($d in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeCLT_*" -ErrorAction SilentlyContinue) {
        $p = Join-Path $d.FullName "GNU-tools-for-STM32\bin\arm-none-eabi-gcc.exe"
        if (Test-Path $p) { $candidates += $p }
    }
    if (-not $candidates) {
        foreach ($ide in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeIDE_*" -ErrorAction SilentlyContinue) {
            $plugins = Join-Path $ide.FullName "STM32CubeIDE\plugins"
            foreach ($pl in Get-ChildItem $plugins -Directory -Filter "com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32*" -ErrorAction SilentlyContinue) {
                $p = Join-Path $pl.FullName "tools\bin\arm-none-eabi-gcc.exe"
                if (Test-Path $p) { $candidates += $p }
            }
        }
    }
    if (-not $candidates) {
        $cmd = Get-Command "arm-none-eabi-gcc.exe" -ErrorAction SilentlyContinue
        if ($cmd) { $candidates += $cmd.Path }
    }
    if (-not $candidates) { throw "arm-none-eabi-gcc not found. Install STM32CubeCLT or STM32CubeIDE." }
    return $candidates[0]
}

function Find-Make {
    $candidates = @()
    foreach ($d in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeCLT_*" -ErrorAction SilentlyContinue) {
        foreach ($md in Get-ChildItem $d.FullName -Directory -Filter "make-*" -ErrorAction SilentlyContinue) {
            $p = Join-Path $md.FullName "bin\make.exe"
            if (Test-Path $p) { $candidates += $p }
        }
    }
    $gw = "C:\Program Files (x86)\GnuWin32\bin\make.exe"
    if (Test-Path $gw) { $candidates += $gw }
    if (-not $candidates) {
        $cmd = Get-Command "make.exe" -ErrorAction SilentlyContinue
        if ($cmd) { $candidates += $cmd.Path }
    }
    if (-not $candidates) { throw "make not found. Install GnuWin32 make or add to PATH." }
    return $candidates[0]
}

$armGccExe = Find-ArmGcc
$armGccDir = Split-Path -Parent $armGccExe
$makeExe = Find-Make

# -------------------------------------------------------------------
# 2. Find build directory
# -------------------------------------------------------------------
$projectRoot = if ($ProjectRoot) { $ProjectRoot } else { Split-Path -Parent $PSScriptRoot }
$buildDir = $null
foreach ($base in @("Application", ".")) {
    $candidate = Join-Path $projectRoot "$base\$Config"
    if (Test-Path (Join-Path $candidate "makefile")) {
        $buildDir = (Resolve-Path $candidate).Path
        break
    }
}
if (-not $buildDir) { throw "No $Config/makefile found under $projectRoot. Build from STM32CubeIDE first." }

$artifactName = $null
foreach ($line in (Get-Content (Join-Path $buildDir "makefile"))) {
    if ($line -match "^BUILD_ARTIFACT_NAME\s*:?=\s*(.+)$") { $artifactName = $Matches[1].Trim(); break }
}
$elfPath = Join-Path $buildDir "$artifactName.elf"

Write-Host "Toolchain : $armGccDir"
Write-Host "Make      : $makeExe"
Write-Host "Build dir : $buildDir"
Write-Host "Artifact  : $elfPath"

if ($DryRun) { exit 0 }

# -------------------------------------------------------------------
# 3. Clean (optional)
# -------------------------------------------------------------------
if ($Clean) {
    Write-Host "Cleaning..."
    & $makeExe "SHELL=cmd.exe" "-C" $buildDir "clean" "-j" $env:NUMBER_OF_PROCESSORS
}

# -------------------------------------------------------------------
# 4. Rebuild objects.list from subdir.mk
# -------------------------------------------------------------------
Write-Host "Rebuilding objects.list..."
$objects = @()
foreach ($mk in Get-ChildItem $buildDir -Recurse -Filter "subdir.mk" -File | Sort-Object FullName) {
    $collect = $false
    foreach ($line in (Get-Content $mk.FullName)) {
        $t = $line.Trim()
        if (-not $collect -and $t -like "OBJS +=*") { $collect = $true; $t = $t.Substring(7).Trim() }
        elseif (-not $collect) { continue }
        $cont = $t.EndsWith("\")
        if ($cont) { $t = $t.Substring(0, $t.Length - 1).Trim() }
        if ($t) { $objects += $t }
        if (-not $cont) { $collect = $false }
    }
}
Set-Content -Path (Join-Path $buildDir "objects.list") -Value ($objects | ForEach-Object { '"' + $_ + '"' }) -Encoding ascii
Write-Host "  $($objects.Count) objects"

# -------------------------------------------------------------------
# 5. Build
# -------------------------------------------------------------------
$env:Path = "$armGccDir$([IO.Path]::PathSeparator)$env:Path"
$env:CROSS_COMPILE = Join-Path $armGccDir "arm-none-eabi-"

Write-Host "Building..."
& $makeExe "SHELL=cmd.exe" "-C" $buildDir "all" "-j" $env:NUMBER_OF_PROCESSORS
if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)" }

if (-not (Test-Path $elfPath)) { throw "ELF not found: $elfPath" }
Write-Host "ELF : $elfPath ($((Get-Item $elfPath).Length) bytes)"

# -------------------------------------------------------------------
# 6. Generate .stm32 (elf -> bin -> add header)
# -------------------------------------------------------------------
$stm32Path = Join-Path $buildDir "$artifactName.stm32"
$binPath = Join-Path $buildDir "${artifactName}_postbuild.bin"
$headerScript = Join-Path $PSScriptRoot "imageheader\Python3\Stm32ImageAddHeader.py"

$readelf = Join-Path $armGccDir "arm-none-eabi-readelf.exe"
$epLine = & $readelf -h $elfPath | Select-String "Entry point address"
$epMatch = [regex]::Match($epLine.Line, '0x([0-9A-Fa-f]+)')
if (-not $epMatch.Success) { throw "Failed to read entry point" }
$entryPoint = "0x" + $epMatch.Groups[1].Value.ToUpper().PadLeft(8, '0')
Write-Host "Entry point: $entryPoint"

$objcopy = Join-Path $armGccDir "arm-none-eabi-objcopy.exe"
& $objcopy -O binary $elfPath $binPath
if ($LASTEXITCODE -ne 0) { throw "objcopy failed" }

python $headerScript $binPath $stm32Path -hv "2.0" -bt "10" -ep $entryPoint
if ($LASTEXITCODE -ne 0) { throw "Stm32ImageAddHeader failed" }

Remove-Item $binPath -Force

Write-Host "STM32 : $stm32Path ($((Get-Item $stm32Path).Length) bytes)" -ForegroundColor Green
Write-Host "Done." -ForegroundColor Green
