param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

$textExtensions = @(
    '.c', '.h', '.H', '.hpp', '.cpp', '.cxx',
    '.txt', '.md', '.yaml', '.yml', '.json', '.xml',
    '.py', '.js', '.ts', '.css', '.html',
    '.ps1', '.bat', '.sh',
    '.A51', '.s', '.S', '.asm', '.inc',
    '.cfg', '.ini', '.log', '.csv'
)

$converted = 0
$skipped   = 0
$errors    = 0

function Convert-FileToUtf8([string]$filePath) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)

        # Skip empty files
        if ($bytes.Length -eq 0) {
            return $false
        }

        # Check for UTF-8 BOM
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            # Already UTF-8 with BOM
            return $false
        }

        # Check for UTF-16 LE BOM
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            return $false
        }

        # Check for UTF-16 BE BOM
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            return $false
        }

        # Try to decode as UTF-8 (without BOM) - if it succeeds without replacement chars, it's already UTF-8
        $utf8 = [System.Text.Encoding]::UTF8
        $text = $utf8.GetString($bytes)

        # Check for replacement characters (0xFFFD) which indicate invalid UTF-8 sequences
        if ($text.IndexOf([char]0xFFFD) -lt 0) {
            # Already valid UTF-8 without BOM, skip
            return $false
        }

        # Has invalid UTF-8 sequences — likely GBK, try GBK decode
        $gbk = [System.Text.Encoding]::GetEncoding(936)  # GBK code page
        $text = $gbk.GetString($bytes)

        # Write back as UTF-8 without BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($filePath, $text, $utf8NoBom)
        return $true
    }
    catch {
        Write-Host "  ERROR: $filePath - $_" -ForegroundColor Red
        return $false
    }
}

function Process-Path([string]$inputPath) {
    if (Test-Path -Path $inputPath -PathType Leaf) {
        # Single file
        $ext = [System.IO.Path]::GetExtension($inputPath)
        if ($textExtensions -contains $ext) {
            if (Convert-FileToUtf8 $inputPath) {
                Write-Host "  UTF-8: $inputPath" -ForegroundColor Green
                $script:converted++
            } else {
                $script:skipped++
            }
        }
    }
    elseif (Test-Path -Path $inputPath -PathType Container) {
        # Directory
        Get-ChildItem -Path $inputPath -Recurse -File | ForEach-Object {
            $ext = $_.Extension
            if ($textExtensions -contains $ext) {
                if (Convert-FileToUtf8 $_.FullName) {
                    Write-Host "  UTF-8: $($_.FullName)" -ForegroundColor Green
                    $script:converted++
                } else {
                    $script:skipped++
                }
            }
        }
    }
    else {
        Write-Host "ERROR: path not found: $inputPath" -ForegroundColor Red
        $script:errors++
    }
}

Process-Path $Path

Write-Host ""
Write-Host "Converted: $converted  Skipped: $skipped  Errors: $errors"
