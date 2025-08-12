Import-Module "$PSScriptRoot\TokenTool.psm1"
Import-Module "$PSScriptRoot\Logger.psm1"

function Request-CustomRegexAddition {
    $addNew = Read-Host "Would you like to add a custom regex type? (y/n)"
    if ($addNew -eq 'y') {
        $prefix = Read-Host "Enter prefix (e.g., CUSTOM_)"
        $pattern = Read-Host "Enter regex pattern"
        $description = Read-Host "Enter description"

        Write-Log "User requested custom regex addition: $prefix" -Level "Info"
        Add-CustomRegexType -Prefix $prefix -Pattern $pattern -Description $description
    }
}

# Request input path
$inputPath = Read-Host "Enter path to file or folder containing text files"
if (-not (Test-Path $inputPath)) {
    Write-Log "Invalid input path provided: $inputPath" -Level "Error"
    return
}

Write-Log "Input path validated: $inputPath" -Level "Info"

# Request regex selection
Request-CustomRegexAddition
$selectedPrefixes = Select-RegexTypes

# Process files
try {
    if ((Get-Item $inputPath).PSIsContainer) {
        $files = Get-ChildItem $inputPath -File -Recurse | Where-Object { $_.Extension -eq ".txt" }
        Write-Log "Processing folder: $inputPath with $($files.Count) .txt files" -Level "Info"

        foreach ($file in $files) {
            Write-Log "Processing file: $($file.FullName)" -Level "Info"
            Invoke-TokenReplacement -Path $file.FullName -SelectedRegexPrefixes $selectedPrefixes
        }
    } else {
        Write-Log "Processing single file: $inputPath" -Level "Info"
        Invoke-TokenReplacement -Path $inputPath -SelectedRegexPrefixes $selectedPrefixes
    }
}
catch {
    Write-Log "Unhandled error during tokenization run: $_" -Level "Error"
}
