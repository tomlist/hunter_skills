---
name: utf8-convert
description: Convert text files to UTF-8 encoding. Accepts a file or directory path. If a directory, recursively scans for text files and converts them. Usage: /utf8-convert <file|directory>
---

Convert text files to UTF-8 encoding.

## When to use

- User asks to convert files to UTF-8 encoding
- User mentions "UTF-8", "encoding", "GBK", "garbled Chinese", "乱码", "编码格式"
- After creating or editing files that may have non-UTF-8 encoding

## Steps

1. Parse the argument: the user provides a file path or directory path.
   - If no argument, ask the user which file or directory to convert.

2. Run the conversion script:
   ```
   powershell -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\utf8-convert\scripts\convert-to-utf8.ps1" -Path "<path>"
   ```

3. Report the results: number of files converted, skipped, and any errors.

## How it works

The script:
- Skips files with UTF-8 BOM, UTF-16 BOM, or valid UTF-8 content
- Detects GBK (code page 936) encoded files by the presence of invalid UTF-8 byte sequences
- Converts detected GBK files to UTF-8 without BOM
- Handles common text file extensions: .c .h .H .cpp .txt .md .yaml .json .py .ps1 .A51 .s .asm etc.
