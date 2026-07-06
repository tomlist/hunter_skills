param(
    [string]$RepoRoot = ".",
    [string]$ProjectDir = ".",
    [string]$Configuration,
    [switch]$Clean,
    [switch]$GenStm32,
    [switch]$DryRun,
    [ValidateRange(1, 128)]
    [int]$Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Resolve project root
# -------------------------------------------------------------------
$repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path
$projectRootPath = if ($ProjectDir -eq ".") {
    $repoRootPath
} else {
    Join-Path $repoRootPath $ProjectDir
}
if (-not (Test-Path -LiteralPath $projectRootPath -PathType Container)) {
    throw "Project directory not found: $projectRootPath"
}

# -------------------------------------------------------------------
# Locate the STM32CubeIDE build directory
# -------------------------------------------------------------------
$configurations = if ($Configuration) { @($Configuration) } else { @("Debug", "Release") }

$searchPaths = @(
    { Join-Path $projectRootPath $args[0] },
    { Join-Path (Join-Path $projectRootPath "Application") $args[0] }
)

$buildInfo = $null
foreach ($name in $configurations) {
    foreach ($pathBuilder in $searchPaths) {
        $candidate = & $pathBuilder $name
        $makefile = Join-Path $candidate "makefile"
        if (Test-Path -LiteralPath $makefile -PathType Leaf) {
            $buildInfo = [pscustomobject]@{
                Name     = $name
                Path     = (Resolve-Path -LiteralPath $candidate).Path
                Makefile = (Resolve-Path -LiteralPath $makefile).Path
            }
            break
        }
    }
    if ($buildInfo) { break }
}

if (-not $buildInfo) {
    throw "No generated STM32CubeIDE build directory found. Expected Debug/makefile or Release/makefile under '$projectRootPath' or '$projectRootPath\Application'. Run STM32CubeIDE to regenerate the project."
}

# -------------------------------------------------------------------
# Discover toolchain
# -------------------------------------------------------------------
function Add-CandidatePath {
    param([Parameter(Mandatory)][System.Collections.IList]$List, [string]$Path)
    if (-not $Path) { return }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        if (-not $List.Contains($resolved)) { $List.Add($resolved) }
    }
}

function Find-MakeExecutable {
    $candidates = [System.Collections.Generic.List[string]]::new()
    Add-CandidatePath -List $candidates -Path "C:\Program Files (x86)\GnuWin32\bin\make.exe"
    Add-CandidatePath -List $candidates -Path "C:\Program Files\GnuWin32\bin\make.exe"
    foreach ($cmd in @("make.exe", "mingw32-make.exe")) {
        foreach ($item in @(Get-Command $cmd -ErrorAction SilentlyContinue)) {
            if ($item) { Add-CandidatePath -List $candidates -Path $item.Path }
        }
    }
    if ($candidates.Count -eq 0) { throw "No make executable found. Install GnuWin32 make.exe or add it to PATH." }
    return ($candidates | Sort-Object { if ($_ -match "GnuWin32") { 0 } else { 1 } }, { $_ })[0]
}

function Find-ToolchainBin {
    param([string]$PreferredVersion)
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @(Get-Command "arm-none-eabi-gcc.exe" -ErrorAction SilentlyContinue)) {
        if ($item) { Add-CandidatePath -List $candidates -Path $item.Path }
    }
    if (Test-Path "C:\ST") {
        foreach ($clt in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeCLT_*" -ErrorAction SilentlyContinue) {
            Add-CandidatePath -List $candidates -Path (Join-Path $clt.FullName "GNU-tools-for-STM32\bin\arm-none-eabi-gcc.exe")
        }
        foreach ($ide in Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeIDE_*" -ErrorAction SilentlyContinue) {
            $pluginsDir = Join-Path $ide.FullName "STM32CubeIDE\plugins"
            if (-not (Test-Path $pluginsDir)) { continue }
            foreach ($plugin in Get-ChildItem $pluginsDir -Directory -Filter "com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32*" -ErrorAction SilentlyContinue) {
                Add-CandidatePath -List $candidates -Path (Join-Path $plugin.FullName "tools\bin\arm-none-eabi-gcc.exe")
            }
        }
    }
    if ($candidates.Count -eq 0) { throw "No arm-none-eabi-gcc toolchain found. Install STM32CubeCLT or STM32CubeIDE." }
    $selected = ($candidates | Sort-Object {
        $score = 0
        if ($PreferredVersion -and $_ -match [regex]::Escape($PreferredVersion)) { $score += 100 }
        if ($_ -match "STM32CubeCLT") { $score += 10 }
        -$score
    } | Select-Object -First 1)
    return Split-Path -Parent $selected
}

# Read preferred toolchain version from makefile
$preferredVersion = $null
foreach ($line in (Get-Content -LiteralPath $buildInfo.Makefile -TotalCount 10)) {
    if ($line -match "GNU Tools for STM32 \(([^)]+)\)") { $preferredVersion = $Matches[1]; break }
}

$makeExe = Find-MakeExecutable
$toolchainBin = Find-ToolchainBin -PreferredVersion $preferredVersion

