# Requires -Version 5.1 or PowerShell 7+, Pester v5
Import-Module "$PSScriptRoot\..\src\TokenTool.psm1" -Force

Describe "Get-FilesToProcess" {
    It "returns the file when given a file path" {
        $tmp = New-Item -ItemType File -Path (Join-Path $env:TEMP "tt_file.txt") -Force
        (Get-FilesToProcess -Path $tmp.FullName) | Should -Contain $tmp.FullName
        Remove-Item $tmp.FullName -Force
    }
    It "filters files by extension in a folder" {
        $dir = Join-Path $env:TEMP "tt_dir_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir | Out-Null
        $a = New-Item -ItemType File -Path (Join-Path $dir "a.txt")
        $b = New-Item -ItemType File -Path (Join-Path $dir "b.csv")
        $files = Get-FilesToProcess -Path $dir -Filter '*.txt'
        $files | Should -Contain $a.FullName
        $files | Should -Not -Contain $b.FullName
        Remove-Item $dir -Recurse -Force
    }
}

Describe "Invoke-TokenReplacement" {
    $lib = "$PSScriptRoot\..\data\regexlibrary.json"
    It "replaces emails with deterministic tokens" {
        $dir = Join-Path $env:TEMP "tt_tok_$(Get-Random)"
        New-Item -ItemType Directory -Path $dir | Out-Null
        $file = Join-Path $dir "in.txt"
        @"
Contact: bob@example.com
"@ | Set-Content -Path $file -Encoding UTF8

        $r = Invoke-TokenReplacement -Path $file -SelectedRegexPrefixes EMAIL -LibraryPath $lib
        $text = Get-Content -Path $file -Raw
        $text | Should -Match 'EMAIL_[0-9a-f]{12}'
        $r.Matches | Should -BeGreaterThan 0
        Remove-Item $dir -Recurse -Force
    }
}
