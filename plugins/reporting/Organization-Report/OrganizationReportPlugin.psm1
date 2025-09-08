# OrganizationReportPlugin.psm1
# Organization Report Plugin for NinjaSuite

function Initialize-OrganizationReportPlugin {
    <#
    .SYNOPSIS
    Initializes the Organization Report plugin.
    #>
    param($TabItem)
    
    # Store the TabItem reference for UI control access
    $script:PluginTabItem = $TabItem
    
    Write-SafeLog "Organization Report plugin initialized" 'INFO'
    
    # Get UI controls
    $orgSelect = Get-UIControl -Name 'OrgReportOrgSelect'
    $refreshOrgsBtn = Get-UIControl -Name 'OrgReportRefreshOrgs'
    $generateBtn = Get-UIControl -Name 'OrgReportGenerate'
    $cancelBtn = Get-UIControl -Name 'OrgReportCancel'
    $progressBar = Get-UIControl -Name 'OrgReportProgress'
    $statusText = Get-UIControl -Name 'OrgReportStatus'
    $logBox = Get-UIControl -Name 'OrgReportLog'
    $htmlPathBox = Get-UIControl -Name 'OrgRptHtmlPath'
    $browseBtn = Get-UIControl -Name 'OrgRptBrowseHtml'
    
    # Set default output path
    $defaultPath = Join-Path $env:TEMP ("Organization-Report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.html')
    if ($htmlPathBox) {
        $htmlPathBox.Text = $defaultPath
    }
    
    # Global cancellation flag
    $script:CancelFlag = [ref]$false
    
    # Event handlers
    if ($refreshOrgsBtn) {
        $refreshOrgsBtn.Add_Click({ Refresh-Organizations })
    }
    if ($browseBtn) {
        $browseBtn.Add_Click({ Browse-OutputPath })
    }
    if ($generateBtn) {
        $generateBtn.Add_Click({ Start-OrganizationReportGeneration })
    }
    if ($cancelBtn -and $statusText) {
        $cancelBtn.Add_Click({ 
            $script:CancelFlag.Value = $true
            if ($statusText) { $statusText.Text = "Cancellation requested..." }
            Write-SafeLog "Organization report cancellation requested" 'WARN'
        })
    }
    
    # Load organizations on startup only if controls are available
    if ($orgSelect -and $statusText) {
        Refresh-Organizations
    } else {
        Write-SafeLog "UI controls not available during initialization - will load organizations when UI is ready" 'DEBUG'
    }
}

function Refresh-Organizations {
    $orgSelect = Get-UIControl -Name 'OrgReportOrgSelect'
    $statusText = Get-UIControl -Name 'OrgReportStatus'
    
    try {
        if ($statusText) {
            $statusText.Text = "Loading organizations..."
        }
        Write-SafeLog "Loading organizations from NinjaOne..." 'INFO'
        
        $config = Get-NinjaSuiteConfig
        $tokenInfo = Get-NinjaOneAccessToken -Instance $config.NinjaOne.Instance -ClientId $config.NinjaOne.ClientId -ClientSecret $config.NinjaOne.ClientSecret
        if (-not $tokenInfo) {
            throw "Token acquisition failed"
        }
        $organizations = Get-NinjaOneOrganizationsAPI -TokenInfo $tokenInfo
        
        if ($orgSelect) {
            $orgSelect.Items.Clear()
            foreach ($org in $organizations) {
                $item = [PSCustomObject]@{
                    Name = $org.name
                    Id = $org.id
                }
                $orgSelect.Items.Add($item)
            }
            
            if ($organizations.Count -gt 0) {
                $orgSelect.SelectedIndex = 0
            }
        }
        
        if ($statusText) {
            $statusText.Text = "Ready - $($organizations.Count) organizations loaded"
        }
        Write-SafeLog "Loaded $($organizations.Count) organizations" 'INFO'
    } catch {
        if ($statusText) {
            $statusText.Text = "Failed to load organizations"
        }
        Write-SafeLog "Failed to load organizations: $($_.Exception.Message)" 'ERROR'
    }
}

function Browse-OutputPath {
    $htmlPathBox = Get-UIControl -Name 'OrgRptHtmlPath'
    
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "HTML files (*.html)|*.html|All files (*.*)|*.*"
    $dialog.DefaultExt = "html"
    $dialog.FileName = "Organization-Report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".html"
    
    if ($dialog.ShowDialog() -eq $true -and $htmlPathBox) {
        $htmlPathBox.Text = $dialog.FileName
    }
}

function Start-OrganizationReportGeneration {
    # Get UI controls
    $orgSelect = Get-UIControl -Name 'OrgReportOrgSelect'
    $generateBtn = Get-UIControl -Name 'OrgReportGenerate'
    $cancelBtn = Get-UIControl -Name 'OrgReportCancel'
    $progressBar = Get-UIControl -Name 'OrgReportProgress'
    $statusText = Get-UIControl -Name 'OrgReportStatus'
    $logBox = Get-UIControl -Name 'OrgReportLog'
    $htmlPathBox = Get-UIControl -Name 'OrgRptHtmlPath'
    $chkSaveHtml = Get-UIControl -Name 'OrgRptSaveHtml'
    $chkEmail = Get-UIControl -Name 'OrgRptEmail'
    $emailTo = Get-UIControl -Name 'OrgRptEmailTo'
    $chkDevices = Get-UIControl -Name 'OrgRptIncludeDevices'
    $chkLocations = Get-UIControl -Name 'OrgRptIncludeLocations'
    $chkM365 = Get-UIControl -Name 'OrgRptIncludeM365'
    $chkDiagnostics = Get-UIControl -Name 'OrgRptDiagnostics'
    $chkOpenAfter = Get-UIControl -Name 'OrgRptOpenAfter'
    
    if (-not $orgSelect.SelectedItem) {
        Write-SafeLog "Please select an organization" 'WARN'
        return
    }
    
    # Reset cancellation flag
    $script:CancelFlag.Value = $false
    
    # Update UI state
    $generateBtn.IsEnabled = $false
    $cancelBtn.IsEnabled = $true
    $progressBar.Visibility = 'Visible'
    $progressBar.Value = 0
    $statusText.Text = "Starting organization report generation..."
    $logBox.Clear()
    
    # Get selected organization
    $selectedOrg = $orgSelect.SelectedItem
    $orgId = $selectedOrg.Id
    $orgName = $selectedOrg.Name
    
    # Get options
    $outputPath = if ($chkSaveHtml.IsChecked) { $htmlPathBox.Text } else { $null }
    $includeDevices = $chkDevices.IsChecked
    $includeLocations = $chkLocations.IsChecked
    $includeM365 = $chkM365.IsChecked
    $includeDiagnostics = $chkDiagnostics.IsChecked
    $openAfter = $chkOpenAfter.IsChecked
    
    Write-SafeLog "Generating organization report for: $orgName (ID: $orgId)" 'INFO'
    
    # Progress callback
    $progressCallback = {
        param($percent, $message)
        try {
            $progressBar.Value = $percent
            $statusText.Text = $message
            $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $message`r`n")
            $logBox.ScrollToEnd()
        } catch {
            Write-SafeLog "Progress update failed: $($_.Exception.Message)" 'DEBUG'
        }
    }
    
    # Start background job
    $job = Start-Job -ScriptBlock {
        param($OrgId, $OrgName, $OutputPath, $IncludeDevices, $IncludeLocations, $IncludeM365, $IncludeDiagnostics, $OpenAfter, $ProgressCallback, $Config, $CancelFlag)
        
        try {
            # Import required modules (if needed)
            
            # Generate the report
            $result = Generate-OrganizationReport -OrganizationId $OrgId -OrganizationName $OrgName -OutputPath $OutputPath -IncludeDevices $IncludeDevices -IncludeLocations $IncludeLocations -IncludeM365 $IncludeM365 -IncludeDiagnostics $IncludeDiagnostics -ProgressCallback $ProgressCallback -Config $Config -CancelFlag $CancelFlag
            
            if ($OpenAfter -and $result.OutputPath -and (Test-Path $result.OutputPath)) {
                Start-Process $result.OutputPath
            }
            
            return @{ Success = $true; OutputPath = $result.OutputPath; Data = $result.Data }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    } -ArgumentList $orgId, $orgName, $outputPath, $includeDevices, $includeLocations, $includeM365, $includeDiagnostics, $openAfter, $progressCallback, (Get-NinjaSuiteConfig), $script:CancelFlag
    
    # Monitor job completion
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($job.State -eq 'Completed') {
            $timer.Stop()
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            # Update UI
            $generateBtn.IsEnabled = $true
            $cancelBtn.IsEnabled = $false
            $progressBar.Visibility = 'Collapsed'
            
            if ($result.Success) {
                $statusText.Text = "Organization report completed successfully"
                Write-SafeLog "Organization report generated: $($result.OutputPath)" 'INFO'
                
                # Email if requested
                if ($chkEmail.IsChecked -and $emailTo.Text) {
                    Send-OrganizationReportEmail -OutputPath $result.OutputPath -Recipient $emailTo.Text -OrganizationName $orgName
                }
            } else {
                $statusText.Text = "Organization report failed"
                Write-SafeLog "Organization report failed: $($result.Error)" 'ERROR'
            }
        } elseif ($job.State -eq 'Failed') {
            $timer.Stop()
            $error = Receive-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job
            
            $generateBtn.IsEnabled = $true
            $cancelBtn.IsEnabled = $false
            $progressBar.Visibility = 'Collapsed'
            $statusText.Text = "Organization report failed"
            Write-SafeLog "Organization report job failed: $error" 'ERROR'
        }
    })
    $timer.Start()
}

