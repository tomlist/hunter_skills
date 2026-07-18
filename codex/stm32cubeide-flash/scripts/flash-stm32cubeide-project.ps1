param(
    [string]$ProjectRoot = ".",
    [string]$Configuration,
    [string]$FirmwarePath,
    [string]$OpenOcdPath,
    [string]$InterfaceConfig = "interface/cmsis-dap.cfg",
    [string]$TargetConfig = "target/stm32f1x.cfg",
    [string]$Transport = "swd",
    [string]$FlashAddress = "0x08000000"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-BuildDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [string]$RequestedConfiguration
    )

    $configurations = @()
    if ($RequestedConfiguration) {
        $configurations += $RequestedConfiguration
    } else {
        $configurations += "Debug", "Release"
    }

    foreach ($name in $configurations) {
        $candidate = Join-Path $Root $name
        $makefile = Join-Path $candidate "makefile"
        if (Test-Path -LiteralPath $makefile -PathType Leaf) {
            return [pscustomobject]@{
                Name = $name
                Path = (Resolve-Path -LiteralPath $candidate).Path
                Makefile = (Resolve-Path -LiteralPath $makefile).Path
            }
        }
    }

    throw "No generated STM32CubeIDE build directory was found under '$Root'. Expected Debug/makefile or Release/makefile."
}

function Add-CandidatePath {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IList]$List,
        [string]$Path
    )

    if (-not $Path) {
        return
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        if (-not $List.Contains($resolved)) {
            $List.Add($resolved)
        }
    }
}

function Find-OpenOcdExecutable {
    param(
        [string]$RequestedPath
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    Add-CandidatePath -List $candidates -Path $RequestedPath
    Add-CandidatePath -List $candidates -Path "D:\tools\xpack-openocd-0.12.0-7\bin\openocd.exe"

    foreach ($commandName in @("openocd.exe", "openocd")) {
        $found = @(Get-Command $commandName -ErrorAction SilentlyContinue)
        foreach ($item in $found) {
            if ($null -ne $item) {
                Add-CandidatePath -List $candidates -Path $item.Path
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No OpenOCD executable was found. Install OpenOCD or pass -OpenOcdPath explicitly."
    }

    return $candidates[0]
}

function Get-BuildArtifactName {
    param(
        [Parameter(Mandatory)]
        [string]$MakefilePath
    )

    foreach ($line in (Get-Content -LiteralPath $MakefilePath)) {
        if ($line -match "^BUILD_ARTIFACT_NAME :=\s*(.+)$") {
            return $Matches[1].Trim()
        }
    }

    throw "Could not determine BUILD_ARTIFACT_NAME from $MakefilePath."
}

$projectRootPath = Resolve-Directory -Path $ProjectRoot -Label "Project root"
$buildInfo = Get-BuildDirectory -Root $projectRootPath -RequestedConfiguration $Configuration
$openOcdExecutable = Find-OpenOcdExecutable -RequestedPath $OpenOcdPath
$artifactName = Get-BuildArtifactName -MakefilePath $buildInfo.Makefile
$binPath = if ($FirmwarePath) {
    if ([System.IO.Path]::IsPathRooted($FirmwarePath)) {
        $FirmwarePath
    } else {
        Join-Path $projectRootPath $FirmwarePath
    }
} else {
    Join-Path $buildInfo.Path ($artifactName + ".bin")
}

Write-Host "Project root : $projectRootPath"
Write-Host "Configuration: $($buildInfo.Name)"
Write-Host "OpenOCD      : $openOcdExecutable"

if (-not (Test-Path -LiteralPath $binPath -PathType Leaf)) {
    throw "Firmware binary was not found: $binPath. Run the build skill first or pass -FirmwarePath explicitly."
}

$firmware = Get-Item -LiteralPath $binPath
Write-Host "Firmware     : $($firmware.FullName)"
Write-Host "Firmware size: $($firmware.Length) bytes"

$openOcdFirmwarePath = $firmware.FullName.Replace("\", "/")
$programCommand = "program `"$openOcdFirmwarePath`" verify reset exit $FlashAddress"

& $openOcdExecutable "-f" $InterfaceConfig "-c" "transport select $Transport" "-f" $TargetConfig "-c" $programCommand
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Flash completed successfully."
