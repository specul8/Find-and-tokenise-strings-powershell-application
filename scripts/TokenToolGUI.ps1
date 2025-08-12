<#
.SYNOPSIS
TokenTool GUI with folder/file selection, filter, recursion, preview paging, progress bar, non-blocking error bar, and custom regex support.

.DESCRIPTION
- Select a folder (with filter and recursion) or multiple files.
- Validate and select predefined regex types from regexlibrary.json; optionally add custom regex (prefix, pattern, description) which is validated and persisted.
- Preview matches across selected files in pages of 40 (Prev/Next). Tokenize or cancel.
- Never executes file contents; reads as text only and skips likely-binary files.
- Writes tokenized output to timestamp-prefixed copies by default; supports overwrite-in-place.
- Writes a per-file mapping (JSON or CSV) Original->Token for rehydration.
- Logs to file and mirrors messages to a 3-line, scrollable notification bar (no modal popups for errors).
- Remembers window size and position per user via %LOCALAPPDATA%\TokenTool\settings.json.
- Approved verbs are used for all function names.
- Code adheres to standards: colon-after-variable safe, $null-first comparisons, no collisions with automatic variables or built-in cmdlets.

.PARAMETER LibraryPath
Path to the regexlibrary.json file.

.EXAMPLE
pwsh -File .\scripts\TokenToolGUI.ps1 -LibraryPath .\data\regexlibrary.json

.NOTES
Requires src\Logger.psm1 and src\TokenTool.psm1.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LibraryPath = "$PSScriptRoot\..\data\regexlibrary.json"
)

Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module "$PSScriptRoot\..\src\Logger.psm1" -Force
Import-Module "$PSScriptRoot\..\src\TokenTool.psm1" -Force

# -------------------- Settings persistence --------------------
$settingsPath = Join-Path $env:LOCALAPPDATA "TokenTool\settings.json"
$settingsDir  = Split-Path -Parent $settingsPath
if (-not (Test-Path -LiteralPath $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

$uiState = [ordered]@{
    Window          = [ordered]@{ X=200; Y=200; W=1000; H=700 }
    LastPath        = ''
    LastFilter      = '*.txt'
    Recurse         = $false
    InPlace         = $false
    MappingFormat   = 'json'
    SelectedPrefixes= @()
    RegexDefs       = @()
    FilesResolved   = @()
    PreviewItems    = @()  # objects: Prefix, Value, File
    PreviewPage     = 0
}

function Import-UiSettings {
<#
.SYNOPSIS
Imports saved window and UI state from disk.
#>
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $json = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
            if ($null -ne $json) {
                $saved = $json | ConvertFrom-Json
                if ($null -ne $saved.Window)          { $uiState.Window           = $saved.Window }
                if ($null -ne $saved.LastPath)        { $uiState.LastPath         = $saved.LastPath }
                if ($null -ne $saved.LastFilter)      { $uiState.LastFilter       = $saved.LastFilter }
                if ($null -ne $saved.Recurse)         { $uiState.Recurse          = [bool]$saved.Recurse }
                if ($null -ne $saved.InPlace)         { $uiState.InPlace          = [bool]$saved.InPlace }
                if ($null -ne $saved.MappingFormat)   { $uiState.MappingFormat    = [string]$saved.MappingFormat }
                if ($null -ne $saved.SelectedPrefixes){ $uiState.SelectedPrefixes = @($saved.SelectedPrefixes) }
            }
        } catch {
            Write-Log ("Failed to import UI settings: $($_.Exception.Message)") -Level "Warning"
        }
    }
}

function Export-UiSettings {
<#
.SYNOPSIS
Persists window and UI state to disk.
#>
    try {
        $uiState | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    } catch {
        Write-Log ("Failed to export UI settings: $($_.Exception.Message)") -Level "Warning"
    }
}

