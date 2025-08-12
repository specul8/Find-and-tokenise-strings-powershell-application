function Read-RegexPreview {
<#
.SYNOPSIS
Validates regexes and presents a paged preview (40 at a time) in the CLI.

.PARAMETER Text
The content to scan.

.PARAMETER SelectedRegexes
Regex objects with Prefix, Pattern.

.OUTPUTS
Hashtable of unique original->token proposed mappings (not applied yet), or $null if cancelled.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][Object[]]$SelectedRegexes
    )

    # Validate all regexes first
    $compiled = @()
    foreach ($r in $SelectedRegexes) {
        try {
            $rx = [Regex]::new($r.Pattern, [RegexOptions]::IgnoreCase)
            $compiled += [pscustomobject]@{ Prefix = $r.Prefix; Regex = $rx }
        } catch {
            Write-Log "Regex validation failed for $($r.Prefix): $($_.Exception.Message)" -Level "Error"
            return $null
        }
    }

    $foundMatches = New-Object System.Collections.Generic.List[object]
    foreach ($c in $compiled) {
        $m = $c.Regex.Matches($Text)
        foreach ($item in $m) {
            $foundMatches.Add([pscustomobject]@{
                Prefix   = $c.Prefix
                Original = [string]$item.Value
            })
        }
    }

    if ($foundMatches.Count -eq 0) {
        Write-Log "No matches found with selected regexes." -Level "Info"
        return @{}
    }

    # Unique originals per prefix
    $map = @{}
    $page = 0
    while ($true) {
        $start = $page * 40
        $end = [Math]::Min($start + 39, $foundMatches.Count - 1)
        if ($start -gt $end) { break }
        $slice = $foundMatches[$start..$end]

        Write-Log "Previewing matches $($start+1)-$($end+1) of $($foundMatches.Count)" -Level "Info"
        foreach ($row in $slice) {
            Write-Host ("[{0}] {1}" -f $row.Prefix, $row.Original)
        }

        $choice = Read-Host "Options: (N)ext 40, (T)okenize, (C)ancel"
        switch ($choice.ToUpperInvariant()) {
            'N' { $page++ ; continue }
            'T' { break }
            'C' { Write-Log "User cancelled during preview." -Level "Warning"; return $null }
            default { Write-Log "Unknown choice '$($choice)'; continuing." -Level "Warning"; $page++ }
        }
    }

    foreach ($row in $foundMatches) {
        if (-not $map.ContainsKey($row.Original)) {
            $map[$row.Original] = Get-DeterministicToken -Prefix $row.Prefix -Value $row.Original
        }
    }
    return $map
}