function Generate-OrganizationReport {
    param(
        [int]$OrganizationId,
        [string]$OrganizationName,
        [string]$OutputPath,
        [bool]$IncludeDevices,
        [bool]$IncludeLocations,
        [bool]$IncludeM365,
        [bool]$IncludeDiagnostics,
        [scriptblock]$ProgressCallback,
        [hashtable]$Config,
        [ref]$CancelFlag
    )
    
    if ($ProgressCallback) { & $ProgressCallback 10 "Connecting to NinjaOne API..." }
    
    # Get token
    $tokenInfo = Get-NinjaOneAccessToken -Instance $Config.NinjaOne.Instance -ClientId $Config.NinjaOne.ClientId -ClientSecret $Config.NinjaOne.ClientSecret
    if (-not $tokenInfo) {
        throw "Token acquisition failed"
    }
    
    # Get organization details
    if ($ProgressCallback) { & $ProgressCallback 20 "Retrieving organization details..." }
    $orgDetails = Get-NinjaOneOrganizationAPI -TokenInfo $tokenInfo -OrganizationId $OrganizationId
    
    $reportData = @{
        Organization = $orgDetails
        Devices = @()
        Locations = @()
        M365Data = @{}
        GeneratedAt = Get-Date
    }
    
    if ($IncludeDevices) {
        if ($CancelFlag.Value) { throw "Cancelled by user" }
        if ($ProgressCallback) { & $ProgressCallback 30 "Retrieving devices..." }
        $reportData.Devices = Get-NinjaOneDevicesAPI -TokenInfo $tokenInfo -OrganizationId $OrganizationId
    }
    
    if ($IncludeLocations) {
        if ($CancelFlag.Value) { throw "Cancelled by user" }
        if ($ProgressCallback) { & $ProgressCallback 50 "Retrieving locations..." }
        $reportData.Locations = Get-NinjaOneLocationsAPI -TokenInfo $tokenInfo -OrganizationId $OrganizationId
    }
    
    if ($IncludeM365) {
        if ($CancelFlag.Value) { throw "Cancelled by user" }
        if ($ProgressCallback) { & $ProgressCallback 70 "Retrieving Microsoft 365 data..." }
        # M365 data retrieval would go here
        $reportData.M365Data = @{ Note = "M365 integration not yet implemented" }
    }
    
    # Generate HTML
    if ($CancelFlag.Value) { throw "Cancelled by user" }
    if ($ProgressCallback) { & $ProgressCallback 90 "Generating HTML report..." }
    
    $html = Generate-OrganizationReportHTML -Data $reportData -IncludeDiagnostics $IncludeDiagnostics
    
    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $html | Out-File -FilePath $OutputPath -Encoding UTF8
    }
    
    if ($ProgressCallback) { & $ProgressCallback 100 "Report generation completed" }
    
    return @{ OutputPath = $OutputPath; Data = $reportData }
}

