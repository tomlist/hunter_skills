---
name: vscode-cpp-tag
description: Generate VS Code C/C++ extension configuration (c_cpp_properties.json and settings.json) for code navigation, IntelliSense, and go-to-definition. Supports STM32CubeIDE, HAL/CMSIS, Makefile, CMake, and compile_commands.json projects. Usage: /vscode-cpp-tag [project-dir=<subdir>] [dry-run]
---

Create or update `.vscode/c_cpp_properties.json` and `.vscode/settings.json` so VS Code's C/C++ extension can resolve headers, macros, and function definitions. Follow these steps:

## 1. Parse arguments

- `project-dir=<subdir>` or `--project-dir <subdir>` → pass `--project-dir <subdir>` to the script
- `dry-run` or `--dry-run` → pass `--dry-run` (print planned config without writing files)

## 2. Verify workspace

Check that the current directory looks like a C/C++ workspace by looking for any of:
- `.cproject`, `.ioc`, `compile_commands.json`, `CMakeLists.txt`, `Makefile`
- Any `*.c`, `*.h`, `*.cpp`, `*.hpp` files

If none are found, tell the user and stop.

## 3. Run the script

```
python "C:\Users\tomli\.claude\skills\vscode-cpp-tag\scripts\generate_vscode_cpp_config.py" --workspace "<cwd>" [flags]
```

Use the Bash tool to run this. Add `--project-dir` or `--dry-run` as needed.

## 4. Report results

Show the key output lines:
- Detected project type (STM32CubeIDE, CMake, Makefile, etc.)
- Project directory
- Compiler path found
- Number of include paths and defines
- Files written

If the script exits with an error, show the message so the user can fix the issue (e.g., missing project signals).

## Notes

- The script merges into existing `.vscode/settings.json` — unrelated user settings are preserved.
- It replaces or inserts only the generated configuration entry in `c_cpp_properties.json`.
- ARM toolchain is auto-discovered from `C:\ST\STM32CubeCLT_*`, `C:\ST\STM32CubeIDE_*`, or PATH.
- Use `dry-run` to preview what would be written before committing.
- If the script cannot infer enough information, manually set `includePath`, `defines`, and `compilerPath` in `.vscode/c_cpp_properties.json` based on the build system flags.
