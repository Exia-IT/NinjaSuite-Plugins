#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Updates the NinjaSuite plugin registry files based on discovered plugins.

.DESCRIPTION
    This script scans the plugins directory for all plugin.json files and automatically
    updates both plugin-index.json and repository.json with current plugin information.
    
    It categorizes plugins based on their directory structure and metadata, updates
    statistics, and maintains featured/popular/recent plugin lists.

.PARAMETER Force
    Force update even if no changes are detected

.PARAMETER Verbose
    Enable verbose output

.EXAMPLE
    .\tools\update-plugin-registry.ps1
    
.EXAMPLE
    .\tools\update-plugin-registry.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor $color
}

function Get-PluginCategory {
    param([string]$PluginPath, [object]$PluginJson)
    
    # Determine category based on path or plugin.json category
    $category = "utilities" # default
    
    if ($PluginPath -match "examples") { $category = "examples" }
    elseif ($PluginPath -match "monitoring") { $category = "monitoring" }
    elseif ($PluginPath -match "reporting") { $category = "reporting" }
    elseif ($PluginPath -match "Active Directory|AD-") { $category = "security" }
    elseif ($PluginPath -match "Management|Cluster") { $category = "utilities" }
    elseif ($PluginPath -match "automation") { $category = "automation" }
    elseif ($PluginPath -match "integration") { $category = "integration" }
    elseif ($PluginPath -match "security") { $category = "security" }
    elseif ($PluginJson.category) {
        switch ($PluginJson.category.ToLower()) {
            "monitoring" { $category = "monitoring" }
            "reporting" { $category = "reporting" }
            "examples" { $category = "examples" }
            "active directory" { $category = "security" }
            "infrastructure" { $category = "utilities" }
            "automation" { $category = "automation" }
            "integration" { $category = "integration" }
            "security" { $category = "security" }
        }
    }
    
    return $category
}

# Main execution
try {
    Write-Log "🔍 Starting plugin registry update..." "INFO"
    
    # Change to repository root
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Set-Location $repoRoot
    Write-Log "📁 Working directory: $((Get-Location).Path)" "INFO"
    
    # Find all plugin.json files
    Write-Log "🔍 Scanning for plugins..." "INFO"
    $pluginFiles = Get-ChildItem -Path "plugins" -Name "plugin.json" -Recurse
    $plugins = @()
    $categories = @{
        "automation" = @()
        "integration" = @()
        "monitoring" = @()
        "reporting" = @()
        "security" = @()
        "utilities" = @()
        "examples" = @()
    }
    
    foreach ($pluginFile in $pluginFiles) {
        $pluginPath = Split-Path $pluginFile -Parent
        $fullPath = Join-Path "plugins" $pluginPath
        
        Write-Log "📦 Processing plugin: $fullPath" "INFO"
        
        try {
            $pluginJson = Get-Content (Join-Path $fullPath "plugin.json") | ConvertFrom-Json
            
            # Get category
            $category = Get-PluginCategory -PluginPath $pluginPath -PluginJson $pluginJson
            
            # Create plugin entry
            $pluginEntry = @{
                id = if ($pluginJson.id) { $pluginJson.id } else { ($pluginJson.name -replace '\s+', '-').ToLower() }
                name = $pluginJson.name
                version = $pluginJson.version
                description = $pluginJson.description
                author = $pluginJson.author
                path = $fullPath -replace '\\', '/'
                enabled = if ($null -ne $pluginJson.enabled) { $pluginJson.enabled } else { $true }
                tags = if ($pluginJson.tags) { $pluginJson.tags } elseif ($pluginJson.keywords) { $pluginJson.keywords } else { @() }
                lastUpdated = if ($pluginJson.lastUpdated) { $pluginJson.lastUpdated } else { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") }
            }
            
            $categories[$category] += $pluginEntry
            $plugins += $pluginEntry
            
            Write-Log "✅ Added '$($pluginJson.name)' to category: $category" "INFO"
        }
        catch {
            Write-Log "⚠️ Failed to process plugin at $fullPath`: $_" "WARN"
        }
    }
    
    Write-Log "📊 Found $($plugins.Count) total plugins" "INFO"
    
    # Backup existing files
    if (Test-Path "plugin-index.json") {
        Copy-Item "plugin-index.json" "plugin-index.json.backup" -Force
    }
    if (Test-Path "repository.json") {
        Copy-Item "repository.json" "repository.json.backup" -Force
    }
    
    # Update plugin-index.json
    Write-Log "📝 Updating plugin-index.json..." "INFO"
    $pluginIndex = @{
        apiVersion = "1.0"
        lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        totalPlugins = $plugins.Count
        categories = $categories
        featured = @($plugins | Where-Object { 
            $_.tags -contains "featured" -or 
            $_.name -match "Network Scanner|AD Report|Hello World" 
        } | Select-Object -First 3 | ForEach-Object { $_.id })
        popular = @($plugins | Sort-Object { $_.tags.Count } -Descending | Select-Object -First 3 | ForEach-Object { $_.id })
        recent = @($plugins | Sort-Object lastUpdated -Descending | Select-Object -First 4 | ForEach-Object { $_.id })
    }
    
    $pluginIndex | ConvertTo-Json -Depth 10 | Set-Content "plugin-index.json" -Encoding UTF8
    Write-Log "✅ Updated plugin-index.json" "INFO"
    
    # Update repository.json statistics
    Write-Log "📝 Updating repository.json..." "INFO"
    $repoJson = Get-Content "repository.json" | ConvertFrom-Json
    $repoJson.statistics.totalPlugins = $plugins.Count
    $repoJson.statistics.lastPluginUpdate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $repoJson.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Update category counts
    foreach ($cat in $repoJson.categories) {
        $cat.pluginCount = $categories[$cat.id].Count
    }
    
    $repoJson | ConvertTo-Json -Depth 10 | Set-Content "repository.json" -Encoding UTF8
    Write-Log "✅ Updated repository.json" "INFO"
    
    # Create summary
    Write-Log "`n📋 Plugin Registry Update Summary:" "INFO"
    Write-Log "Total plugins: $($plugins.Count)" "INFO"
    foreach ($cat in $categories.Keys | Sort-Object) {
        if ($categories[$cat].Count -gt 0) {
            Write-Log "  $cat`: $($categories[$cat].Count) plugins" "INFO"
        }
    }
    
    Write-Log "`n🎉 Plugin registry update completed successfully!" "INFO"
}
catch {
    Write-Log "❌ Error updating plugin registry: $_" "ERROR"
    
    # Restore backups if they exist
    if (Test-Path "plugin-index.json.backup") {
        Copy-Item "plugin-index.json.backup" "plugin-index.json" -Force
        Write-Log "📄 Restored plugin-index.json from backup" "INFO"
    }
    if (Test-Path "repository.json.backup") {
        Copy-Item "repository.json.backup" "repository.json" -Force
        Write-Log "📄 Restored repository.json from backup" "INFO"
    }
    
    exit 1
}