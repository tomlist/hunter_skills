---
name: keil
description: Build and flash Keil MDK projects. Use when the user needs to build, rebuild, or flash Keil uVision firmware. Handles project discovery, UV4.exe invocation, and flash via debug adapter.
---

You are helping the user build and/or flash Keil MDK (uVision) firmware. Follow these steps:

## 1. Parse arguments

The user may specify:
- `build`, `rebuild`, `flash`, `build-flash`, `rebuild-flash` (default: build)
- `clone` — copy do.ps1 to cwd and stop
- `project=<name>` — select project when multiple .uvprojx/.uvproj exist

## 2. Handle clone

If clone is requested, create do.ps1 with `<REL_PROJ_PATH>` and `<TARGET_NAME>` placeholders (see template below), tell user to fill them in, and stop.

## 3. Locate the Keil project

Search recursively for `*.uvprojx` and `*.uvproj`. If none: stop. If multiple and no project=: ask user. If project= specified: match case-insensitive.

## 4. Extract target name

Read the first `<TargetName>` element from the project file.

## 5. Ensure do.ps1 exists

If do.ps1 doesn't exist in cwd, create it with the template below, substituting the relative path to the project and target name.

```powershell
param(
    [switch]$Flash,
    [switch]$Rebuild
)

$UV4       = "C:\Keil_v5\UV4\UV4.exe"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Proj      = Join-Path $ScriptDir "<REL_PROJ_PATH>"
$Target    = "<TARGET_NAME>"
$Log       = Join-Path (Split-Path $Proj -Parent) "build.log"

function Invoke-UV4 ([string]$Flags) {
    cmd /c "`"$UV4`" $Flags"
    return $LASTEXITCODE
}

function Show-Result ([int]$rc) {
    if ($rc -eq 0) { Write-Host "[OK] Build succeeded." }
    elseif ($rc -eq 1) { Write-Host "[WARN] Build succeeded with warnings." }
    else { Write-Host "[FAIL] Build failed (exit code $rc)."; exit $rc }
}

$BuildFlag = if ($Rebuild) { "-r" } else { "-b" }
$Action    = if ($Rebuild) { "Rebuild" } else { "Build  " }

Write-Host "$Action : $Proj"
Write-Host "Target  : $Target"
Write-Host ""
$rc = Invoke-UV4 "$BuildFlag `"$Proj`" -t `"$Target`" -o `"$Log`" -j0"
if (Test-Path $Log) { Get-Content $Log; Write-Host "" }
Show-Result $rc

if ($Flash) {
    Write-Host ""
    Write-Host "Flashing firmware to target..."
    $rc = Invoke-UV4 "-f `"$Proj`" -t `"$Target`" -j0"
    if ($rc -eq 0) { Write-Host "[OK] Flash succeeded." }
    else { Write-Host "[FAIL] Flash failed (exit code $rc). Check debug adapter."; exit $rc }
}
```

## 6. Run do.ps1

Run: `powershell -ExecutionPolicy Bypass -File "<cwd>/do.ps1"` with `-Rebuild` and/or `-Flash` as needed.

## 7. Report results

Show key output and final status. If flash fails, remind to check debug adapter.

## Notes

- UV4.exe at `C:\Keil_v5\UV4\UV4.exe` (registry-discovered).
- `-j0` suppresses GUI. Exit codes: 0=ok, 1=warnings, >=2=errors.
- `cmd /c` needed for GUI exe exit code capture.
- Requires debug adapter for flash.
