<#
.SYNOPSIS
CLI for TokenTool with folder/file selection, filter, recursion, preview, and mapping output.

.DESCRIPTION
- Accepts file or folder paths (including via pipeline) and filters with optional recursion.
- Validates and previews regex matches (40 per page) before tokenization if -Preview is set.
- Never executes file contents; reads as text only. Skips binary/invalid text.
- Writes tokenized copies prefixed with timestamp by default; supports -InPlace overwrite.
- Writes per-file mapping (JSON or CSV) for rehydration.
- Logs to file and console using Logger.psm1.

.EXAMPLE
# Tokenize all .txt files in folder with EMAIL and TFN patterns; preview matches
pwsh -File .\scripts\TokenTool.ps1 -Path .\in -Filter *.txt -RegexPrefix EMAIL,TFN -LibraryPath .\data\regexlibrary.json -Preview

.EXAMPLE
# Overwrite in place, include recursion
pwsh -File .\scripts\TokenTool.ps1 -Path .\in -Filter *.* -Recurse -RegexPrefix EMAIL -LibraryPath .\data\regexlibrary.json -InPlace

.EXAMPLE
# Add a custom regex and run
pwsh -File .\scripts\TokenTool.ps1 -Path .\in -Filter *.csv -RegexPrefix CUSTOM -CustomRegex @{Prefix='CUSTOM';Pattern='\bABC-\d{3}\b';Description='Custom code'} -LibraryPath .\data\regexlibrary.json
#>

[CmdletBinding()]
param(
    [string]$Path,
    [string]$Filter = '*.*',
    [switch]$Recurse,

    [Parameter(Mandatory)][string[]]$RegexPrefix,

    [Object[]]$CustomRegex,

    [Parameter(Mandatory)][string]$LibraryPath = "$PSScriptRoot\..\data\regexlibrary.json",

    [switch]$InPlace,

    [ValidateSet('json','csv')][string]$MappingFormat = 'json',

    [switch]$Preview
)

Import-Module "$PSScriptRoot\..\src\Logger.psm1" -Force
Import-Module "$PSScriptRoot\..\src\TokenTool.psm1" -Force

Write-Log "CLI started | Path=$($Path) | Filter=$($Filter) | Recurse=$($Recurse) | Prefixes=$($RegexPrefix -join ', ') | InPlace=$($InPlace) | Mapping=$($MappingFormat) | Preview=$($Preview)" -Level "Info"

$exitCode = 0
try {
    $files = @()
    if ($Path) {
        $files = Get-FilesToProcess -Path $Path -Filter $Filter -Recurse:$Recurse
    } else {
        # Read from pipeline
        $inputItems = @($input)
        foreach ($itm in $inputItems) {
            $p = $null
            if ($itm -is [System.IO.FileInfo] -or $itm -is [System.IO.DirectoryInfo]) { $p = $itm.FullName }
            else { $p = [string]$itm }
            if ($p) { $files += (Get-FilesToProcess -Path $p -Filter $Filter -Recurse:$Recurse) }
        }
    }

    if (-not $files -or $files.Count -eq 0) {
        Write-Log "No files matched selection." -Level "Warning"
        Write-Warning "No files matched selection."
        exit 2
    }

    $total = $files.Count
    $i = 0
    $errorCount = 0

    foreach ($file in $files) {
        $i++
        $pct = [int](($i / $total) * 100)
        Write-Progress -Activity "Tokenizing files" -Status "Processing $i of $total" -PercentComplete $pct

        try {
            $summary = Invoke-TokenTool -Path $file -Filter '*.*' -RegexPrefix $RegexPrefix -CustomRegex $CustomRegex -LibraryPath $LibraryPath -InPlace:$InPlace -MappingFormat $MappingFormat -Preview:$Preview
            Write-Log ("Processed: {0} | Output: {1} | Mapping: {2} | Matches: {3}" -f $summary.File, $summary.Output, $summary.MappingFile, $summary.Matches) -Level "Info"
        } catch {
            $errorCount++
            $msg = "Error processing $($file): $($_.Exception.Message)"
            Write-Error $msg
            Write-Log $msg -Level "Error"
        }
    }
    Write-Progress -Activity "Tokenizing files" -Completed
    Write-Log "Complete. Files=$($total) Errors=$($errorCount) InPlace=$($InPlace)" -Level "Success"
    if ($errorCount -gt 0) { $exitCode = 1 }
} catch {
    $exitCode = 3
    $fatal = "Fatal CLI error: $($_.Exception.Message)"
    Write-Error $fatal
    Write-Log $fatal -Level "Error"
} finally {
    exit $exitCode
}
