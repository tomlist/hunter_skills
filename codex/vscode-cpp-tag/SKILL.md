---
name: vscode-cpp-tag
description: Generate VS Code C/C++ extension configuration for code navigation, IntelliSense, function jump, and go-to-definition in C/C++ workspaces. Use when the user invokes vscode_cpp_tag or asks to create c_cpp_properties.json, configure VS Code C/C++ include paths/macros, or enable function navigation in C/C++ projects including STM32CubeIDE, STM32 HAL/CMSIS, Makefile, CMake, or compile_commands.json based projects.
---

Create or update `.vscode/c_cpp_properties.json` and `.vscode/settings.json` so VS Code's C/C++ extension can resolve headers, macros, and function definitions.

## 1. Parse arguments

- `project-dir=<subdir>` or `--project-dir <subdir>`: pass `--project-dir <subdir>` to script
- `dry-run` or `--dry-run`: preview without writing

## 2. Verify workspace

Check for C/C++ signals: `.cproject`, `.ioc`, `compile_commands.json`, `CMakeLists.txt`, `Makefile`, or any `*.c`/`*.h`/`*.cpp`/`*.hpp` files. If none: tell user and stop.

## 3. Run the script

```
python "<skill_dir>/scripts/generate_vscode_cpp_config.py" --workspace "<cwd>" [flags]
```

## 4. Report results

Show: detected project type, compiler path, include path count, define count, files written.

## Notes

- Merges into existing `.vscode/settings.json` — preserves user settings.
- Replaces/inserts only generated config in `c_cpp_properties.json`.
- ARM toolchain auto-discovered from `C:\ST\STM32CubeCLT_*`, `C:\ST\STM32CubeIDE_*`, or PATH.
- Use `dry-run` to preview before committing.
