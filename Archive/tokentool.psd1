@{
    RootModule        = 'TokenTool.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd3f9a5e2-8b4f-4c3a-9e2f-123456789abc'
    Author            = 'Copilot'
    Description       = 'Tokenization and rehydration tool with GUI, regex library, syntax highlighting, and sensitive data detection.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Process-Tokenization')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('tokenization', 'regex', 'gui', 'powershell')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/your-repo/token-tool'
            ReleaseNotes = 'Initial release with GUI, regex library, and syntax highlighting.'
        }
    }
}
