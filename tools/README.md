# 🛠️ NinjaSuite Plugin Repository Tools

This directory contains utility scripts for managing and maintaining the NinjaSuite plugin repository.

## Scripts Overview

### 📊 `update-plugin-registry.ps1`

Automatically updates the plugin registry files (`plugin-index.json` and `repository.json`) based on discovered plugins in the repository.

**Usage:**
```powershell
# Standard update
.\tools\update-plugin-registry.ps1

# Force update (even if no changes detected)
.\tools\update-plugin-registry.ps1 -Force
```

**What it does:**
- Scans all plugins in the `plugins/` directory
- Reads each `plugin.json` file for metadata
- Categorizes plugins based on directory structure and metadata
- Updates `plugin-index.json` with current plugin inventory
- Updates `repository.json` statistics and category counts
- Creates backup files before making changes
- Provides detailed logging and summary

### 🔍 `validate-plugins.ps1`

Validates all plugins in the repository for compliance and correctness.

**Usage:**
```powershell
# Validate all plugins
.\tools\validate-plugins.ps1

# Validate with attempt to fix issues
.\tools\validate-plugins.ps1 -Fix

# Validate specific directory
.\tools\validate-plugins.ps1 -Path "plugins/monitoring"
```

**What it validates:**
- Required fields in `plugin.json` (name, version, description, author)
- Semantic versioning format
- File references (PowerShell modules, XAML files)
- Plugin structure compliance
- Category validity
- Documentation presence

## GitHub Actions Integration

### 🤖 Auto-Update Workflow

The repository includes a GitHub Actions workflow (`.github/workflows/update-plugin-registry.yml`) that automatically:

- **Triggers on:**
  - Push to `main` branch with plugin changes
  - Pull requests affecting plugin files
  - Manual workflow dispatch

- **Actions:**
  - Scans for plugin changes
  - Updates registry files
  - Commits changes automatically
  - Provides detailed summary reports

### Workflow Features

- ✅ **Automatic Detection**: Monitors changes to `plugin.json`, `.psm1`, and `.xaml` files
- ✅ **Smart Updates**: Only commits when actual changes are detected
- ✅ **Backup Safety**: Creates backups before making changes
- ✅ **Detailed Reporting**: Provides comprehensive summary in GitHub Actions logs
- ✅ **Error Handling**: Rolls back changes if errors occur

## Development Workflow

### Adding a New Plugin

1. **Create Plugin Structure:**
   ```
   plugins/[category]/[plugin-name]/
   ├── plugin.json          # Required: Plugin metadata
   ├── PluginName.psm1      # Required: PowerShell module
   ├── PluginName.xaml      # Optional: UI definition
   ├── README.md            # Recommended: Documentation
   └── settings.xaml        # Optional: Settings UI
   ```

2. **Validate Plugin:**
   ```powershell
   .\tools\validate-plugins.ps1
   ```

3. **Update Registry:**
   ```powershell
   .\tools\update-plugin-registry.ps1
   ```

4. **Commit Changes:**
   ```bash
   git add .
   git commit -m "Add new plugin: [Plugin Name]"
   git push
   ```

The GitHub Actions workflow will automatically update the registry on push.

### Modifying Existing Plugins

1. **Make Changes** to plugin files
2. **Validate** using the validation script
3. **Commit** changes - registry will auto-update via GitHub Actions

### Manual Registry Updates

If you need to manually update the registry (e.g., for testing):

```powershell
# Update registry
.\tools\update-plugin-registry.ps1

# Check for any issues
.\tools\validate-plugins.ps1

# View the updated files
Get-Content plugin-index.json | ConvertFrom-Json
Get-Content repository.json | ConvertFrom-Json
```

## Plugin Categories

The system recognizes these standard categories:

- **automation** - Task automation and workflow optimization
- **integration** - Third-party service and API integration
- **monitoring** - System monitoring and alerting
- **reporting** - Data analysis and reporting
- **security** - Security monitoring and compliance
- **utilities** - General utility and helper tools
- **examples** - Example plugins for learning

Plugins are automatically categorized based on:
1. Directory structure (`plugins/[category]/`)
2. `category` field in `plugin.json`
3. Path-based heuristics for common patterns

## Troubleshooting

### Common Issues

**Plugin not appearing in registry:**
- Ensure `plugin.json` exists and is valid JSON
- Run validation script to check for errors
- Verify plugin is in correct directory structure

**Registry not updating:**
- Check GitHub Actions logs for errors
- Run update script locally to test
- Ensure proper permissions for GitHub Actions

**Validation failures:**
- Review validation output for specific issues
- Ensure all required fields are present in `plugin.json`
- Check file references are correct

### Getting Help

- Check GitHub Actions workflow logs
- Run validation script for detailed error information
- Review plugin examples in `plugins/examples/`
- Consult repository documentation in `docs/`

## Script Maintenance

These scripts are designed to be self-maintaining, but may need updates when:
- New plugin schema requirements are added
- Additional validation rules are needed
- Category structure changes
- GitHub Actions workflow needs enhancement

Regular maintenance tasks:
- Monitor validation warnings
- Update category definitions as needed
- Review and update automation workflows
- Keep backup and recovery procedures current