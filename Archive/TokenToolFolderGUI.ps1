Import-Module "$PSScriptRoot\TokenTool.psm1"
Import-Module "$PSScriptRoot\Logger.psm1"
Add-Type -AssemblyName System.Windows.Forms

function Show-ModeSelector {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Choose Input Mode"
    $form.Size = '300,150'
    $form.StartPosition = "CenterScreen"

    $radioFolder = New-Object Windows.Forms.RadioButton
    $radioFolder.Text = "Select Folder"
    $radioFolder.Location = '30,30'
    $radioFolder.Checked = $true

    $radioFiles = New-Object Windows.Forms.RadioButton
    $radioFiles.Text = "Select Files"
    $radioFiles.Location = '30,60'

    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = "Continue"
    $okButton.Location = '100,90'
    $okButton.Add_Click({
        $form.Tag = if ($radioFolder.Checked) { "Folder" } else { "Files" }
        $form.Close()
    })

    $form.Controls.AddRange(@($radioFolder, $radioFiles, $okButton))
    $form.ShowDialog() | Out-Null
    return $form.Tag
}

function Show-ExtensionSelector {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Filter by File Type"
    $form.Size = '300,150'
    $form.StartPosition = "CenterScreen"

    $combo = New-Object Windows.Forms.ComboBox
    $combo.Location = '30,30'
    $combo.Size = '220,30'
    $combo.DropDownStyle = 'DropDownList'
    $combo.Items.AddRange(@("*.txt", "*.csv", "*.*"))
    $combo.SelectedIndex = 0

    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = "Confirm"
    $okButton.Location = '100,70'
    $okButton.Add_Click({
        $form.Tag = $combo.SelectedItem
        $form.Close()
    })

    $form.Controls.AddRange(@($combo, $okButton))
    $form.ShowDialog() | Out-Null
    return $form.Tag
}

function SelectFilesFromFolder {
    $folderDialog = New-Object Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = "Select a folder containing files"
    if ($folderDialog.ShowDialog() -ne "OK") {
        Write-Log "Folder selection cancelled" -Level "Warning"
        return @()
    }

    $filter = Show-ExtensionSelector
    Write-Log "Filtering folder '$($folderDialog.SelectedPath)' with filter '$filter'" -Level "Info"
    return Get-ChildItem -Path $folderDialog.SelectedPath -Filter $filter -File | Select-Object -ExpandProperty FullName
}

function SelectFilesDirectly {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = "Select one or more files"
    $dialog.Filter = "Text Files (*.txt)|*.txt|CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog() -eq "OK") {
        Write-Log "User selected $($dialog.FileNames.Count) file(s)" -Level "Info"
        return $dialog.FileNames
    } else {
        Write-Log "File selection cancelled" -Level "Warning"
        return @()
    }
}

# Reuse existing GUI functions
function Show-RegexSelector { ... }     # Same as before
function Show-ProgressBar { ... }       # Same as before

# 🔄 Main Flow
$mode = Show-ModeSelector
$selectedFiles = if ($mode -eq "Folder") {
    SelectFilesFromFolder
} else {
    SelectFilesDirectly
}

if (-not $selectedFiles -or $selectedFiles.Count -eq 0) {
    [Windows.Forms.MessageBox]::Show("No files selected. Aborting.", "TokenTool", "OK", "Warning")
    return
}

$selectedPrefixes = Show-RegexSelector
if (-not $selectedPrefixes -or $selectedPrefixes.Count -eq 0) {
    [Windows.Forms.MessageBox]::Show("No regex types selected. Aborting.", "TokenTool", "OK", "Warning")
    return
}

$progress = Show-ProgressBar -Maximum $selectedFiles.Count

for ($i = 0; $i -lt $selectedFiles.Count; $i++) {
    $file = $selectedFiles[$i]
    try {
        Write-Log "Processing file: $file" -Level "Info"
        Invoke-TokenReplacement -Path $file -SelectedRegexPrefixes $selectedPrefixes
    } catch {
        $msg = "Error processing file: $file`n$_"
        Write-Log $msg -Level "Error"
        [Windows.Forms.MessageBox]::Show($msg, "Error", "OK", "Error")
    }
    $progress.Bar.Value = $i + 1
    $progress.Form.Refresh()
}

$progress.Form.Close()
[Windows.Forms.MessageBox]::Show("Tokenization complete.", "TokenTool", "OK", "Information")
Write-Log "Tokenization complete for all selected files." -Level "Success"