# -------------------- Notification bar and GUI log sink --------------------
function Write-Notify {
<#
.SYNOPSIS
Appends a colored line to the 3-line, scrollable notification bar.
#>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warning','Error','Success','Debug')][string]$Level = 'Info'
    )
    $color = switch ($Level) {
        'Error'   { [Drawing.Color]::Red }
        'Warning' { [Drawing.Color]::DarkOrange }
        'Success' { [Drawing.Color]::Green }
        'Debug'   { [Drawing.Color]::SlateGray }
        default   { [Drawing.Color]::DimGray }
    }
    $append = {
        param($rtb, $text, $clr)
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $rtb.SelectionColor = $clr
        $rtb.AppendText($text + [Environment]::NewLine)
        $rtb.SelectionColor = $rtb.ForeColor
        $rtb.ScrollToCaret()
    }
    $form.BeginInvoke($append, $rtbNotify, $Message, $color) | Out-Null
}

# Mirror log output to the GUI's notification bar
Set-LogGuiSink {
    param($Level, $Message, $Timestamp)
    Write-Notify -Message ("[{0}] {1} - {2}" -f $Level, $Timestamp, $Message) -Level $Level
}

# -------------------- Regex list and selection --------------------
function Update-RegexList {
<#
.SYNOPSIS
Loads regex definitions from the library into the checklist.
#>
    try {
        $uiState.RegexDefs = @(Get-RegexTypes -LibraryPath $LibraryPath)
        $clbRegex.Items.Clear()
        foreach ($def in $uiState.RegexDefs) {
            $text = "[{0}] {1}" -f $def.Prefix, $def.Description
            $null = $clbRegex.Items.Add($text, ($uiState.SelectedPrefixes -contains $def.Prefix))
        }
        Write-Log ("Loaded {0} regex definitions" -f $uiState.RegexDefs.Count) -Level "Info"
    } catch {
        Write-Notify -Message ("Failed to load regex library: $($_.Exception.Message)") -Level "Error"
    }
}

function Get-SelectedPrefixes {
<#
.SYNOPSIS
Gets selected regex prefixes from the checklist.
#>
    $out = @()
    foreach ($i in $clbRegex.CheckedIndices) {
        $txt = [string]$clbRegex.Items[$i]
        if ($txt -match '^

\[(?<pfx>[A-Za-z0-9]+)\]

\s') {
            $out += $Matches['pfx']
        }
    }
    return $out
}

# -------------------- File resolution --------------------
function Test-InputSelection {
<#
.SYNOPSIS
Validates the user's selection and resolves files according to mode, filter, and recursion.
#>
    $uiState.FilesResolved = @()

    $raw = $txtPath.Text.Trim()
    if ([string]::IsNullOrEmpty($raw)) {
        Write-Notify -Message "Select a folder or files first." -Level "Warning"
        return $false
    }

    $filter = [string]$cbFilter.SelectedItem
    $recurse = [bool]$chkRecurse.Checked
    $uiState.LastFilter = $filter
    $uiState.Recurse    = $recurse

    if ($rbFolder.Checked) {
        if (-not (Test-Path -LiteralPath $raw -PathType Container)) {
            Write-Notify -Message "Folder not found." -Level "Error"
            return $false
        }
        $uiState.FilesResolved = @(Get-FilesToProcess -Path $raw -Filter $filter -Recurse:$recurse)
    } else {
        # Files mode: semicolon-separated list
        $parts = $raw -split ';'
        foreach ($p in $parts) {
            if (Test-Path -LiteralPath $p -PathType Leaf) {
                $uiState.FilesResolved += (Resolve-Path -LiteralPath $p).Path
            }
        }
    }

    if ($uiState.FilesResolved.Count -eq 0) {
        Write-Notify -Message "No files matched the selection." -Level "Warning"
        return $false
    }

    $uiState.LastPath = $raw
    return $true
}

