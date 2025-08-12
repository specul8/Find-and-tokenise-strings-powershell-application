# 🔐 TokenTool

TokenTool is a PowerShell-based utility for tokenizing and rehydrating sensitive data in text files. It supports regex-based pattern matching, mapping formats, and a GUI for ease of use.

---

## 🚀 Features

- Tokenize common PII types: emails, IPs, GUIDs, credit cards, phone numbers, and more
- Rehydrate tokenized files using mapping
- Supports JSON and CSV mapping formats
- GUI interface for regex testing and file preview
- Regex library for reusable patterns
- Light/Dark theme toggle
- Error logging to file and interface

---

## 📦 Installation

1. Clone or download this repository
2. Ensure PowerShell 5.1+ is installed
3. Place all files in the same folder:
   - `TokenTool.psm1`
   - `TokenToolGUI.ps1`
   - `RegexLibrary.json`
   - `README.md`

---

## 🛠️ Usage

### 🔧 Command-Line

```powershell
Import-Module .\TokenTool.psm1

# Tokenize
Process-Tokenization -sourceFilePath "input.txt" `
                     -targetFilePath "output.txt" `
                     -mappingFilePath "map.json" `
                     -MappingFormat "json" `
                     -actionType "tokenize" `
                     -ReplaceEmails `
                     -ReplaceGuids `
                     -ReplaceIPs `
                     -ReplaceCreditCards `
                     -ReplacePhoneNumbers `
                     -ReplaceTFNs `
                     -ReplaceMedicare `
                     -ReplaceDOBs `
                     -ReplacePassports `
                     -ReplaceAddresses

# Rehydrate
Process-Tokenization -sourceFilePath "output.txt" `
                     -targetFilePath "rehydrated.txt" `
                     -mappingFilePath "map.json" `
                     -MappingFormat "json" `
                     -actionType "rehydrate"
