param(
    [string]$PortName,
    [int]$BaudRate = 115200,
    [Parameter(Mandatory)]
    [string[]]$Pattern,
    [int]$TimeoutSeconds = 10,
    [int]$MinMatches = 2,
    [switch]$RequireIncreasingLastInteger,
    [int]$ReadTimeoutMilliseconds = 500,
    [switch]$EnableDtr,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-SerialPort {
    param(
        [string]$RequestedPortName
    )

    if ($RequestedPortName) {
        return $RequestedPortName
    }

    $ports = @(Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Sort-Object DeviceID)
    if ($ports.Count -eq 0) {
        throw "No serial ports were detected. Pass -PortName explicitly."
    }

    if ($ports.Count -eq 1) {
        return $ports[0].DeviceID
    }

    $preferred = $ports | Where-Object {
        $_.Name -match "STLink|ST-LINK|Virtual COM|USB Serial|CH340|CP210|CMSIS-DAP"
    } | Select-Object -First 1

    if ($null -ne $preferred) {
        return $preferred.DeviceID
    }

    $names = ($ports | Select-Object -ExpandProperty DeviceID) -join ", "
    throw "Multiple serial ports were detected ($names). Pass -PortName explicitly."
}

function Get-LastInteger {
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    $matches = [regex]::Matches($Line, "-?\d+")
    if ($matches.Count -eq 0) {
        return $null
    }

    return [int64]$matches[$matches.Count - 1].Value
}

$selectedPort = Resolve-SerialPort -RequestedPortName $PortName
$compiledPatterns = @($Pattern | ForEach-Object { [regex]::new($_) })
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$serialPort = [System.IO.Ports.SerialPort]::new($selectedPort, $BaudRate)
$serialPort.NewLine = "`n"
$serialPort.ReadTimeout = $ReadTimeoutMilliseconds
$serialPort.DtrEnable = $EnableDtr.IsPresent
$serialPort.RtsEnable = $false

$capturedLines = [System.Collections.Generic.List[string]]::new()
$matchedLines = [System.Collections.Generic.List[string]]::new()
$matchedTicks = [System.Collections.Generic.List[int64]]::new()

try {
    try {
        $serialPort.Open()
    } catch {
        throw "Failed to open serial port $selectedPort. Confirm the COM port exists and is not occupied by another program."
    }
    $serialPort.DiscardInBuffer()
    Start-Sleep -Milliseconds 200

    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $line = $serialPort.ReadLine()
        } catch [System.TimeoutException] {
            continue
        }

        if ($null -eq $line) {
            continue
        }

        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $capturedLines.Add($line)
        Write-Host $line

        foreach ($regex in $compiledPatterns) {
            if ($regex.IsMatch($line)) {
                $matchedLines.Add($line)

                if ($RequireIncreasingLastInteger) {
                    $lastInteger = Get-LastInteger -Line $line
                    if ($null -eq $lastInteger) {
                        throw "Matched line does not contain an integer for monotonic validation: $line"
                    }
                    $matchedTicks.Add($lastInteger)
                }

                break
            }
        }

        if ($matchedLines.Count -ge $MinMatches) {
            break
        }
    }
}
finally {
    if ($serialPort.IsOpen) {
        $serialPort.Close()
    }
}

if ($LogPath) {
    $capturedLines | Set-Content -LiteralPath $LogPath -Encoding utf8
}

if ($matchedLines.Count -lt $MinMatches) {
    $seen = if ($capturedLines.Count -gt 0) { $capturedLines -join [Environment]::NewLine } else { "<no output captured>" }
    throw "UART verification failed. Expected at least $MinMatches matched lines, got $($matchedLines.Count). Captured output:`n$seen"
}

if ($RequireIncreasingLastInteger) {
    for ($index = 1; $index -lt $matchedTicks.Count; $index++) {
        if ($matchedTicks[$index] -le $matchedTicks[$index - 1]) {
            throw "UART verification failed. The last integer is not strictly increasing across matched lines."
        }
    }
}

Write-Host "UART verification succeeded on $selectedPort."
Write-Host "Matched lines: $($matchedLines.Count)"