# -------------------- Preview building and paging --------------------
function Get-MatchPreview {
<#
.SYNOPSIS
Builds a preview list of matches for the selected files and prefixes.
#>
    $uiState.PreviewItems = @()
    $uiState.PreviewPage  = 0

    $pfxs = @(Get-SelectedPrefixes)
    if ($pfxs.Count -eq 0) { Write-Notify -Message "Select at least one regex type." -Level "Warning"; return }

    $defs = foreach ($p in $pfxs) { $uiState.RegexDefs | Where-Object { $_.Prefix -eq $p } }
    if ($defs.Count -eq 0) { Write-Notify -Message "No matching regex definitions found." -Level "Warning"; return }

    # Compile regexes with validation
    $compiled = @()
    foreach ($d in $defs) {
        try {
            $rx = [System.Text.RegularExpressions.Regex]::new([string]$d.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $compiled += [pscustomobject]@{ Prefix=$d.Prefix; Regex=$rx }
        } catch {
            Write-Notify -Message ("Invalid regex for {0}: {1}" -f $d.Prefix, $_.Exception.Message) -Level "Error"
            return
        }
    }

    foreach ($f in $uiState.FilesResolved) {
        try {
            if (Test-IsBinaryFile -Path $f) { continue }
            $text = Get-Content -LiteralPath $f -Raw -Encoding UTF8
            foreach ($c in $compiled) {
                foreach ($m in $c.Regex.Matches($text)) {
                    $uiState.PreviewItems += [pscustomobject]@{
                        Prefix = $c.Prefix
                        Value  = [string]$m.Value
                        File   = $f
                    }
                }
            }
        } catch {
            Write-Notify -Message ("Preview scan error for $($f): $($_.Exception.Message)") -Level "Warning"
        }
    }
    Write-Log ("Preview collected {0} matches" -f $uiState.PreviewItems.Count) -Level "Info"
}

function Set-MatchPage {
<#
.SYNOPSIS
Displays 40 preview items per page in the Matches tab.
#>
    param([int]$Index)

    $total = $uiState.PreviewItems.Count
    $lvMatches.BeginUpdate()
    $lvMatches.Items.Clear()

    if ($total -eq 0) {
        $lblPage.Text = "No matches"
        $btnPrev.Enabled = $false
        $btnNext.Enabled = $false
        $lvMatches.EndUpdate()
        return
    }

    $start = $Index * 40
    if ($start -ge $total) { $Index = 0; $start = 0 }
    $end = [Math]::Min($start + 39, $total - 1)

    foreach ($row in $uiState.PreviewItems[$start..$end]) {
        $lvi = New-Object System.Windows.Forms.ListViewItem($row.Prefix)
        $null = $lvi.SubItems.Add($row.Value)
        $null = $lvi.SubItems.Add([IO.Path]::GetFileName($row.File))
        $null = $lvMatches.Items.Add($lvi)
    }

    $lblPage.Text = "Showing {0}-{1} of {2}" -f ($start + 1), ($end + 1), $total
    $btnPrev.Enabled = ($Index -gt 0)
    $btnNext.Enabled = ($end -lt ($total - 1))
    $uiState.PreviewPage = $Index

    $lvMatches.EndUpdate()
}

# -------------------- Content preview --------------------
function Set-ContentPreview {
<#
.SYNOPSIS
Loads text content into the content tab with lightweight syntax highlighting.
#>
    param([string]$PathToShow)

    $rtbContent.ReadOnly = $false
    $rtbContent.Clear()
    if (-not (Test-Path -LiteralPath $PathToShow -PathType Leaf)) { $rtbContent.ReadOnly = $true; return }

    try {
        $txt = Get-Content -LiteralPath $PathToShow -Raw -Encoding UTF8
        $rtbContent.Text = $txt
        $rtbContent.SuspendLayout()
        # Reset
        $rtbContent.SelectAll()
        $rtbContent.SelectionColor = [Drawing.Color]::Black
        $rtbContent.DeselectAll()

        $ext = [IO.Path]::GetExtension($PathToShow).ToLowerInvariant()
        if ($ext -eq '.ps1') {
            $rxC = [Text.RegularExpressions.Regex]::new('(?m)^\s*#.*$')
            foreach ($m in $rxC.Matches($txt)) { $rtbContent.Select($m.Index,$m.Length); $rtbContent.SelectionColor = [Drawing.Color]::ForestGreen }
            $rxS = [Text.RegularExpressions.Regex]::new('"(?:\\.|[^"\\]

)*"')
            foreach ($m in $rxS.Matches($txt)) { $rtbContent.Select($m.Index,$m.Length); $rtbContent.SelectionColor = [Drawing.Color]::SaddleBrown }
        } elseif ($ext -eq '.json') {
            $rxK = [Text.RegularExpressions.Regex]::new('"(?:\\.|[^"\\]

)*"(?=\s*:)')
            foreach ($m in $rxK.Matches($txt)) { $rtbContent.Select($m.Index,$m.Length); $rtbContent.SelectionColor = [Drawing.Color]::Blue }
            $rxV = [Text.RegularExpressions.Regex]::new('"(?:\\.|[^"\\]

)*"')
            foreach ($m in $rxV.Matches($txt)) { $rtbContent.Select($m.Index,$m.Length); $rtbContent.SelectionColor = [Drawing.Color]::SaddleBrown }
        } elseif ($ext -eq '.xml') {
            $rxT = [Text.RegularExpressions.Regex]::new('<[^>]+?>')
            foreach ($m in $rxT.Matches($txt)) { $rtbContent.Select($m.Index,$m.Length); $rtbContent.SelectionColor = [Drawing.Color]::Navy }
        }
        $rtbContent.ResumeLayout()
    } catch {
        Write-Notify -Message ("Preview read failed: $($_.Exception.Message)") -Level "Warning"
    } finally {
        $rtbContent.ReadOnly = $true
    }
}

# -------------------- Form and controls --------------------
Import-UiSettings

$form = New-Object System.Windows.Forms.Form
$form.Text = "TokenTool"
$form.StartPosition = 'Manual'
$form.Location = New-Object Drawing.Point($uiState.Window.X, $uiState.Window.Y)
$form.Size = New-Object Drawing.Size($uiState.Window.W, $uiState.Window.H)
$form.MinimumSize = New-Object Drawing.Size(900, 560)

# Top panel (mode, path, browse, filter, recurse)
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Dock = 'Top'
$panelTop.Height = 100

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = "Mode:"
$lblMode.Location = New-Object Drawing.Point(10, 12)

$rbFolder = New-Object System.Windows.Forms.RadioButton
$rbFolder.Text = "Folder"
$rbFolder.Location = New-Object Drawing.Point(60, 10)
$rbFolder.Checked = $true

$rbFiles = New-Object System.Windows.Forms.RadioButton
$rbFiles.Text = "Files"
$rbFiles.Location = New-Object Drawing.Point(130, 10)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object Drawing.Point(10, 40)
$txtPath.Width = 640
$txtPath.Text = $uiState.LastPath

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object Drawing.Point(660, 38)
$btnBrowse.Width = 90

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = "Filter:"
$lblFilter.Location = New-Object Drawing.Point(760, 12)

$cbFilter = New-Object System.Windows.Forms.ComboBox
$cbFilter.Location = New-Object Drawing.Point(760, 38)
$cbFilter.Width = 120
$cbFilter.DropDownStyle = 'DropDownList'
[void]$cbFilter.Items.AddRange(@('*.txt','*.csv','*.json','*.xml','*.ini','*.ps1','*.log','*.*'))
$cbFilter.SelectedItem = $uiState.LastFilter

$chkRecurse = New-Object System.Windows.Forms.CheckBox
$chkRecurse.Text = "Recurse"
$chkRecurse.Location = New-Object Drawing.Point(890, 38)
$chkRecurse.Checked = [bool]$uiState.Recurse

$panelTop.Controls.AddRange(@($lblMode,$rbFolder,$rbFiles,$txtPath,$btnBrowse,$lblFilter,$cbFilter,$chkRecurse))

# Main split (controls over content/matches)
$splitMain = New-Object System.Windows.Forms.SplitContainer
$splitMain.Dock = 'Fill'
$splitMain.Orientation = 'Horizontal'
$splitMain.SplitterDistance = 250

# Controls panel (regex, custom, actions, progress)
$panelControls = New-Object System.Windows.Forms.Panel
$panelControls.Dock = 'Fill'

$clbRegex = New-Object System.Windows.Forms.CheckedListBox
$clbRegex.Location = New-Object System.Drawing.Point(10, 10)
$clbRegex.Size = New-Object System.Drawing.Size(380, 180)
$clbRegex.CheckOnClick = $true

$grpCustom = New-Object System.Windows.Forms.GroupBox
$grpCustom.Text = "Add custom regex"
$grpCustom.Location = New-Object System.Drawing.Point(400, 10)
$grpCustom.Size = New-Object System.Drawing.Size(520, 180)

$lblPrefix = New-Object System.Windows.Forms.Label
$lblPrefix.Text = "Prefix:"
$lblPrefix.Location = New-Object System.Drawing.Point(10, 25)

$txtPrefix = New-Object System.Windows.Forms.TextBox
$txtPrefix.Location = New-Object System.Drawing.Point(80, 22)
$txtPrefix.Width = 120

$lblPattern = New-Object System.Windows.Forms.Label
$lblPattern.Text = "Pattern:"
$lblPattern.Location = New-Object System.Drawing.Point(10, 55)

$txtPattern = New-Object System.Windows.Forms.TextBox
$txtPattern.Location = New-Object System.Drawing.Point(80, 52)
$txtPattern.Width = 420

$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = "Description:"
$lblDesc.Location = New-Object System.Drawing.Point(10, 85)

$txtDesc = New-Object System.Windows.Forms.TextBox
$txtDesc.Location = New-Object System.Drawing.Point(80, 82)
$txtDesc.Width = 420

$btnAddRegex = New-Object System.Windows.Forms.Button
$btnAddRegex.Text = "Validate and add"
$btnAddRegex.Location = New-Object System.Drawing.Point(80, 120)

$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text = "Preview"
$btnPreview.Location = New-Object System.Drawing.Point(10, 200)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Tokenize"
$btnRun.Location = New-Object System.Drawing.Point(100, 200)

$chkInPlace = New-Object System.Windows.Forms.CheckBox
$chkInPlace.Text = "Overwrite in place"
$chkInPlace.Location = New-Object System.Drawing.Point(200, 203)
$chkInPlace.Checked = [bool]$uiState.InPlace

$lblMapping = New-Object System.Windows.Forms.Label
$lblMapping.Text = "Mapping:"
$lblMapping.Location = New-Object System.Drawing.Point(360, 203)

$cbMapping = New-Object System.Windows.Forms.ComboBox
$cbMapping.Location = New-Object System.Drawing.Point(420, 200)
$cbMapping.DropDownStyle = 'DropDownList'
[void]$cbMapping.Items.AddRange(@('json','csv'))
$cbMapping.SelectedItem = $uiState.MappingFormat

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(520, 200)
$progress.Size = New-Object System.Drawing.Size(400, 22)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0

$grpCustom.Controls.AddRange(@($lblPrefix,$txtPrefix,$lblPattern,$txtPattern,$lblDesc,$txtDesc,$btnAddRegex))
$panelControls.Controls.AddRange(@($clbRegex,$grpCustom,$btnPreview,$btnRun,$chkInPlace,$lblMapping,$cbMapping,$progress))
$splitMain.Panel1.Controls.Add($panelControls)

# Tabs (Content + Matches)
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'

$tabContent = New-Object System.Windows.Forms.TabPage
$tabContent.Text = "Content"

$rtbContent = New-Object System.Windows.Forms.RichTextBox
$rtbContent.Dock = 'Fill'
$rtbContent.Font = New-Object Drawing.Font('Consolas', 10)
$rtbContent.ReadOnly = $true
$rtbContent.WordWrap = $false
$tabContent.Controls.Add($rtbContent)

$tabMatches = New-Object System.Windows.Forms.TabPage
$tabMatches.Text = "Matches"

$lvMatches = New-Object System.Windows.Forms.ListView
$lvMatches.Dock = 'Fill'
$lvMatches.View = [System.Windows.Forms.View]::Details
$lvMatches.FullRowSelect = $true
[void]$lvMatches.Columns.Add("Prefix", 100)
[void]$lvMatches.Columns.Add("Value", 500)
[void]$lvMatches.Columns.Add("File", 220)

$panelMatchBottom = New-Object System.Windows.Forms.Panel
$panelMatchBottom.Dock = 'Bottom'
$panelMatchBottom.Height = 36

$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = "Prev 40"
$btnPrev.Location = New-Object System.Drawing.Point(10, 6)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = "Next 40"
$btnNext.Location = New-Object System.Drawing.Point(90, 6)

$lblPage = New-Object System.Windows.Forms.Label
$lblPage.Text = "No matches"
$lblPage.Location = New-Object System.Drawing.Point(180, 10)
$lblPage.AutoSize = $true

$panelMatchBottom.Controls.AddRange(@($btnPrev,$btnNext,$lblPage))
$tabMatches.Controls.Add($lvMatches)
$tabMatches.Controls.Add($panelMatchBottom)

$tabs.TabPages.AddRange(@($tabContent,$tabMatches))
$splitMain.Panel2.Controls.Add($tabs)

# Bottom notification bar (3 lines high, scrollable, colored)
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Dock = 'Bottom'
$panelBottom.Height = 54

$rtbNotify = New-Object System.Windows.Forms.RichTextBox
$rtbNotify.Dock = 'Fill'
$rtbNotify.ReadOnly = $true
$rtbNotify.ScrollBars = 'Vertical'
$rtbNotify.BackColor = [Drawing.Color]::White
$rtbNotify.ForeColor = [Drawing.Color]::Black
$rtbNotify.WordWrap = $false

$panelBottom.Controls.Add($rtbNotify)

# Compose form
$form.Controls.Add($splitMain)
$form.Controls.Add($panelTop)
$form.Controls.Add($panelBottom)

# -------------------- Init --------------------
Import-UiSettings
Update-RegexList
if (-not [string]::IsNullOrEmpty($uiState.LastPath)) { $txtPath.Text = $uiState.LastPath }

# Re-check previously selected prefixes
if ($uiState.SelectedPrefixes.Count -gt 0) {
    for ($i=0; $i -lt $clbRegex.Items.Count; $i++) {
        $txt = [string]$clbRegex.Items[$i]
        if ($txt -match '^

\[(?<pfx>[A-Za-z0-9]+)\]

\s' -and ($uiState.SelectedPrefixes -contains $Matches['pfx'])) {
            $clbRegex.SetItemChecked($i, $true)
        }
    }
}

# -------------------- Handlers --------------------
# Browse
$btnBrowse.Add_Click({
    if ($rbFolder.Checked) {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtPath.Text = $dlg.SelectedPath
            $uiState.FilesResolved = @(Get-FilesToProcess -Path $dlg.SelectedPath -Filter ([string]$cbFilter.SelectedItem) -Recurse:$chkRecurse.Checked)
            if ($uiState.FilesResolved.Count -gt 0) { Set-ContentPreview -PathToShow $uiState.FilesResolved[0] }
        }
    } else {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Multiselect = $true
        $ofd.Filter = "Supported|*.txt;*.csv;*.json;*.xml;*.ini;*.ps1;*.log|All files|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtPath.Text = ($ofd.FileNames -join ';')
            if ($ofd.FileNames.Count -gt 0) { Set-ContentPreview -PathToShow $ofd.FileNames[0] }
        }
    }
})

