#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates NinjaSuite plugins for compliance and correctness.

.DESCRIPTION
    This script validates all plugins in the repository to ensure they meet
    the required standards and have proper configuration files.

.PARAMETER Path
    Path to plugins directory (defaults to ./plugins)

.PARAMETER Fix
    Attempt to fix common issues automatically

.EXAMPLE
    .\tools\validate-plugins.ps1
    
.EXAMPLE
    .\tools\validate-plugins.ps1 -Fix
#>

[CmdletBinding()]
param(
    [string]$Path = "plugins",
    [switch]$Fix
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor $color
}

function Test-PluginStructure {
    param([string]$PluginPath, [object]$PluginJson)
    
    $issues = @()
    $warnings = @()
    
    # Check for PowerShell module
    $psmFiles = Get-ChildItem -Path $PluginPath -Filter "*.psm1"
    if ($psmFiles.Count -eq 0) {
        $issues += "Missing PowerShell module (.psm1 file)"
    } elseif ($psmFiles.Count -gt 1) {
        $warnings += "Multiple PowerShell modules found - consider consolidating"
    }
    
    # Check for XAML UI if specified
    if ($PluginJson.files -and $PluginJson.files.xaml) {
        $xamlFile = Join-Path $PluginPath $PluginJson.files.xaml
        if (-not (Test-Path $xamlFile)) {
            $issues += "XAML file specified in plugin.json but not found: $($PluginJson.files.xaml)"
        }
    }
    
    # Check for README
    if (-not (Test-Path (Join-Path $PluginPath "README.md"))) {
        $warnings += "Missing README.md file"
    }
    
    return @{
        Issues = $issues
        Warnings = $warnings
    }
}

function Test-PluginJson {
    param([object]$PluginJson, [string]$PluginPath)
    
    $issues = @()
    $warnings = @()
    
    # Required fields
    $requiredFields = @("name", "version", "description", "author")
    foreach ($field in $requiredFields) {
        if (-not $PluginJson.$field) {
            $issues += "Missing required field: $field"
        }
    }
    
    # Version format validation
    if ($PluginJson.version -and $PluginJson.version -notmatch '^\d+\.\d+\.\d+') {
        $warnings += "Version should follow semantic versioning (x.y.z)"
    }
    
    # Category validation
    $validCategories = @("automation", "integration", "monitoring", "reporting", "security", "utilities", "examples")
    if ($PluginJson.category -and $PluginJson.category.ToLower() -notin $validCategories) {
        $warnings += "Category '$($PluginJson.category)' is not in standard categories"
    }
    
    # Files section validation
    if ($PluginJson.files) {
        if ($PluginJson.files.module) {
            $moduleFile = Join-Path $PluginPath $PluginJson.files.module
            if (-not (Test-Path $moduleFile)) {
                $issues += "Module file specified but not found: $($PluginJson.files.module)"
            }
        }
    }
    
    return @{
        Issues = $issues
        Warnings = $warnings
    }
}

# Main execution
try {
    Write-Log "🔍 Starting plugin validation..." "INFO"
    
    if (-not (Test-Path $Path)) {
        Write-Log "❌ Plugins directory not found: $Path" "ERROR"
        exit 1
    }
    
    $pluginDirs = Get-ChildItem -Path $Path -Directory -Recurse | Where-Object { 
        Test-Path (Join-Path $_.FullName "plugin.json") 
    }
    
    $totalPlugins = $pluginDirs.Count
    $validPlugins = 0
    $pluginsWithIssues = 0
    $pluginsWithWarnings = 0
    
    Write-Log "📦 Found $totalPlugins plugins to validate" "INFO"
    Write-Log "" "INFO"
    
    foreach ($pluginDir in $pluginDirs) {
        $relativePath = $pluginDir.FullName.Substring((Get-Location).Path.Length + 1)
        Write-Log "🔍 Validating: $relativePath" "INFO"
        
        try {
            # Load plugin.json
            $pluginJsonPath = Join-Path $pluginDir.FullName "plugin.json"
            $pluginJson = Get-Content $pluginJsonPath | ConvertFrom-Json
            
            # Validate plugin.json
            $jsonValidation = Test-PluginJson -PluginJson $pluginJson -PluginPath $pluginDir.FullName
            
            # Validate plugin structure
            $structureValidation = Test-PluginStructure -PluginPath $pluginDir.FullName -PluginJson $pluginJson
            
            $allIssues = $jsonValidation.Issues + $structureValidation.Issues
            $allWarnings = $jsonValidation.Warnings + $structureValidation.Warnings
            
            if ($allIssues.Count -eq 0) {
                Write-Log "  ✅ Plugin '$($pluginJson.name)' is valid" "SUCCESS"
                $validPlugins++
            } else {
                Write-Log "  ❌ Plugin '$($pluginJson.name)' has issues:" "ERROR"
                foreach ($issue in $allIssues) {
                    Write-Log "    • $issue" "ERROR"
                }
                $pluginsWithIssues++
            }
            
            if ($allWarnings.Count -gt 0) {
                Write-Log "  ⚠️ Plugin '$($pluginJson.name)' has warnings:" "WARN"
                foreach ($warning in $allWarnings) {
                    Write-Log "    • $warning" "WARN"
                }
                $pluginsWithWarnings++
            }
        }
        catch {
            Write-Log "  ❌ Failed to validate plugin: $_" "ERROR"
            $pluginsWithIssues++
        }
        
        Write-Log "" "INFO"
    }
    
    # Summary
    Write-Log "📊 Validation Summary:" "INFO"
    Write-Log "  Total plugins: $totalPlugins" "INFO"
    Write-Log "  Valid plugins: $validPlugins" "SUCCESS"
    Write-Log "  Plugins with issues: $pluginsWithIssues" "ERROR"
    Write-Log "  Plugins with warnings: $pluginsWithWarnings" "WARN"
    
    $successRate = if ($totalPlugins -gt 0) { [math]::Round(($validPlugins / $totalPlugins) * 100, 1) } else { 0 }
    Write-Log "  Success rate: $successRate%" "INFO"
    
    if ($pluginsWithIssues -eq 0) {
        Write-Log "`n🎉 All plugins passed validation!" "SUCCESS"
        exit 0
    } else {
        Write-Log "`n⚠️ Some plugins have issues that need attention." "WARN"
        exit 1
    }
}
catch {
    Write-Log "❌ Error during validation: $_" "ERROR"
    exit 1
}