# -------------------------------------------------------------------
# Determine artifact name from makefile
# -------------------------------------------------------------------
$artifactName = $null
$artifactExt = $null
foreach ($line in (Get-Content -LiteralPath $buildInfo.Makefile)) {
    if (-not $artifactName -and $line -match "^BUILD_ARTIFACT_NAME :=\s*(.+)$") { $artifactName = $Matches[1].Trim() }
    if (-not $artifactExt -and $line -match "^BUILD_ARTIFACT_EXTENSION :=\s*(.*)$") { $artifactExt = $Matches[1].Trim() }
    if ($artifactName -and $artifactExt -ne $null) { break }
}
$elfFileName = if ($artifactName -and $artifactExt) { "$artifactName.$artifactExt" } else { "$artifactName.elf" }
$artifactPath = Join-Path $buildInfo.Path $elfFileName

# -------------------------------------------------------------------
# Rebuild objects.list (in case files were added/removed)
# -------------------------------------------------------------------
function Write-ObjectsList {
    param([Parameter(Mandatory)][string]$BuildDirectory)
    $objectPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($subdirMk in (Get-ChildItem -LiteralPath $BuildDirectory -Recurse -Filter "subdir.mk" -File | Sort-Object FullName)) {
        $collecting = $false
        foreach ($line in (Get-Content -LiteralPath $subdirMk.FullName)) {
            $trimmed = $line.Trim()
            if (-not $collecting -and $trimmed -like "OBJS +=*") {
                $collecting = $true
                $trimmed = $trimmed.Substring(7).Trim()
            } elseif (-not $collecting) { continue }
            $continues = $trimmed.EndsWith("\")
            if ($continues) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1).Trim() }
            if ($trimmed) { $objectPaths.Add($trimmed) }
            if (-not $continues) { $collecting = $false }
        }
    }
    if ($objectPaths.Count -eq 0) { throw "No OBJS entries found under $BuildDirectory." }
    $path = Join-Path $BuildDirectory "objects.list"
    Set-Content -LiteralPath $path -Value ($objectPaths | ForEach-Object { '"' + $_ + '"' }) -Encoding ascii
    return $path
}

function Remove-BuildOutputs {
    param([Parameter(Mandatory)][string]$BuildDirectory)
    Get-ChildItem -LiteralPath $BuildDirectory -Recurse -File | Where-Object {
        $_.Name -eq "default.size.stdout" -or $_.Extension -in @(".o", ".d", ".su", ".cyclo", ".elf", ".map", ".list")
    } | Remove-Item -Force
}

# -------------------------------------------------------------------
# Locate postbuild script (search project, repo root, then bundled skill scripts)
# -------------------------------------------------------------------
function Find-PostbuildScript {
    foreach ($base in @($projectRootPath, $repoRootPath)) {
        $candidate = Join-Path $base "Scripts\imageheader\postbuild.ps1"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    # Fallback to skill's bundled copy
    $bundled = Join-Path $PSScriptRoot "imageheader\postbuild.ps1"
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
    return $null
}

# -------------------------------------------------------------------
# Dry-run report
# -------------------------------------------------------------------
$postbuildScript = if ($GenStm32) { Find-PostbuildScript } else { $null }
$stm32Output = if ($GenStm32 -and $artifactPath) {
    Join-Path (Split-Path $artifactPath -Parent) "$([IO.Path]::GetFileNameWithoutExtension($artifactPath)).stm32"
} else { "" }

Write-Host "Repo root     : $repoRootPath"
Write-Host "Project root  : $projectRootPath"
Write-Host "Build dir     : $($buildInfo.Path)"
Write-Host "Configuration : $($buildInfo.Name)"
Write-Host "Make          : $makeExe"
Write-Host "Toolchain     : $toolchainBin"
Write-Host "Artifact      : $artifactPath"
if ($GenStm32) { Write-Host "Postbuild     : $postbuildScript" }
if ($stm32Output) { Write-Host "STM32 output  : $stm32Output" }

if ($DryRun) { exit 0 }

# -------------------------------------------------------------------
# Build
# -------------------------------------------------------------------
if (-not (($env:Path -split ";") -contains $toolchainBin)) {
    $env:Path = "$toolchainBin;$env:Path"
}

if ($Clean) {
    Write-Host "Cleaning generated outputs in $($buildInfo.Path)"
    Remove-BuildOutputs -BuildDirectory $buildInfo.Path
}

$objectsListPath = Write-ObjectsList -BuildDirectory $buildInfo.Path
Write-Host "Objects list  : $objectsListPath"

& $makeExe "SHELL=cmd.exe" "-C" $buildInfo.Path "all" "-j" $Jobs
if ($LASTEXITCODE -ne 0) { throw "Build failed (exit code $LASTEXITCODE)" }

if ($artifactPath -and (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    $artifact = Get-Item -LiteralPath $artifactPath
    Write-Host "Artifact size : $($artifact.Length) bytes"
}

# -------------------------------------------------------------------
# PostBuild: add STM32 header
# -------------------------------------------------------------------
if ($GenStm32) {
    if (-not $artifactPath -or -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "No ELF artifact to generate .stm32 from."
    }
    if (-not $postbuildScript) {
        throw "Postbuild script not found at Scripts\imageheader\postbuild.ps1. Ensure the imageheader scripts are present in the project."
    }
    Write-Host ""
    pwsh -ExecutionPolicy Bypass -File $postbuildScript -ElfPath $artifactPath -OutputPath $stm32Output
    if ($LASTEXITCODE -ne 0) { throw "Postbuild failed (exit code $LASTEXITCODE)" }

    if (-not (Test-Path -LiteralPath $stm32Output -PathType Leaf)) {
        throw "Expected .stm32 image was not generated: $stm32Output"
    }
}

Write-Host "Build completed." -ForegroundColor Green