# Add custom regex
$btnAddRegex.Add_Click({
    $pfx = $txtPrefix.Text.Trim()
    $pat = $txtPattern.Text
    $desc= $txtDesc.Text.Trim()

    if ([string]::IsNullOrEmpty($pfx) -or [string]::IsNullOrEmpty($pat) -or [string]::IsNullOrEmpty($desc)) {
        Write-Notify -Message "Custom regex requires Prefix, Pattern, and Description." -Level "Warning"
        return
    }
    if ($pfx -notmatch '^[A-Za-z0-9]+$') {
        Write-Notify -Message "Prefix must be alphanumeric." -Level "Error"
        return
    }
    try {
        [void][Text.RegularExpressions.Regex]::new($pat)
        Add-RegexType -Prefix $pfx -Pattern $pat -Description $desc -LibraryPath $LibraryPath
        Write-Notify -Message ("Custom regex '{0}' added." -f $pfx) -Level "Success"
        Update-RegexList
        # Auto-check it
        for ($i=0; $i -lt $clbRegex.Items.Count; $i++) {
            $t = [string]$clbRegex.Items[$i]
            if ($t -like "[${pfx}]*") { $clbRegex.SetItemChecked($i,$true); break }
        }
    } catch {
        Write-Notify -Message ("Invalid regex: {0}" -f $_.Exception.Message) -Level "Error"
    }
})

