#!/usr/bin/env bash
set -euo pipefail

# Defaults
CONFIG="Debug"
CLEAN=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -Config)       CONFIG="$2"; shift ;;
        -Clean)        CLEAN=true ;;
        -DryRun)       DRY_RUN=true ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: do.sh [-Config Debug|Release] [-Clean] [-DryRun]"
            exit 1
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
BUILD_SCRIPT="$SCRIPTS_DIR/build-elf.ps1"
GEN_SCRIPT="$SCRIPTS_DIR/gen-stm32-header.ps1"
FIND_SCRIPT="$SCRIPTS_DIR/find-toolchain.ps1"

DRY_FLAG=""
if $DRY_RUN; then DRY_FLAG="-DryRun"; fi

echo "=== stm32mp135_build_flash (Linux) ==="
echo "Project root : $SCRIPT_DIR"
echo "Config       : $CONFIG"
echo ""

# Auto-discover build directory
BUILD_DIR=""
for candidate in "Application/$CONFIG" "$CONFIG"; do
    if [ -f "$SCRIPT_DIR/$candidate/makefile" ]; then
        BUILD_DIR="$SCRIPT_DIR/$candidate"
        break
    fi
done

if [ -z "$BUILD_DIR" ]; then
    echo "No STM32CubeIDE build directory found."
    echo "Expected $CONFIG/makefile under '$SCRIPT_DIR/Application' or '$SCRIPT_DIR'."
    if ! $DRY_RUN; then exit 1; fi
    echo "[DryRun] Would exit with error."
    exit 0
fi

# Parse artifact name from makefile
ARTIFACT_NAME=$(grep -oP '^BUILD_ARTIFACT_NAME\s*:?=\s*\K.*' "$BUILD_DIR/makefile" | head -1 | tr -d '[:space:]')
ARTIFACT_EXT=$(grep -oP '^BUILD_ARTIFACT_EXTENSION\s*:?=\s*\K.*' "$BUILD_DIR/makefile" | head -1 | tr -d '[:space:]')
ARTIFACT_NAME="${ARTIFACT_NAME:-project}"
ARTIFACT_EXT="${ARTIFACT_EXT:-elf}"
ELF_PATH="$BUILD_DIR/$ARTIFACT_NAME.$ARTIFACT_EXT"
STM32_PATH="$BUILD_DIR/$ARTIFACT_NAME.stm32"

echo "Build dir    : $BUILD_DIR"
echo "ELF          : $ELF_PATH"
echo "STM32        : $STM32_PATH"
echo ""

# Step 1: Build
echo "--- Build ---"
BUILD_ARGS=("-RepoRoot" "$SCRIPT_DIR" "-Config" "$CONFIG")
if $CLEAN; then BUILD_ARGS+=("-Clean"); fi
if $DRY_RUN; then BUILD_ARGS+=("-DryRun"); fi

pwsh -ExecutionPolicy Bypass -File "$BUILD_SCRIPT" "${BUILD_ARGS[@]}"
echo ""

# Step 2: Generate .stm32 header
echo "--- Generate STM32 header ---"
GEN_ARGS=("-ElfPath" "$ELF_PATH")
if $DRY_RUN; then GEN_ARGS+=("-DryRun"); fi

pwsh -ExecutionPolicy Bypass -File "$GEN_SCRIPT" "${GEN_ARGS[@]}"
echo ""

echo "Build completed (Linux: flash not supported)."
echo "STM32 image: $STM32_PATH"
echo ""
echo "To flash, copy $STM32_PATH to a Windows machine and run:"
echo "  pwsh scripts/flash-target.ps1 -ImagePath $STM32_PATH -Port USB1"
exit 0
