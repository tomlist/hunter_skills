param(
    [string]$RepoRoot = ".",
    [string]$ProjectDir = "STM32MP135C-DK_DDR_UTILITIES_A7",
    [string]$BuildScript = "build.ps1",
    [string]$ToolchainBin = "",
    [switch]$Clean,
    [switch]$GenStm32,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-NormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    if ([System.IO.Path]::IsPathRooted($ChildPath)) {
        return [System.IO.Path]::GetFullPath($ChildPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $ChildPath))
}

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    throw "Repo root not found: $repoRootPath"
}

$projectPath = Resolve-NormalizedPath -BasePath $repoRootPath -ChildPath $ProjectDir
if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
    throw "Project directory not found: $projectPath"
}

$buildScriptPath = Resolve-NormalizedPath -BasePath $projectPath -ChildPath $BuildScript
if (-not (Test-Path -LiteralPath $buildScriptPath -PathType Leaf)) {
    throw "Build script not found: $buildScriptPath"
}

$artifactName = Split-Path -Leaf $projectPath
$artifactPath = Join-Path $projectPath "build\$artifactName.stm32"
$commandParts = @("& `"$buildScriptPath`"")

if ($ToolchainBin) {
    $commandParts += "-ToolchainBin `"$ToolchainBin`""
}
if ($Clean) {
    $commandParts += "-Clean"
}
if ($GenStm32) {
    $commandParts += "-GenStm32"
}

Write-Host "Repo root: $repoRootPath"
Write-Host "Project path: $projectPath"
Write-Host "Build script: $buildScriptPath"
Write-Host "Expected image: $artifactPath"
Write-Host ("Command: " + ($commandParts -join " "))

if ($DryRun) {
    exit 0
}

Push-Location $projectPath
try {
    $invokeArgs = @{}
    if ($ToolchainBin) {
        $invokeArgs["ToolchainBin"] = $ToolchainBin
    }
    if ($Clean) {
        $invokeArgs["Clean"] = $true
    }
    if ($GenStm32) {
        $invokeArgs["GenStm32"] = $true
    }

    & $buildScriptPath @invokeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Build script failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

if ($GenStm32 -and -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "Expected .stm32 image was not generated: $artifactPath"
}

Write-Host "Build wrapper completed." -ForegroundColor Green
