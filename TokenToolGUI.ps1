Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module "$PSScriptRoot\TokenTool.psm1"

# Logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "ERROR"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    Add-Content -Path "$PSScriptRoot\TokenTool.log" -Value $logEntry
}

# GUI form
$form = New-Object System.Windows.Forms.Form
$form.Text = "TokenTool GUI"
$form.Size = '800,600'
$form.StartPosition = 'CenterScreen'

# Status bar
$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = "Ready"
$statusBar.AutoSize = $false
$statusBar.Size = '760,20'
$statusBar.Location = '10,530'
$statusBar.BorderStyle = 'Fixed3D'
$form.Controls.Add($statusBar)

function Show-Error {
    param ([string]$msg)
    $statusBar.Text = "❌ $msg"
    Write-Log $msg
}

function Show-Info {
    param ([string]$msg)
    $statusBar.Text = "✅ $msg"
    Write-Log $msg "INFO"
}

# File selection
$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Text = "Source File:"
$sourceLabel.Location = '10,20'
$form.Controls.Add($sourceLabel)

$sourceBox = New-Object System.Windows.Forms.TextBox
$sourceBox.Size = '600,20'
$sourceBox.Location = '100,20'
$form.Controls.Add($sourceBox)

$browseSource = New-Object System.Windows.Forms.Button
$browseSource.Text = "Browse"
$browseSource.Location = '710,20'
$form.Controls.Add($browseSource)

# Theme toggle
$themeLabel = New-Object System.Windows.Forms.Label
$themeLabel.Text = "Theme:"
$themeLabel.Location = '10,50'
$form.Controls.Add($themeLabel)

$themeDropdown = New-Object System.Windows.Forms.ComboBox
$themeDropdown.Items.AddRange(@("Light", "Dark"))
$themeDropdown.SelectedIndex = 0
$themeDropdown.Location = '100,50'
$form.Controls.Add($themeDropdown)

function Apply-Theme {
    param ($theme)
    if ($theme -eq "Dark") {
        $form.BackColor = 'Black'
        $form.ForeColor = 'White'
        $previewBox.BackColor = 'Black'
        $previewBox.ForeColor = 'White'
    } else {
        $form.BackColor = 'White'
        $form.ForeColor = 'Black'
        $previewBox.BackColor = 'White'
        $previewBox.ForeColor = 'Black'
    }
}
$themeDropdown.Add_SelectedIndexChanged({ Apply-Theme $themeDropdown.SelectedItem })

# Preview pane
$previewLabel = New-Object System.Windows.Forms.Label
$previewLabel.Text = "File Preview:"
$previewLabel.Location = '10,80'
$form.Controls.Add($previewLabel)

$previewBox = New-Object System.Windows.Forms.RichTextBox
$previewBox.Multiline = $true
$previewBox.ScrollBars = 'Vertical'
$previewBox.ReadOnly = $true
$previewBox.Size = '760,200'
$previewBox.Location = '10,100'
$form.Controls.Add($previewBox)

# Regex tester
$regexLabel = New-Object System.Windows.Forms.Label
$regexLabel.Text = "Test Regex:"
$regexLabel.Location = '10,310'
$form.Controls.Add($regexLabel)

$regexBox = New-Object System.Windows.Forms.TextBox
$regexBox.Size = '600,20'
$regexBox.Location = '100,310'
$form.Controls.Add($regexBox)

$testRegexButton = New-Object System.Windows.Forms.Button
$testRegexButton.Text = "Test"
$testRegexButton.Location = '710,310'
$form.Controls.Add($testRegexButton)

$matchesBox = New-Object System.Windows.Forms.ListBox
$matchesBox.Size = '760,100'
$matchesBox.Location = '10,340'
$form.Controls.Add($matchesBox)

$testRegexButton.Add_Click({
    $matchesBox.Items.Clear()
    $pattern = $regexBox.Text
    try {
        $matches = [regex]::Matches($previewBox.Text, $pattern)
        foreach ($m in $matches) {
            $matchesBox.Items.Add($m.Value)
        }
        Show-Info "Regex test completed."
    } catch {
        Show-Error "Invalid regex: $($_.Exception.Message)"
    }
})

# Add to regex library
$descLabel = New-Object System.Windows.Forms.Label
$descLabel.Text = "Description:"
$descLabel.Location = '10,450'
$form.Controls.Add($descLabel)

$descBox = New-Object System.Windows.Forms.TextBox
$descBox.Size = '600,20'
$descBox.Location = '100,450'
$form.Controls.Add($descBox)

$addRegexButton = New-Object System.Windows.Forms.Button
$addRegexButton.Text = "➕ Add to Library"
$addRegexButton.Location = '710,450'
$form.Controls.Add($addRegexButton)

$addRegexButton.Add_Click({
    $regex = $regexBox.Text
    $desc = $descBox.Text
    if (-not $regex -or -not $desc) {
        Show-Error "Please enter both a regex and a description."
        return
    }
    try {
        [void][regex]::new($regex)
    } catch {
        Show-Error "Invalid regex pattern."
        return
    }
    $libraryPath = "$PSScriptRoot\RegexLibrary.json"
    $existing = @()
    if (Test-Path $libraryPath) {
        $existing = Get-Content $libraryPath | ConvertFrom-Json
    }
    $newEntry = [PSCustomObject]@{ Description = $desc; Pattern = $regex }
    $updated = $existing + $newEntry
    $updated | ConvertTo-Json -Depth 3 | Set-Content $libraryPath
    Show-Info "Regex added to library."
    $regexBox.Text = ""
    $descBox.Text = ""
})

# Load file preview
function Load-FilePreview {
    param ([string]$filePath)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $printable = $text.ToCharArray() | Where-Object { $_ -match '[\x20-\x7E\r\n\t]' }
        $ratio = $printable.Count / $text.Length
        if ($ratio -lt 0.9) {
            $previewBox.Text = "⚠️ This file may contain binary or unreadable content."
            Show-Error "Binary content detected in preview."
            return
        }
        $previewBox.Text = $text.Substring(0, [Math]::Min($text.Length, 5000))
        Show-Info "File loaded successfully."
    } catch {
        $previewBox.Text = "❌ Unable to read file."
        Show-Error "Failed to load file: $($_.Exception.Message)"
    }
}

$browseSource.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    if ($dialog.ShowDialog() -eq "OK") {
        $sourceBox.Text = $dialog.FileName
        Load-FilePreview $dialog.FileName
    }
})

$sourceBox.AllowDrop = $true
$sourceBox.Add_DragEnter({ $_.Effect = 'Copy' })
$sourceBox.Add_DragDrop({
    $filePath = $_.Data.GetData("FileDrop")[0]
    $sourceBox.Text = $filePath
    Load-FilePreview $filePath
})

# Run button
$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Run Tokenization"
$runButton.Location = '10,500'
$form.Controls.Add($runButton)

$runButton.Add_Click({
    try {
        Process-Tokenization -sourceFilePath $sourceBox.Text `
                             -targetFilePath "$PSScriptRoot\output.txt" `
                             -mappingFilePath "$PSScriptRoot\map.json" `
                             -MappingFormat "json" `
                             -actionType "tokenize" `
                             -ReplaceEmails `
                             -ReplaceGuids `
                             -ReplaceIPs `
                             -Force
        Show-Info "Tokenization complete."
    } catch {
        Show-Error "Tokenization failed: $($_.Exception.Message)"
    }
})

Apply-Theme "Light"
$form.ShowDialog()
