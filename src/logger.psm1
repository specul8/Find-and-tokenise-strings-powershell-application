<#
.SYNOPSIS
Structured logging with rotation, retention, and console/GUI forwarding.

.DESCRIPTION
Provides Write-Log for all modules. Logs to a rolling file and writes to the console.
GUI scripts can subscribe a callback via Set-LogGuiSink to mirror messages in a UI bar.
Uses size-based rotation and age-based retention. Supports Info, Warning, Error, Debug, Success.

.VARIABLES
$Global:TokenToolDebugMode (bool) - when $true, Debug messages are emitted to console/GUI.

.EXAMPLE
$Global:TokenToolDebugMode = $true
Write-Log "Debug enabled" -Level "Debug"

.EXAMPLE
Write-Log "Processing started" -Level "Info"
#>

Set-StrictMode -Version Latest

$Global:TokenToolDebugMode = $false
$Global:TokenToolLogPath = "$PSScriptRoot\tokentool.log"
$Global:TokenToolMaxLogSizeMB = 10
$Global:TokenToolRetentionDays = 7

# Optional GUI sink callback: a scriptblock that takes (Level, Message, Timestamp)
$script:GuiSink = $null

function Set-LogGuiSink {
<#
.SYNOPSIS
Registers a GUI sink callback to mirror log messages in the UI.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$Callback
    )
    $script:GuiSink = $Callback
}

function Write-Log {
<#
.SYNOPSIS
Writes a structured log entry to file and console, and optionally to GUI.

.PARAMETER Message
The message to log.

.PARAMETER Level
One of Info, Warning, Error, Debug, Success.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Warning", "Error", "Debug", "Success")]
        [string]$Level = "Info"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $logLine = "[$Level] $timestamp - $Message"

    Invoke-LogRotation
    Remove-OldLogEntries

    try {
        Add-Content -Path $Global:TokenToolLogPath -Value $logLine -Encoding UTF8
    } catch {
        # Best-effort fallback
        Write-Host "[$Level] $timestamp - FILE LOGGING FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    $writeToConsole = $true
    if ($Level -eq "Debug" -and -not $Global:TokenToolDebugMode) {
        $writeToConsole = $false
    }

    if ($writeToConsole) {
        switch ($Level) {
            "Error"   { Write-Host $logLine -ForegroundColor Red }
            "Warning" { Write-Host $logLine -ForegroundColor Yellow }
            "Debug"   { Write-Host $logLine -ForegroundColor DarkGray }
            "Success" { Write-Host $logLine -ForegroundColor Green }
            default   { Write-Host $logLine -ForegroundColor White }
        }
    }

    if ($script:GuiSink) {
        & $script:GuiSink $Level $Message $timestamp
    }
}

function Invoke-LogRotation {
<#
.SYNOPSIS
Performs size-based log rotation when the active log exceeds the configured size.
#>
    if (Test-Path $Global:TokenToolLogPath) {
        $sizeMB = (Get-Item $Global:TokenToolLogPath).Length / 1MB
        if ($sizeMB -ge $Global:TokenToolMaxLogSizeMB) {
            $backupPath = "$Global:TokenToolLogPath.$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
            try {
                if (Test-Path $backupPath) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
                Rename-Item $Global:TokenToolLogPath -NewName (Split-Path -Leaf $backupPath) -Force
                Write-Host "[Info] Log rotated: backup created at $backupPath" -ForegroundColor Cyan
            } catch {
                Write-Host "[Warning] Log rotation failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    } else {
        try {
            New-Item -ItemType File -Path $Global:TokenToolLogPath -Force | Out-Null
        } catch {
            Write-Host "[Error] Unable to create log file at $Global:TokenToolLogPath: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Remove-OldLogEntries {
<#
.SYNOPSIS
Removes log entries older than the configured retention period from the active log.
#>
    if (-not (Test-Path $Global:TokenToolLogPath)) { return }

    $cutoff = (Get-Date).AddDays(-$Global:TokenToolRetentionDays)
    $lines = Get-Content -LiteralPath $Global:TokenToolLogPath -ErrorAction SilentlyContinue
    if (-not $lines) { return }

    $filtered = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        # Match: [Level] yyyy-MM-dd HH:mm:ss.fff - Message
        if ($line -match '^

\[\w+\]

\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s+-\s+') {
            $logDate = $null
            [void][DateTime]::TryParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null, 0, [ref]$logDate)
            if ($logDate -and $logDate -ge $cutoff) {
                [void]$filtered.Add($line)
            }
        } else {
            # Keep lines that don't match the header pattern
            [void]$filtered.Add($line)
        }
    }

    try {
        Set-Content -LiteralPath $Global:TokenToolLogPath -Value $filtered -Encoding UTF8
    } catch {
        Write-Host "[Warning] Unable to apply log retention: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Export-ModuleMember -Function Write-Log, Set-LogGuiSink