# Preview
$btnPreview.Add_Click({
    if (-not (Test-InputSelection)) { return }
    $uiState.SelectedPrefixes = @(Get-SelectedPrefixes)
    if ($uiState.SelectedPrefixes.Count -eq 0) { Write-Notify -Message "Select at least one regex type." -Level "Warning"; return }
    Get-MatchPreview
    Set-MatchPage -Index 0
    $tabs.SelectedTab = $tabMatches
})

# Paging
$btnPrev.Add_Click({ Set-MatchPage -Index ([Math]::Max(0, $uiState.PreviewPage - 1)) })
$btnNext.Add_Click({ Set-MatchPage -Index ($uiState.PreviewPage + 1) })

# Tokenize
$btnRun.Add_Click({
    if (-not (Test-InputSelection)) { return }
    $uiState.SelectedPrefixes = @(Get-SelectedPrefixes)
    if ($uiState.SelectedPrefixes.Count -eq 0) { Write-Notify -Message "Select at least one regex type." -Level "Warning"; return }

    $uiState.InPlace       = [bool]$chkInPlace.Checked
    $uiState.MappingFormat = [string]$cbMapping.SelectedItem

    $total = $uiState.FilesResolved.Count
    if ($total -le 0) { Write-Notify -Message "No files to process." -Level "Warning"; return }

    $progress.Value = 0
    $idx = 0
    foreach ($f in $uiState.FilesResolved) {
        try {
            $summary = Invoke-TokenTool -Path $f -Filter '*.*' -RegexPrefix $uiState.SelectedPrefixes -LibraryPath $LibraryPath -InPlace:$uiState.InPlace -MappingFormat $uiState.MappingFormat
            if ($null -ne $summary) {
                Write-Notify -Message ("Tokenized: {0} (matches: {1})" -f $summary.File, $summary.Matches) -Level "Success"
            }
        } catch {
            Write-Notify -Message ("Error: {0}" -f $_.Exception.Message) -Level "Error"
        } finally {
            $idx++
            $pct = [int](($idx / $total) * 100)
            if ($pct -lt 0) { $pct = 0 } elseif ($pct -gt 100) { $pct = 100 }
            $progress.Value = $pct
            $form.Refresh()
        }
    }
    $progress.Value = 100
    Write-Notify -Message "Completed tokenization." -Level "Success"
})

# Persist window on move/resize/close
$form.Add_Move({
    $uiState.Window.X = $form.Location.X
    $uiState.Window.Y = $form.Location.Y
})
$form.Add_Resize({
    $uiState.Window.W = $form.Size.Width
    $uiState.Window.H = $form.Size.Height
})
$form.Add_FormClosing({ Export-UiSettings })

# Initial content preview if possible
try {
    if (-not [string]::IsNullOrEmpty($uiState.LastPath) -and (Test-Path -LiteralPath $uiState.LastPath)) {
        if (Test-Path -LiteralPath $uiState.LastPath -PathType Container) {
            $uiState.FilesResolved = @(Get-FilesToProcess -Path $uiState.LastPath -Filter $uiState.LastFilter -Recurse:$uiState.Recurse)
            if ($uiState.FilesResolved.Count -gt 0) { Set-ContentPreview -PathToShow $uiState.FilesResolved[0] }
        } elseif (Test-Path -LiteralPath $uiState.LastPath -PathType Leaf) {
            Set-ContentPreview -PathToShow $uiState.LastPath
        }
    }
} catch {
    Write-Notify -Message ("Init error: {0}" -f $_.Exception.Message) -Level "Warning"
}

# Show the form
[void]$form.ShowDialog()
