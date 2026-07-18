Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ports = @(Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Sort-Object DeviceID)

if ($ports.Count -eq 0) {
    Write-Host "No serial ports were detected."
    exit 0
}

$ports | Select-Object DeviceID, Name, Description, PNPDeviceID | Format-Table -AutoSize
