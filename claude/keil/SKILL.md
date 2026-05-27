---
name: keil
description: Build and flash Keil MDK projects. Usage: /keil [build|rebuild|flash|build-flash|rebuild-flash] [project=<name>] [clone]
---

You are helping the user build and/or flash Keil MDK (uVision) firmware. Follow these steps:

## 1. Parse arguments

The user may pass arguments after `/keil`. Recognised keywords (case-insensitive):

**Actions** (pick one):
- `build` — incremental build (default if no action specified)
- `rebuild` — clean rebuild (recompile all files)
- `flash` — flash prebuilt firmware only (no build)
- `build-flash` — build then flash
- `rebuild-flash` — clean rebuild then flash

**Options**:
- `clone` — copy the build/flash script (`do.ps1`) to the current working directory, then stop
- `project=<name>` — specify project by filename (without extension) when multiple Keil projects exist
  - Matches `.uvprojx` or `.uvproj` files containing `<name>` in the filename

## 2. Handle clone

If the user passed `clone`, create the build/flash script in the current working directory and stop.

Create `do.ps1` using the Write tool with the template shown in step 5 (Ensure do.ps1 exists). The template contains `<REL_PROJ_PATH>` and `<TARGET_NAME>` placeholders — since the user will fill these in later, keep the placeholders as-is. Do not proceed to build or flash.

Report the created file path to the user and remind them to:
- Edit `<REL_PROJ_PATH>` to point to their Keil project file
- Edit `<TARGET_NAME>` to match their Keil project target

## 3. Locate the Keil project

Search the current working directory (recursively) for `*.uvprojx` and `*.uvproj` files using the Glob tool.

- If **none found**: tell the user and stop.
- If **one found**: use it directly.
- If **multiple found** and **no `project=` specified**: ask the user which one with AskUserQuestion.
- If **multiple found** and **`project=<name>` specified**: pick the one whose filename contains `<name>` (case-insensitive match). If no match or ambiguous, ask the user.

Let `$projFile` = the absolute path to the project file.
Let `$repoRoot` = the current working directory (where the user invoked the skill).

## 4. Extract the target name

Read the project file and find the first `<TargetName>` element. Use that string as `$target`.

## 5. Ensure do.ps1 exists in $repoRoot

Check whether `do.ps1` exists in `$repoRoot`.

If it does **not** exist, create it with the Write tool using the template below.
Substitute the actual relative path from `$repoRoot` to `$projFile` for `<REL_PROJ_PATH>`,
and the actual target name for `<TARGET_NAME>`.

```powershell
param(
    [switch]$Flash,     # -Flash: build then flash firmware to target
    [switch]$Rebuild    # -Rebuild: clean build (rebuild all files)
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
    if ($rc -eq 0) {
        Write-Host "[OK] Build succeeded."
    } elseif ($rc -eq 1) {
        Write-Host "[WARN] Build succeeded with warnings."
    } else {
        Write-Host "[FAIL] Build failed (exit code $rc)."
        exit $rc
    }
}

# ── Build ────────────────────────────────────────────────────────────────────
$BuildFlag = if ($Rebuild) { "-r" } else { "-b" }
$Action    = if ($Rebuild) { "Rebuild" } else { "Build  " }

Write-Host "$Action : $Proj"
Write-Host "Target  : $Target"
Write-Host ""

$rc = Invoke-UV4 "$BuildFlag `"$Proj`" -t `"$Target`" -o `"$Log`" -j0"

if (Test-Path $Log) { Get-Content $Log; Write-Host "" }

Show-Result $rc

# ── Flash ────────────────────────────────────────────────────────────────────
if ($Flash) {
    Write-Host ""
    Write-Host "Flashing firmware to target..."

    $rc = Invoke-UV4 "-f `"$Proj`" -t `"$Target`" -j0"

    if ($rc -eq 0) {
        Write-Host "[OK] Flash succeeded."
    } else {
        Write-Host "[FAIL] Flash failed (exit code $rc). Check debug adapter connection."
        exit $rc
    }
}
```

## 6. Run do.ps1

Use the Bash tool to run:

```
powershell -ExecutionPolicy Bypass -File "<repoRoot>/do.ps1" [flags]
```

Where `[flags]` depends on the action:
| Action | Flags |
|--------|-------|
| `build` | (none) |
| `rebuild` | `-Rebuild` |
| `flash` | `-Flash` |
| `build-flash` | `-Flash` |
| `rebuild-flash` | `-Rebuild -Flash` |

## 7. Report results

Show the key lines from the output (especially errors/warnings) and the final `[OK]`/`[WARN]`/`[FAIL]` status. If flashing failed, remind the user to check debug adapter connection.

## Notes

- UV4.exe is at `C:\Keil_v5\UV4\UV4.exe` on this machine (discovered via registry key `HKLM\SOFTWARE\WOW6432Node\Keil\Products\MDK`, value `Path`).
- `-j0` flag suppresses the UV4 GUI window (essential for headless builds).
- UV4 exit codes: 0 = success, 1 = warnings only, >=2 = errors.
- `cmd /c` is required to capture the exit code from UV4.exe (a GUI executable); `$LASTEXITCODE` is not reliably set when calling GUI exes directly from PowerShell.
- Flash (`-f`) requires a debug adapter (ST-Link, J-Link, ULINK, etc.) connected to the target board.
- Supports both `.uvprojx` (MDK5) and `.uvproj` (MDK4) project files.
- Default action is `build` (incremental build, no flash).
