Add-Type -AssemblyName System.Windows.Forms

function Show-RegexSelector {
    param([string]$LibraryPath = "$PSScriptRoot\regexlibrary.json")

    $regexes = Get-Content $LibraryPath | ConvertFrom-Json

    $form = New-Object Windows.Forms.Form
    $form.Text = "Select Regex Types"
    $form.Size = '400,400'
    $form.StartPosition = "CenterScreen"

    $checkedListBox = New-Object Windows.Forms.CheckedListBox
    $checkedListBox.Size = '360,280'
    $checkedListBox.Location = '10,10'
    $checkedListBox.CheckOnClick = $true

    foreach ($r in $regexes) {
        $checkedListBox.Items.Add("[$($r.Prefix)] $($r.Description)")
    }

    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = "Confirm"
    $okButton.Location = '220,310'
    $okButton.Add_Click({
        $form.Tag = $checkedListBox.CheckedIndices
        $form.Close()
    })

    $cancelButton = New-Object Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = '100,310'
    $cancelButton.Add_Click({
        $form.Tag = $null
        $form.Close()
    })

    $form.Controls.AddRange(@($checkedListBox, $okButton, $cancelButton))
    $form.ShowDialog() | Out-Null

    if ($form.Tag -eq $null) {
        Write-Host "Selection cancelled."
        return @()
    }

    $selectedPrefixes = @()
    foreach ($index in $form.Tag) {
        $selectedPrefixes += $regexes[$index].Prefix
    }

    return $selectedPrefixes
}