function Generate-OrganizationReportHTML {
    param(
        [hashtable]$Data,
        [bool]$IncludeDiagnostics
    )
    
    $org = $Data.Organization
    $devices = $Data.Devices
    $locations = $Data.Locations
    $generatedAt = $Data.GeneratedAt
    
    $css = Get-NinjaSuiteHtmlThemeCss -Theme 'Light'
    
    $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <title>Organization Report - $($org.name)</title>
    <style>$css</style>
</head>
<body>
    <div class='container'>
        <h1>Organization Report: $($org.name)</h1>
        <p><strong>Generated:</strong> $($generatedAt.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        
        <h2>Organization Summary</h2>
        <table>
            <tr><td><strong>Organization ID:</strong></td><td>$($org.id)</td></tr>
            <tr><td><strong>Name:</strong></td><td>$($org.name)</td></tr>
            <tr><td><strong>Total Devices:</strong></td><td>$($devices.Count)</td></tr>
            <tr><td><strong>Total Locations:</strong></td><td>$($locations.Count)</td></tr>
        </table>
        
        <h2>Device Breakdown</h2>
        <table>
            <thead>
                <tr><th>Device Class</th><th>Count</th></tr>
            </thead>
            <tbody>
"@
    
    if ($devices.Count -gt 0) {
        $deviceGroups = $devices | Group-Object nodeClass
        foreach ($group in $deviceGroups) {
            $html += "<tr><td>$($group.Name)</td><td>$($group.Count)</td></tr>"
        }
    } else {
        $html += "<tr><td colspan='2'>No devices found</td></tr>"
    }
    
    $html += @"
            </tbody>
        </table>
        
        <h2>Location Breakdown</h2>
        <table>
            <thead>
                <tr><th>Location</th><th>Device Count</th></tr>
            </thead>
            <tbody>
"@
    
    if ($locations.Count -gt 0) {
        foreach ($location in $locations) {
            $locationDevices = $devices | Where-Object { $_.locationId -eq $location.id }
            $html += "<tr><td>$($location.name)</td><td>$($locationDevices.Count)</td></tr>"
        }
    } else {
        $html += "<tr><td colspan='2'>No locations found</td></tr>"
    }
    
    $html += @"
            </tbody>
        </table>
        
        <div class='timestamp'>Report generated by NinjaSuite on $($generatedAt.ToString('dd-MM-yyyy HH:mm'))</div>
    </div>
</body>
</html>
"@
    
    return $html
}

function Send-OrganizationReportEmail {
    param(
        [string]$OutputPath,
        [string]$Recipient,
        [string]$OrganizationName
    )
    
    try {
        $config = Get-NinjaSuiteConfig
        if ($config.SMTP -and $config.SMTP.Server) {
            $params = @{
                SmtpServer = $config.SMTP.Server
                Port = $config.SMTP.Port
                From = $config.SMTP.From
                To = $Recipient
                Subject = "NinjaSuite Organization Report - $OrganizationName - $(Get-Date -Format 'yyyy-MM-dd')"
                Body = "Please find the attached organization report for $OrganizationName generated by NinjaSuite."
                Attachments = $OutputPath
            }
            
            if ($config.SMTP.UseSsl) {
                $params.UseSsl = $true
            }
            
            if ($config.SMTP.Username -and $config.SMTP.Password) {
                $securePassword = ConvertTo-SecureString $config.SMTP.Password -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential($config.SMTP.Username, $securePassword)
                $params.Credential = $credential
            }
            
            Send-MailMessage @params
            Write-SafeLog "Organization report emailed to $Recipient" 'INFO'
        } else {
            Write-SafeLog "SMTP not configured, skipping email" 'WARN'
        }
    } catch {
        Write-SafeLog "Failed to email report: $($_.Exception.Message)" 'ERROR'
    }
}

function Write-SafeLog {
    param($Message, $Level = 'INFO')
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level
    } else {
        $color = switch($Level) { 
            'ERROR' {'Red'} 
            'WARN' {'Yellow'} 
            'INFO' {'Green'} 
            'DEBUG' {'Cyan'}
            default {'White'} 
        }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

# UI Control Helper Function
function Get-UIControl {
    param($Name)
    try {
        # Use stored TabItem reference first
        if ($script:PluginTabItem -and $script:PluginTabItem.Content) {
            $control = $script:PluginTabItem.Content.FindName($Name)
            if ($control) {
                return $control
            }
        }
        
        # Fallback: try to find the Organization Report tab
        $windows = [System.Windows.Application]::Current.Windows
        foreach ($window in $windows) {
            if ($window.Content) {
                # Try to find MainTabs control
                $mainTabs = $window.Content.FindName('MainTabs')
                if ($mainTabs) {
                    foreach ($tabItem in $mainTabs.Items) {
                        if ($tabItem.Tag -eq "Organization Report" -or $tabItem.Header -eq "Org Report") {
                            $control = $tabItem.Content.FindName($Name)
                            if ($control) {
                                return $control
                            }
                        }
                    }
                }
            }
        }
        
        # Last fallback: search all windows for the control
        foreach ($window in $windows) {
            $control = $window.FindName($Name)
            if ($control) {
                return $control
            }
        }
        
        return $null
    } catch {
        Write-SafeLog "Error finding UI control '$Name': $($_.Exception.Message)" 'WARN'
        return $null
    }
}

# Export functions for the plugin system
Export-ModuleMember -Function Initialize-OrganizationReportPlugin

# Auto-initialize when module is loaded
Write-SafeLog "Organization Report plugin module loaded" 'DEBUG'
