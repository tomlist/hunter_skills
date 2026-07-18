param(
    [string]$ProjectRoot = ".",
    [string]$Configuration,
    [switch]$Clean,
    [ValidateRange(1, 128)]
    [int]$Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
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

function Get-PreferredToolchainVersion {
    param(
        [Parameter(Mandatory)]
        [string]$MakefilePath
    )

    foreach ($line in (Get-Content -LiteralPath $MakefilePath -TotalCount 10)) {
        if ($line -match "GNU Tools for STM32 \(([^)]+)\)") {
            return $Matches[1]
        }
    }

    return $null
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

function Find-MakeExecutable {
    $candidates = [System.Collections.Generic.List[string]]::new()

    Add-CandidatePath -List $candidates -Path "C:\Program Files (x86)\GnuWin32\bin\make.exe"
    Add-CandidatePath -List $candidates -Path "C:\Program Files\GnuWin32\bin\make.exe"

    foreach ($commandName in @("make.exe", "mingw32-make.exe")) {
        $found = @(Get-Command $commandName -ErrorAction SilentlyContinue)
        foreach ($item in $found) {
            if ($null -ne $item) {
                Add-CandidatePath -List $candidates -Path $item.Path
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No compatible make executable was found. Install GnuWin32 make.exe or add it to PATH."
    }

    return $candidates |
        Sort-Object @{
            Expression = {
                $score = 0
                if ($_ -match "GnuWin32") { $score += 100 }
                if ([System.IO.Path]::GetFileName($_) -ieq "make.exe") { $score += 10 }
                -$score
            }
        }, @{ Expression = { $_ } } |
        Select-Object -First 1
}

function Find-ToolchainBin {
    param(
        [string]$PreferredVersion
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    $gccInPath = @(Get-Command "arm-none-eabi-gcc.exe" -ErrorAction SilentlyContinue)
    foreach ($item in $gccInPath) {
        if ($null -ne $item) {
            Add-CandidatePath -List $candidates -Path $item.Path
        }
    }

    if (Test-Path -LiteralPath "C:\ST" -PathType Container) {
        foreach ($clt in (Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeCLT_*" -ErrorAction SilentlyContinue)) {
            Add-CandidatePath -List $candidates -Path (Join-Path $clt.FullName "GNU-tools-for-STM32\bin\arm-none-eabi-gcc.exe")
        }

        foreach ($ide in (Get-ChildItem "C:\ST" -Directory -Filter "STM32CubeIDE_*" -ErrorAction SilentlyContinue)) {
            $pluginsDir = Join-Path $ide.FullName "STM32CubeIDE\plugins"
            if (-not (Test-Path -LiteralPath $pluginsDir -PathType Container)) {
                continue
            }

            foreach ($plugin in (Get-ChildItem $pluginsDir -Directory -Filter "com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32*" -ErrorAction SilentlyContinue)) {
                Add-CandidatePath -List $candidates -Path (Join-Path $plugin.FullName "tools\bin\arm-none-eabi-gcc.exe")
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No arm-none-eabi-gcc toolchain was found. Install STM32CubeCLT or STM32CubeIDE GNU Tools for STM32."
    }

    $selected = $candidates |
        Sort-Object @{
            Expression = {
                $score = 0
                if ($PreferredVersion -and $_ -match [regex]::Escape($PreferredVersion)) { $score += 100 }
                if ($_ -match "STM32CubeCLT") { $score += 10 }
                -$score
            }
        }, @{ Expression = { $_ } } |
        Select-Object -First 1

    return Split-Path -Parent $selected
}

function Get-BuildArtifactPath {
    param(
        [Parameter(Mandatory)]
        [string]$MakefilePath,
        [Parameter(Mandatory)]
        [string]$BuildDirectory
    )

    $artifactName = $null
    $artifactExtension = $null

    foreach ($line in (Get-Content -LiteralPath $MakefilePath)) {
        if (-not $artifactName -and $line -match "^BUILD_ARTIFACT_NAME :=\s*(.+)$") {
            $artifactName = $Matches[1].Trim()
        }
        if (-not $artifactExtension -and $line -match "^BUILD_ARTIFACT_EXTENSION :=\s*(.*)$") {
            $artifactExtension = $Matches[1].Trim()
        }
        if ($artifactName -and $artifactExtension -ne $null) {
            break
        }
    }

    if (-not $artifactName) {
        return $null
    }

    $fileName = $artifactName
    if ($artifactExtension) {
        $fileName = "$artifactName.$artifactExtension"
    }

    return Join-Path $BuildDirectory $fileName
}

function Write-ObjectsList {
    param(
        [Parameter(Mandatory)]
        [string]$BuildDirectory
    )

    $objectPaths = [System.Collections.Generic.List[string]]::new()

    foreach ($subdirMk in (Get-ChildItem -LiteralPath $BuildDirectory -Recurse -Filter "subdir.mk" -File | Sort-Object FullName)) {
        $collecting = $false

        foreach ($line in (Get-Content -LiteralPath $subdirMk.FullName)) {
            $trimmed = $line.Trim()
            if (-not $collecting -and $trimmed -like "OBJS +=*") {
                $collecting = $true
                $trimmed = $trimmed.Substring(7).Trim()
            } elseif (-not $collecting) {
                continue
            }

            $continues = $trimmed.EndsWith("\")
            if ($continues) {
                $trimmed = $trimmed.Substring(0, $trimmed.Length - 1).Trim()
            }

            if ($trimmed) {
                $objectPaths.Add($trimmed)
            }

            if (-not $continues) {
                $collecting = $false
            }
        }
    }

    if ($objectPaths.Count -eq 0) {
        throw "Could not reconstruct objects.list because no OBJS entries were found under $BuildDirectory."
    }

    $objectsListPath = Join-Path $BuildDirectory "objects.list"
    $content = $objectPaths | ForEach-Object { '"' + $_ + '"' }
    Set-Content -LiteralPath $objectsListPath -Value $content -Encoding ascii
    return $objectsListPath
}

function Remove-BuildOutputs {
    param(
        [Parameter(Mandatory)]
        [string]$BuildDirectory
    )

    $targets = @(Get-ChildItem -LiteralPath $BuildDirectory -Recurse -File | Where-Object {
        $_.Name -eq "default.size.stdout" -or
        $_.Extension -in @(".o", ".d", ".su", ".cyclo", ".elf", ".map", ".list")
    })

    if ($targets.Count -eq 0) {
        return
    }

    $targets | Remove-Item -Force
}

$projectRootPath = Resolve-Directory -Path $ProjectRoot -Label "Project root"
$buildInfo = Get-BuildDirectory -Root $projectRootPath -RequestedConfiguration $Configuration
$preferredVersion = Get-PreferredToolchainVersion -MakefilePath $buildInfo.Makefile
$makeExecutable = Find-MakeExecutable
$toolchainBin = Find-ToolchainBin -PreferredVersion $preferredVersion
$artifactPath = Get-BuildArtifactPath -MakefilePath $buildInfo.Makefile -BuildDirectory $buildInfo.Path

if ($Clean) {
    Write-Host "Cleaning generated outputs in $($buildInfo.Path)"
    Remove-BuildOutputs -BuildDirectory $buildInfo.Path
}

if (-not (($env:Path -split ";") -contains $toolchainBin)) {
    $env:Path = "$toolchainBin;$env:Path"
}

$objectsListPath = Write-ObjectsList -BuildDirectory $buildInfo.Path

Write-Host "Project root : $projectRootPath"
Write-Host "Configuration: $($buildInfo.Name)"
Write-Host "Make         : $makeExecutable"
Write-Host "Toolchain    : $toolchainBin"
Write-Host "Objects list : $objectsListPath"
if ($preferredVersion) {
    Write-Host "Requested GNU Tools for STM32 version: $preferredVersion"
}

# Force cmd.exe so the generated makefiles do not pick up an incompatible sh.exe.
& $makeExecutable "SHELL=cmd.exe" "-C" $buildInfo.Path "all" "-j" $Jobs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($artifactPath -and (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    $artifact = Get-Item -LiteralPath $artifactPath
    Write-Host "Artifact     : $($artifact.FullName)"
    Write-Host "Artifact size: $($artifact.Length) bytes"
} else {
    Write-Warning "Build finished but no artifact path could be confirmed from the generated makefile."
}
