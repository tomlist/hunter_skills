---
name: utf8-convert
description: Convert text files to UTF-8 encoding. Use when user mentions UTF-8, GBK, garbled Chinese, 乱码, 编码格式, or needs to convert files to UTF-8.
---

Convert text files to UTF-8 encoding.

## When to use

- User asks to convert files to UTF-8 encoding
- User mentions "UTF-8", "encoding", "GBK", "garbled Chinese", "乱码", "编码格式"
- After creating or editing files that may have non-UTF-8 encoding

## Steps

1. Parse the argument: the user provides a file path or directory path.
2. Run the conversion script: `powershell -ExecutionPolicy Bypass -File "<skill_dir>/scripts/convert-to-utf8.ps1" -Path "<path>"`
3. Report results: files converted, skipped, and any errors.

The script handles .c .h .H .cpp .txt .md .yaml .json .py .ps1 .A51 .s .asm etc. Skips UTF-8/UTF-16 BOM files. Converts GBK to UTF-8 without BOM.
