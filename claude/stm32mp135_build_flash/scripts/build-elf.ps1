param(
    [string]$RepoRoot = ".",
    [string]$Config = "Debug",
    [switch]$Clean,
    [string]$ArmGccDir,
    [string]$MakeExe,
    [switch]$DryRun,
    [ValidateRange(1, 128)]
    [int]$Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Resolve repo root
# -------------------------------------------------------------------
$repoRootPath = (Resolve-Path -LiteralPath $RepoRoot).Path

# -------------------------------------------------------------------
# Locate the STM32CubeIDE build directory
# -------------------------------------------------------------------
$searchPaths = @(
    { Join-Path (Join-Path $repoRootPath "Application") $args[0] },
    { Join-Path $repoRootPath $args[0] }
)

$buildDir = $null
foreach ($pathBuilder in $searchPaths) {
    $candidate = & $pathBuilder $Config
    $makefile = Join-Path $candidate "makefile"
    if (Test-Path -LiteralPath $makefile -PathType Leaf) {
        $buildDir = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}

if (-not $buildDir) {
    Write-Host "No STM32CubeIDE build directory found."
    Write-Host "Expected $Config/makefile under '$repoRootPath/Application' or '$repoRootPath'."
    if ($DryRun) {
        Write-Host "Artifact      : <not found>"
        exit 0
    }
    Write-Host "Run STM32CubeIDE to generate the project first."
    exit 1
}

# -------------------------------------------------------------------
# Resolve toolchain
# -------------------------------------------------------------------
$toolchainScript = Join-Path $PSScriptRoot "find-toolchain.ps1"

if (-not $ArmGccDir -or -not $MakeExe) {
    if (-not (Test-Path -LiteralPath $toolchainScript -PathType Leaf)) {
        Write-Host "Toolchain not provided and find-toolchain.ps1 not found at $toolchainScript"
        exit 1
    }
    $tc = & "$PSScriptRoot\find-toolchain.ps1" -AsObject
    if (-not $ArmGccDir) { $ArmGccDir = $tc.ARM_GCC_DIR }
    if (-not $MakeExe)   { $MakeExe   = $tc.MAKE_EXE }
}

# -------------------------------------------------------------------
# Determine artifact name from makefile
# -------------------------------------------------------------------
$makefilePath = Join-Path $buildDir "makefile"
$artifactName = $null
$artifactExt = $null
foreach ($line in (Get-Content -LiteralPath $makefilePath)) {
    if (-not $artifactName -and $line -match "^BUILD_ARTIFACT_NAME\s*:?=\s*(.+)$") { $artifactName = $Matches[1].Trim() }
    if (-not $artifactExt -and $line -match "^BUILD_ARTIFACT_EXTENSION\s*:?=\s*(.*)$") { $artifactExt = $Matches[1].Trim() }
    if ($artifactName -and $artifactExt -ne $null) { break }
}
$elfFileName = if ($artifactName) {
    $ext = if ($artifactExt) { $artifactExt } else { "elf" }
    "$artifactName.$ext"
} else { "project.elf" }
$artifactPath = Join-Path $buildDir $elfFileName

# -------------------------------------------------------------------
# Dry-run report
# -------------------------------------------------------------------
Write-Host "Repo root     : $repoRootPath"
Write-Host "Build dir     : $buildDir"
Write-Host "Configuration : $Config"
Write-Host "Toolchain     : $ArmGccDir"
Write-Host "Make          : $MakeExe"
Write-Host "Artifact      : $artifactPath"

if ($DryRun) {
    $makeCmd = "& '$MakeExe' SHELL=cmd.exe -C '$buildDir' all -j $Jobs"
    if ($Clean) { $makeCmd = "& '$MakeExe' SHELL=cmd.exe -C '$buildDir' clean; $makeCmd" }
    Write-Host "Make command  : $makeCmd"
    exit 0
}

# -------------------------------------------------------------------
# Rebuild objects.list from subdir.mk files
# -------------------------------------------------------------------
Write-Host "Rebuilding objects.list from subdir.mk files..."

$objectPaths = [System.Collections.Generic.List[string]]::new()
foreach ($subdirMk in (Get-ChildItem -LiteralPath $buildDir -Recurse -Filter "subdir.mk" -File | Sort-Object FullName)) {
    $collecting = $false
    foreach ($line in (Get-Content -LiteralPath $subdirMk.FullName)) {
        $trimmed = $line.Trim()
        if (-not $collecting -and $trimmed -like "OBJS +=*") {
            $collecting = $true
            $trimmed = $trimmed.Substring(7).Trim()
        } elseif (-not $collecting) { continue }
        $continues = $trimmed.EndsWith("\")
        if ($continues) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1).Trim() }
        if ($trimmed) { [void]$objectPaths.Add($trimmed) }
        if (-not $continues) { $collecting = $false }
    }
}

if ($objectPaths.Count -eq 0) {
    Write-Host "No OBJS entries found under $buildDir."
    exit 1
}

$objectsListPath = Join-Path $buildDir "objects.list"
Set-Content -LiteralPath $objectsListPath -Value ($objectPaths | ForEach-Object { '"' + $_ + '"' }) -Encoding ascii
Write-Host "Objects list  : $objectsListPath ($($objectPaths.Count) objects)"

# -------------------------------------------------------------------
# Clean if requested
# -------------------------------------------------------------------
if ($Clean) {
    Write-Host "Cleaning generated outputs in $buildDir"
    Get-ChildItem -LiteralPath $buildDir -Recurse -File | Where-Object {
        $_.Name -eq "default.size.stdout" -or $_.Extension -in @(".o", ".d", ".su", ".cyclo", ".elf", ".map", ".list")
    } | Remove-Item -Force -ErrorAction SilentlyContinue
    # Run make clean
    & $MakeExe "SHELL=cmd.exe" "-C" $buildDir "clean" "-j" $Jobs
}

# -------------------------------------------------------------------
# Build
# -------------------------------------------------------------------
# Ensure toolchain is on PATH
if (-not (($env:Path -split [IO.Path]::PathSeparator) -contains $ArmGccDir)) {
    $env:Path = "$ArmGccDir$([IO.Path]::PathSeparator)$env:Path"
}
$env:CROSS_COMPILE = Join-Path $ArmGccDir "arm-none-eabi-"

Write-Host "Running make in $buildDir..."
& $MakeExe "SHELL=cmd.exe" "-C" $buildDir "all" "-j" $Jobs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
    $artifact = Get-Item -LiteralPath $artifactPath
    Write-Host "Build completed. Artifact: $artifactPath ($($artifact.Length) bytes)" -ForegroundColor Green
} else {
    Write-Host "Build completed but artifact not found at expected path: $artifactPath"
    exit 1
}

exit 0
