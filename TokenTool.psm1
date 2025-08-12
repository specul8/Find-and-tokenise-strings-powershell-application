function Replace-WithToken {
    param (
        [string] $pattern,
        [string] $prefix
    )
    if (-not (Test-FileContentValid -FilePath $InputFile)) {
        Write-Error "Skipping file due to validation failure: $InputFile"
        return
    }
    $text = [regex]::Replace($text, $pattern, {
        $token = "$prefix_" + [guid]::NewGuid().ToString()
        $map[$token] = $_.Value
        return $token
    })
}

function Process-Tokenization {
    param (
        [Parameter(Mandatory=$true)] [string] $sourceFilePath,
        [Parameter(Mandatory=$true)] [string] $targetFilePath,
        [Parameter(Mandatory=$true)] [string] $mappingFilePath,
        [Parameter()] [ValidateSet("json", "csv")] [string] $MappingFormat = "json",
        [Parameter()] [ValidateSet("tokenize", "rehydrate")] [string] $actionType = "tokenize",
        [Parameter()] [switch] $ReplaceEmails,
        [Parameter()] [switch] $ReplaceGuids,
        [Parameter()] [switch] $ReplaceIPs,
        [Parameter()] [switch] $ReplaceCreditCards,
        [Parameter()] [switch] $ReplacePhoneNumbers,
        [Parameter()] [switch] $ReplaceTFNs,
        [Parameter()] [switch] $ReplaceMedicare,
        [Parameter()] [switch] $ReplaceDOBs,
        [Parameter()] [switch] $ReplacePassports,
        [Parameter()] [switch] $ReplaceAddresses,
        [Parameter()] [switch] $Force
    )

    if (-not (Test-Path $sourceFilePath)) {
        throw "Source file not found: $sourceFilePath"
    }

    $text = Get-Content $sourceFilePath -Raw
    $map = @{}

    if ($actionType -eq "rehydrate") {
        if (-not (Test-Path $mappingFilePath)) {
            throw "Mapping file not found: $mappingFilePath"
        }
        if (-not (Test-FileContentValid -FilePath $InputFile)) {
            Write-Error "Skipping file due to validation failure: $InputFile"
            return
        }
        if ($MappingFormat -eq "json") {
            $map = Get-Content $mappingFilePath | ConvertFrom-Json
        } elseif ($MappingFormat -eq "csv") {
            $map = @{}
            Import-Csv $mappingFilePath | ForEach-Object {
                $map[$_.Token] = $_.Original
            }
        }

        foreach ($token in $map.Keys) {
            $text = $text -replace [regex]::Escape($token), $map[$token]
        }

        Set-Content $targetFilePath -Value $text
        return
    }


    if ($ReplaceEmails) {
        Replace-WithToken "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "EMAIL"
    }
    if ($ReplaceGuids) {
        Replace-WithToken "\b[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}\b" "GUID"
    }
    if ($ReplaceIPs) {
        Replace-WithToken "\b(?:\d{1,3}\.){3}\d{1,3}\b" "IP"
    }
    if ($ReplaceCreditCards) {
        Replace-WithToken "\b(?:\d[ -]*?){13,16}\b" "CARD"
    }
    if ($ReplacePhoneNumbers) {
        Replace-WithToken "\b\(?0[2-8]\)?[ ]?\d{4}[ ]?\d{4}\b" "PHONE"
    }
    if ($ReplaceTFNs) {
        Replace-WithToken "\b\d{3}[ ]?\d{3}[ ]?\d{3}\b" "TFN"
    }
    if ($ReplaceMedicare) {
        Replace-WithToken "\b\d{4}[ ]?\d{5}[ ]?\d\b" "MED"
    }
    if ($ReplaceDOBs) {
        Replace-WithToken "\b\d{2}/\d{2}/\d{4}\b" "DOB"
    }
    if ($ReplacePassports) {
        Replace-WithToken "\b[A-Z]\d{7}\b" "PASS"
    }
    if ($ReplaceAddresses) {
        Replace-WithToken "\b\d{1,5}\s\w+\s(?:Street|St|Road|Rd|Avenue|Ave|Boulevard|Blvd|Lane|Ln)\b" "ADDR"
    }

    if ($MappingFormat -eq "json") {
        $map | ConvertTo-Json -Depth 3 | Set-Content $mappingFilePath
    } elseif ($MappingFormat -eq "csv") {
        $map.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{ Token = $_.Key; Original = $_.Value }
        } | Export-Csv $mappingFilePath -NoTypeInformation
    }

    Set-Content $targetFilePath -Value $text
}

function Test-FileContentValid {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "File does not exist: $FilePath"
        return $false
    }

    try {
        $content = Get-Content -Path $FilePath -ErrorAction Stop
        if ($content -is [System.Array] -and $content.Count -eq 0) {
            Write-Warning "File is empty: $FilePath"
            return $false
        }

        # Optional: check for non-text content
        $sample = $content | Select-Object -First 5
        if ($sample -join "`n" -match '[^\x00-\x7F]') {
            Write-Warning "File may contain non-ASCII or binary data: $FilePath"
        }

        return $true
    }
    catch {
        Write-Warning "Unable to read file: $FilePath. $_"
        return $false
    }
}
