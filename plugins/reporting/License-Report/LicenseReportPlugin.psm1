# LicenseReportPlugin.psm1
# License Report Plugin for NinjaSuite

function Initialize-LicenseReportPlugin {
    <#
    .SYNOPSIS
    Initializes the License Report plugin.
    #>
    
    Write-SafeLog "License Report plugin initialized" 'INFO'
    
    # Get UI controls
    $runButton = Get-UIControl -Name 'RunLicenseReport'
    $cancelButton = Get-UIControl -Name 'CancelLicenseReport'
    $progressBar = Get-UIControl -Name 'LicenseProgress'
    $statusText = Get-UIControl -Name 'LicenseStatus'
    $logBox = Get-UIControl -Name 'LicenseLog'
    $htmlPathBox = Get-UIControl -Name 'HtmlPathBox'
    $browseButton = Get-UIControl -Name 'BrowseHtml'
    
    # Set default output path
    $defaultPath = Join-Path $env:TEMP ("NinjaRMM-AD-Report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.html')
    if ($htmlPathBox) {
        $htmlPathBox.Text = $defaultPath
    }
    
    # Browse button event
    if ($browseButton) {
        $browseButton.Add_Click({
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.Filter = "HTML files (*.html)|*.html|All files (*.*)|*.*"
            $dialog.DefaultExt = "html"
            $dialog.FileName = "License-Report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".html"
            
            if ($dialog.ShowDialog() -eq $true) {
                if ($htmlPathBox) {
                    $htmlPathBox.Text = $dialog.FileName
                }
            }
        })
    }
    
    # Global cancellation flag
    $script:CancelFlag = [ref]$false
    
    # Run button event
    if ($runButton) {
        $runButton.Add_Click({
            Start-LicenseReportGeneration
        })
    }

    # Cancel button event
    if ($cancelButton -and $statusText) {
        $cancelButton.Add_Click({
            $script:CancelFlag.Value = $true
            $statusText.Text = "Cancellation requested..."
            Write-SafeLog "License report cancellation requested" 'WARN'
        })
    }
}

function Start-LicenseReportGeneration {
    # Get UI controls
    $runButton = Get-UIControl -Name 'RunLicenseReport'
    $cancelButton = Get-UIControl -Name 'CancelLicenseReport'
    $progressBar = Get-UIControl -Name 'LicenseProgress'
    $statusText = Get-UIControl -Name 'LicenseStatus'
    $logBox = Get-UIControl -Name 'LicenseLog'
    $htmlPathBox = Get-UIControl -Name 'HtmlPathBox'
    $chkSaveHtml = Get-UIControl -Name 'ChkSaveHtml'
    $chkEmail = Get-UIControl -Name 'ChkEmail'
    $emailRecipient = Get-UIControl -Name 'EmailRecipient'
    $chkParallel = Get-UIControl -Name 'ChkParallel'
    $parallelThrottle = Get-UIControl -Name 'ParallelThrottle'
    $chkOpenAfter = Get-UIControl -Name 'ChkOpenAfter'
    
    # Reset cancellation flag
    $script:CancelFlag.Value = $false
    
    # Update UI state
    $runButton.IsEnabled = $false
    $cancelButton.IsEnabled = $true
    $progressBar.Visibility = 'Visible'
    $progressBar.Value = 0
    $statusText.Text = "Starting license report generation..."
    $logBox.Clear()
    
    # Get configuration
    $config = Get-NinjaSuiteConfig
    
    # Prepare context
    $context = @{
        NinjaOne = @{
            Instance = $config.NinjaOne.Instance
            ClientId = $config.NinjaOne.ClientId
            ClientSecret = $config.NinjaOne.ClientSecret
        }
        Config = $config
        CancelFlag = $script:CancelFlag
    }
    
    # Get options
    $outputPath = if ($chkSaveHtml.IsChecked) { $htmlPathBox.Text } else { $null }
    $parallel = if ($chkParallel.IsChecked) { $true } else { $false }
    $throttle = try { [int]$parallelThrottle.Text } catch { 8 }
    $openAfter = if ($chkOpenAfter.IsChecked) { $true } else { $false }
    
    # Progress callback
    $progressCallback = {
        param($percent, $message)
        try {
            $progressBar.Value = $percent
            $statusText.Text = $message
            Write-SafeLog $message 'INFO'
        } catch {
            Write-SafeLog "Progress update failed: $($_.Exception.Message)" 'DEBUG'
        }
    }
    
    # Start background job
    $job = Start-Job -ScriptBlock {
        param($Context, $OutputPath, $LogBox, $OpenAfter, $ProgressCallback, $Parallel, $Throttle)
        
        # Import required modules in job
        Import-Module LicenseReport -Force
        
        try {
            Invoke-LicenseReportTask -Context $Context -OutputPath $OutputPath -LogBox $LogBox -OpenAfterRun $OpenAfter -ProgressCallback $ProgressCallback -Parallel:$Parallel -ParallelThrottle $Throttle
            return @{ Success = $true; OutputPath = $OutputPath }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    } -ArgumentList $context, $outputPath, $logBox, $openAfter, $progressCallback, $parallel, $throttle
    
    # Monitor job completion
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($job.State -eq 'Completed') {
            $timer.Stop()
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            # Update UI
            $runButton.IsEnabled = $true
            $cancelButton.IsEnabled = $false
            $progressBar.Visibility = 'Collapsed'
            
            if ($result.Success) {
                $statusText.Text = "License report completed successfully"
                Write-SafeLog "License report generated: $($result.OutputPath)" 'INFO'
                
                # Email if requested
                if ($chkEmail.IsChecked -and $emailRecipient.Text) {
                    Send-LicenseReportEmail -OutputPath $result.OutputPath -Recipient $emailRecipient.Text
                }
            } else {
                $statusText.Text = "License report failed"
                Write-SafeLog "License report failed: $($result.Error)" 'ERROR'
            }
        } elseif ($job.State -eq 'Failed') {
            $timer.Stop()
            $error = Receive-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job
            
            $runButton.IsEnabled = $true
            $cancelButton.IsEnabled = $false
            $progressBar.Visibility = 'Collapsed'
            $statusText.Text = "License report failed"
            Write-SafeLog "License report job failed: $error" 'ERROR'
        }
    })
    $timer.Start()
}

function Send-LicenseReportEmail {
    param(
        [string]$OutputPath,
        [string]$Recipient
    )
    
    try {
        $config = Get-NinjaSuiteConfig
        if ($config.SMTP -and $config.SMTP.Server) {
            $params = @{
                SmtpServer = $config.SMTP.Server
                Port = $config.SMTP.Port
                From = $config.SMTP.From
                To = $Recipient
                Subject = "NinjaSuite License Report - $(Get-Date -Format 'yyyy-MM-dd')"
                Body = "Please find the attached license report generated by NinjaSuite."
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
            Write-SafeLog "License report emailed to $Recipient" 'INFO'
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

# Export functions for the plugin system
Export-ModuleMember -Function Initialize-LicenseReportPlugin, Start-LicenseReportGeneration, Send-LicenseReportEmail

# Auto-initialize when module is loaded
Write-SafeLog "License Report plugin module loaded" 'DEBUG'
