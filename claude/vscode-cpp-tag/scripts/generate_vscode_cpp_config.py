#!/usr/bin/env python3
"""Generate VS Code C/C++ navigation settings for C/C++ workspaces."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable


C_EXTENSIONS = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"}


def normalize_slashes(value: str) -> str:
    return value.replace("\\", "/")


def unique(values: Iterable[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        if value and value not in seen:
            seen.add(value)
            result.append(value)
    return result


def is_under(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def format_path(path: Path, workspace: Path) -> str:
    path = path.resolve()
    workspace = workspace.resolve()
    if is_under(path, workspace):
        rel = path.relative_to(workspace)
        rel_text = normalize_slashes(rel.as_posix())
        if rel_text == ".":
            return "${workspaceFolder}"
        return "${workspaceFolder}/" + rel_text
    return normalize_slashes(str(path))


def strip_quotes(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def find_build_dir(project_dir: Path) -> Path | None:
    for name in ("Debug", "Release", "build"):
        candidate = project_dir / name
        if candidate.exists():
            return candidate
    return None


def resolve_include_path(raw: str, workspace: Path, project_dir: Path, build_dir: Path | None) -> str:
    raw = strip_quotes(raw)
    raw = raw.replace("${workspace_loc:/${ProjName}", "")
    raw = raw.replace("${ProjName}", project_dir.name)
    raw = raw.replace("}", "")

    if raw.startswith("${workspaceFolder}"):
        return normalize_slashes(raw)

    raw_path = Path(raw)
    if raw_path.is_absolute():
        return format_path(raw_path, workspace)

    bases: list[Path] = []
    if build_dir is not None:
        bases.append(build_dir)
    bases.extend([project_dir, workspace])

    candidates = [(base / raw_path).resolve() for base in bases]
    for candidate in candidates:
        if candidate.exists():
            return format_path(candidate, workspace)
    return format_path(candidates[0], workspace)


def contains_cpp_sources(path: Path) -> bool:
    ignored = {".git", ".vscode", "Debug", "Release", "build", ".settings"}
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in ignored]
        if any(Path(name).suffix.lower() in C_EXTENSIONS for name in files):
            return True
    return False


def project_signals(path: Path) -> bool:
    known_files = [".cproject", ".ioc", "compile_commands.json", "CMakeLists.txt", "Makefile", "makefile"]
    return any((path / name).exists() for name in known_files) or contains_cpp_sources(path)


def detect_project_dir(workspace: Path, explicit_project_dir: str | None) -> tuple[Path, str]:
    if explicit_project_dir:
        project_dir = (workspace / explicit_project_dir).resolve()
        if not project_dir.exists():
            raise SystemExit(f"project directory does not exist: {project_dir}")
        if not project_signals(project_dir):
            raise SystemExit(f"project directory is not recognized as C/C++: {project_dir}")
        return project_dir, detect_kind(project_dir)

    preferred_child = find_preferred_child_project(workspace)
    if preferred_child is not None:
        return preferred_child, detect_kind(preferred_child)

    if project_signals(workspace):
        return workspace, detect_kind(workspace)

    for child in sorted(p for p in workspace.iterdir() if p.is_dir()):
        if project_signals(child):
            return child, detect_kind(child)

    raise SystemExit(
        "not a C/C++ project: missing .cproject, .ioc, compile_commands.json, "
        "CMakeLists.txt, Makefile, or C/C++ source/header files"
    )


def find_preferred_child_project(workspace: Path) -> Path | None:
    strong_markers = [".cproject", ".ioc", "compile_commands.json", "CMakeLists.txt"]
    for child in sorted(p for p in workspace.iterdir() if p.is_dir()):
        if child.name in {".git", ".vscode", ".settings", "Debug", "Release", "build"}:
            continue
        for marker in strong_markers:
            if marker == ".ioc":
                if any(child.glob("*.ioc")):
                    return child
            elif (child / marker).exists():
                return child
    return None


def detect_kind(project_dir: Path) -> str:
    if (project_dir / ".cproject").exists() or any(project_dir.glob("*.ioc")):
        return "STM32CubeIDE"
    if find_compile_commands(project_dir):
        return "compile_commands"
    if (project_dir / "CMakeLists.txt").exists():
        return "CMake"
    if (project_dir / "Makefile").exists() or (project_dir / "makefile").exists():
        return "Makefile"
    return "C/C++"


def parse_cproject(project_dir: Path, workspace: Path, build_dir: Path | None) -> tuple[list[str], list[str]]:
    cproject = project_dir / ".cproject"
    includes: list[str] = []
    defines: list[str] = []
    if not cproject.exists():
        return includes, defines

    root = ET.parse(cproject).getroot()
    for option in root.iter("option"):
        value_type = option.attrib.get("valueType", "")
        option_id = option.attrib.get("id", "") + " " + option.attrib.get("superClass", "")
        values = [child.attrib.get("value", "") for child in option.findall("listOptionValue")]
        if value_type == "includePath" or "includepaths" in option_id:
            includes.extend(resolve_include_path(value, workspace, project_dir, build_dir) for value in values)
        elif value_type == "definedSymbols" or "definedsymbols" in option_id:
            defines.extend(value for value in values if value)
    return unique(includes), unique(defines)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def parse_make_metadata(project_dir: Path, workspace: Path, build_dir: Path | None) -> tuple[list[str], list[str], list[str], str | None]:
    includes: list[str] = []
    defines: list[str] = []
    compiler_args: list[str] = []
    c_standard: str | None = None

    roots = [build_dir] if build_dir is not None else []
    roots.append(project_dir)
    makefiles: list[Path] = []
    for root in roots:
        if root and root.exists():
            makefiles.extend(root.rglob("*.mk"))
            for name in ("makefile", "Makefile"):
                if (root / name).exists():
                    makefiles.append(root / name)

    for makefile in unique(str(path) for path in makefiles):
        makefile_path = Path(makefile)
        base_dir = build_dir if build_dir is not None and is_under(makefile_path, build_dir) else makefile_path.parent
        text = read_text(makefile_path)
        for value in re.findall(r"(?:^|\s)-I\s*(\"[^\"]+\"|'[^']+'|\S+)", text):
            includes.append(resolve_include_path(value, workspace, project_dir, base_dir))
        for value in re.findall(r"(?:^|\s)-D\s*([A-Za-z_][A-Za-z0-9_]*(?:=[^\s]+)?)", text):
            defines.append(value)
        for value in re.findall(r"(-mcpu=\S+|-mthumb|-mfloat-abi=\S+|--specs=\S+)", text):
            compiler_args.append(strip_quotes(value))
        std_match = re.search(r"-std=(gnu\d+|c\d+|gnu\+\+\d+|c\+\+\d+)", text)
        if std_match:
            c_standard = std_match.group(1)

    return unique(includes), unique(defines), unique(compiler_args), c_standard


def find_compile_commands(project_dir: Path) -> Path | None:
    candidates = [
        project_dir / "compile_commands.json",
        project_dir / "build" / "compile_commands.json",
        project_dir / "Debug" / "compile_commands.json",
        project_dir / "Release" / "compile_commands.json",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def fallback_include_paths(project_dir: Path, workspace: Path) -> list[str]:
    candidates = [
        project_dir,
        project_dir / "include",
        project_dir / "inc",
        project_dir / "src",
        project_dir / "Core" / "Inc",
        project_dir / "Drivers" / "STM32F1xx_HAL_Driver" / "Inc" / "Legacy",
        project_dir / "Drivers" / "STM32F1xx_HAL_Driver" / "Inc",
        project_dir / "Drivers" / "CMSIS" / "Device" / "ST" / "STM32F1xx" / "Include",
        project_dir / "Drivers" / "CMSIS" / "Include",
    ]
    existing = [format_path(path, workspace) for path in candidates if path.exists()]
    if existing:
        return unique(existing)
    return [format_path(project_dir, workspace) + "/**"]


def infer_browse_paths(project_dir: Path, workspace: Path) -> list[str]:
    candidates = [project_dir, project_dir / "Core", project_dir / "Drivers", project_dir / "src", project_dir / "include"]
    return unique(format_path(path, workspace) for path in candidates if path.exists())


def find_arm_gcc() -> str | None:
    for tool in ("arm-none-eabi-gcc.exe", "arm-none-eabi-gcc"):
        found = shutil.which(tool)
        if found:
            return normalize_slashes(found)

    st_root = Path("C:/ST")
    if st_root.exists():
        patterns = [
            "STM32CubeIDE_*/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32*/tools/bin/arm-none-eabi-gcc.exe",
            "STM32CubeCLT_*/GNU-tools-for-STM32/bin/arm-none-eabi-gcc.exe",
        ]
        for pattern in patterns:
            matches = sorted(st_root.glob(pattern), reverse=True)
            if matches:
                return normalize_slashes(str(matches[0]))

    found = shutil.which("gcc")
    return normalize_slashes(found) if found else None


def choose_c_standard(value: str | None) -> str:
    if value and value.startswith("gnu"):
        return value
    if value and value.startswith("c"):
        return value
    return "gnu11"


def load_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def merge_settings(settings_path: Path, compile_commands_value: str | None) -> dict:
    settings = load_json(settings_path, {})
    files_associations = settings.setdefault("files.associations", {})
    files_associations.update(
        {
            "stm32f1xx_hal.h": "c",
            "stm32f1xx.h": "c",
            "main.h": "c",
        }
    )

    files_exclude = settings.setdefault("files.exclude", {})
    files_exclude.update(
        {
            "**/.git": True,
            "**/.settings": True,
            "**/Debug/**/*.cyclo": True,
            "**/Debug/**/*.d": True,
            "**/Debug/**/*.list": True,
            "**/Debug/**/*.map": True,
            "**/Debug/**/*.o": True,
            "**/Debug/**/*.su": True,
            "**/Release/**/*.cyclo": True,
            "**/Release/**/*.d": True,
            "**/Release/**/*.o": True,
            "**/Release/**/*.su": True,
        }
    )

    search_exclude = settings.setdefault("search.exclude", {})
    search_exclude.update({"**/Debug": True, "**/Release": True})

    settings["C_Cpp.default.configurationProvider"] = ""
    settings["C_Cpp.errorSquiggles"] = "enabled"
    settings["C_Cpp.intelliSenseEngine"] = "default"
    settings["C_Cpp.default.compileCommands"] = compile_commands_value or ""
    return settings


def update_cpp_properties(path: Path, config: dict) -> dict:
    data = load_json(path, {"version": 4, "configurations": []})
    data["version"] = 4
    configs = data.setdefault("configurations", [])
    for index, existing in enumerate(configs):
        if existing.get("name") == config["name"]:
            configs[index] = config
            break
    else:
        configs.insert(0, config)
    return data


def build_config(workspace: Path, project_dir: Path, kind: str) -> tuple[dict, str | None, dict]:
    build_dir = find_build_dir(project_dir)
    cproject_includes, cproject_defines = parse_cproject(project_dir, workspace, build_dir)
    make_includes, make_defines, make_args, c_standard = parse_make_metadata(project_dir, workspace, build_dir)
    compile_commands = find_compile_commands(project_dir)

    includes = unique(cproject_includes + make_includes)
    if not includes and compile_commands is None:
        includes = fallback_include_paths(project_dir, workspace)

    defines = unique(cproject_defines + make_defines)
    compiler_path = find_arm_gcc()

    name = f"{project_dir.name} {kind}".strip()
    config = {
        "name": name,
        "intelliSenseMode": "gcc-arm" if compiler_path and "arm-none-eabi" in compiler_path else "gcc-x64",
        "cStandard": choose_c_standard(c_standard),
        "cppStandard": "gnu++14",
        "includePath": includes,
        "browse": {
            "path": infer_browse_paths(project_dir, workspace),
            "limitSymbolsToIncludedHeaders": True,
        },
        "defines": defines,
    }

    if compiler_path:
        config["compilerPath"] = compiler_path
    if make_args:
        config["compilerArgs"] = make_args
    if compile_commands:
        config["compileCommands"] = format_path(compile_commands, workspace)

    compile_commands_value = format_path(compile_commands, workspace) if compile_commands else None
    summary = {
        "kind": kind,
        "project_dir": str(project_dir),
        "include_count": len(includes),
        "define_count": len(defines),
        "compiler_path": compiler_path or "",
        "compile_commands": compile_commands_value or "",
    }
    return config, compile_commands_value, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=".", help="workspace root where .vscode should be written")
    parser.add_argument("--project-dir", help="C/C++ project directory relative to workspace")
    parser.add_argument("--dry-run", action="store_true", help="detect and print planned config without writing files")
    args = parser.parse_args()

    workspace = Path(args.workspace).resolve()
    if not workspace.exists():
        raise SystemExit(f"workspace does not exist: {workspace}")

    project_dir, kind = detect_project_dir(workspace, args.project_dir)
    config, compile_commands_value, summary = build_config(workspace, project_dir, kind)

    vscode_dir = workspace / ".vscode"
    cpp_properties_path = vscode_dir / "c_cpp_properties.json"
    settings_path = vscode_dir / "settings.json"

    if args.dry_run:
        print(json.dumps({"summary": summary, "configuration": config}, indent=2, ensure_ascii=False))
        return 0

    cpp_properties = update_cpp_properties(cpp_properties_path, config)
    settings = merge_settings(settings_path, compile_commands_value)
    write_json(cpp_properties_path, cpp_properties)
    write_json(settings_path, settings)

    print(f"Detected       : {summary['kind']}")
    print(f"Project dir    : {summary['project_dir']}")
    print(f"Compiler       : {summary['compiler_path'] or '(not found)'}")
    print(f"Includes       : {summary['include_count']}")
    print(f"Defines        : {summary['define_count']}")
    print(f"Wrote          : {cpp_properties_path}")
    print(f"Wrote          : {settings_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
