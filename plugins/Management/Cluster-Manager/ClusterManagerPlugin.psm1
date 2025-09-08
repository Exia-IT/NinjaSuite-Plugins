# ClusterManagerPlugin.psm1
# Cluster Manager Plugin for NinjaSuite

function Initialize-ClusterManagerPlugin {
    <#
    .SYNOPSIS
    Initializes the Cluster Manager plugin (basic initialization only).
    #>
    
    Write-SafeLog "Cluster Manager plugin initialized" 'INFO'
    
    # Get configuration if available
    $config = $null
    try {
        if (Get-Command "Get-NinjaSuiteConfig" -ErrorAction SilentlyContinue) {
            $config = Get-NinjaSuiteConfig
        }
    } catch {
        Write-SafeLog "Configuration not available during plugin initialization" 'DEBUG'
    }
    
    # State container (plugin local)
    $script:ClusterState = [ordered]@{
        ClusterName = $null
        ClusterNodes = @()
        Matched = @{}
        Config = $config
        UIInitialized = $false
    }
    
    Write-SafeLog "Cluster Manager plugin basic initialization complete" 'INFO'
}

function Initialize-ClusterManagerUI {
    <#
    .SYNOPSIS
    Initializes the UI components for the Cluster Manager plugin.
    This should be called only when UI is available.
    #>
    
    if ($script:ClusterState.UIInitialized) {
        return
    }
    
    Write-SafeLog "Initializing Cluster Manager UI" 'INFO'
    
    try {
        # Get UI controls
        $clusterNameBox = Get-UIControl -Name 'ClusterNameBox'
        $connectBtn = Get-UIControl -Name 'ConnectClusterBtn'
        $refreshBtn = Get-UIControl -Name 'RefreshNodesBtn'
        $openFullBtn = Get-UIControl -Name 'OpenFullBtn'
        $clusterNodesList = Get-UIControl -Name 'ClusterNodesList'
        $matchBtn = Get-UIControl -Name 'MatchBtn'
        $maintStartBtn = Get-UIControl -Name 'MaintStartBtn'
        $maintEndBtn = Get-UIControl -Name 'MaintEndBtn'
        $pauseDrainBtn = Get-UIControl -Name 'PauseDrainBtn'
        $matchedDevicesList = Get-UIControl -Name 'MatchedDevicesList'
        $durationBox = Get-UIControl -Name 'DurationBox'
        $disablePatching = Get-UIControl -Name 'DisablePatching'
        $disableAV = Get-UIControl -Name 'DisableAV'
        $disableMonitoring = Get-UIControl -Name 'DisableMonitoring'
        $disableAutomation = Get-UIControl -Name 'DisableAutomation'
        $runHealthBtn = Get-UIControl -Name 'RunHealthBtn'
        $runUpdatesBtn = Get-UIControl -Name 'RunUpdatesBtn'
        $runCustomBtn = Get-UIControl -Name 'RunCustomBtn'
        $actionLogBox = Get-UIControl -Name 'ActionLogBox'
        $clusterTabLog = Get-UIControl -Name 'ClusterTabLog'
        $actionProgress = Get-UIControl -Name 'ActionProgress'
        
        # Apply maintenance defaults from config if present
        $config = $script:ClusterState.Config
        if ($config -and $config.MaintenanceDefaults) {
            if ($config.MaintenanceDefaults.PSObject.Properties.Name -contains 'DurationHours') {
                $durationBox.Text = [string]$config.MaintenanceDefaults.DurationHours
            }
            if ($config.MaintenanceDefaults.PSObject.Properties.Name -contains 'DisablePatching') {
                $disablePatching.IsChecked = [bool]$config.MaintenanceDefaults.DisablePatching
            }
            if ($config.MaintenanceDefaults.PSObject.Properties.Name -contains 'DisableAV') {
                $disableAV.IsChecked = [bool]$config.MaintenanceDefaults.DisableAV
            }
            if ($config.MaintenanceDefaults.PSObject.Properties.Name -contains 'DisableMonitoring') {
                $disableMonitoring.IsChecked = [bool]$config.MaintenanceDefaults.DisableMonitoring
            }
            if ($config.MaintenanceDefaults.PSObject.Properties.Name -contains 'DisableAutomation') {
                $disableAutomation.IsChecked = [bool]$config.MaintenanceDefaults.DisableAutomation
            }
        }
        
        # Event handlers
        $connectBtn.Add_Click({ Connect-ToCluster })
        $refreshBtn.Add_Click({ Refresh-ClusterNodes })
        $openFullBtn.Add_Click({ Open-FullClusterUI })
        $matchBtn.Add_Click({ Match-ClusterNodes })
        $maintStartBtn.Add_Click({ Start-MaintenanceMode })
        $maintEndBtn.Add_Click({ End-MaintenanceMode })
        $pauseDrainBtn.Add_Click({ Invoke-PauseDrain })
        $runHealthBtn.Add_Click({ Invoke-HealthCheck })
        $runUpdatesBtn.Add_Click({ Invoke-WindowsUpdates })
        $runCustomBtn.Add_Click({ Invoke-CustomScript })
        
        $script:ClusterState.UIInitialized = $true
        Write-SafeLog "Cluster Manager UI initialized successfully" 'INFO'
        
    } catch {
        Write-SafeLog "Failed to initialize Cluster Manager UI: $($_.Exception.Message)" 'ERROR'
    }
}

function Connect-ToCluster {
    $clusterNameBox = Get-UIControl -Name 'ClusterNameBox'
    $clusterTabLog = Get-UIControl -Name 'ClusterTabLog'
    
    $clusterName = $clusterNameBox.Text.Trim()
    if (-not $clusterName) {
        Write-SafeLog "Please enter a cluster name" 'WARN'
        return
    }
    
    try {
        Write-SafeLog "Connecting to cluster: $clusterName" 'INFO'
        $script:ClusterState.ClusterName = $clusterName
        
        # Test cluster connectivity
        $nodes = Get-ClusterNode -Cluster $clusterName -ErrorAction Stop
        $script:ClusterState.ClusterNodes = $nodes
        
        Update-ClusterNodesDisplay
        Write-SafeLog "Connected to cluster '$clusterName' with $($nodes.Count) nodes" 'INFO'
    } catch {
        Write-SafeLog "Failed to connect to cluster '$clusterName': $($_.Exception.Message)" 'ERROR'
        $script:ClusterState.ClusterName = $null
        $script:ClusterState.ClusterNodes = @()
    }
}

function Refresh-ClusterNodes {
    if (-not $script:ClusterState.ClusterName) {
        Write-SafeLog "No cluster connected" 'WARN'
        return
    }
    
    try {
        Write-SafeLog "Refreshing cluster nodes..." 'INFO'
        $nodes = Get-ClusterNode -Cluster $script:ClusterState.ClusterName -ErrorAction Stop
        $script:ClusterState.ClusterNodes = $nodes
        Update-ClusterNodesDisplay
        Write-SafeLog "Refreshed cluster nodes: $($nodes.Count) nodes found" 'INFO'
    } catch {
        Write-SafeLog "Failed to refresh cluster nodes: $($_.Exception.Message)" 'ERROR'
    }
}

function Update-ClusterNodesDisplay {
    $clusterNodesList = Get-UIControl -Name 'ClusterNodesList'
    $clusterNodesList.Items.Clear()
    
    foreach ($node in $script:ClusterState.ClusterNodes) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = "$($node.Name) ($($node.State))"
        $item.Tag = $node
        $clusterNodesList.Items.Add($item)
    }
}

function Match-ClusterNodes {
    $clusterNodesList = Get-UIControl -Name 'ClusterNodesList'
    $matchedDevicesList = Get-UIControl -Name 'MatchedDevicesList'
    
    if ($clusterNodesList.SelectedItems.Count -eq 0) {
        Write-SafeLog "Please select cluster nodes to match" 'WARN'
        return
    }
    
    try {
        Write-SafeLog "Matching selected cluster nodes with NinjaOne devices..." 'INFO'
        $matchedDevicesList.Items.Clear()
        $script:ClusterState.Matched.Clear()
        
        # Get all devices from NinjaOne
        $config = Get-NinjaSuiteConfig
        $tokenResult = Get-NinjaOneAccessToken -Instance $config.NinjaOne.Instance -ClientId $config.NinjaOne.ClientId -ClientSecret $config.NinjaOne.ClientSecret
        if (-not $tokenResult.Success -or -not $tokenResult.Data) {
            throw "Token acquisition failed: $($tokenResult.ErrorMessage)"
        }
        $tokenInfo = $tokenResult.Data
        $devices = Get-NinjaOneDevicesAPI -TokenInfo $tokenInfo -All
        
        foreach ($selectedItem in $clusterNodesList.SelectedItems) {
            $clusterNode = $selectedItem.Tag
            $nodeName = $clusterNode.Name
            
            # Try to match by hostname
            $matchedDevice = $devices | Where-Object { 
                $_.systemName -eq $nodeName -or 
                $_.systemName -eq "$nodeName.$($env:USERDNSDOMAIN)" -or
                $_.dnsName -eq $nodeName
            } | Select-Object -First 1
            
            if ($matchedDevice) {
                $script:ClusterState.Matched[$nodeName] = $matchedDevice
                $item = New-Object System.Windows.Controls.ListBoxItem
                $item.Content = "$nodeName → $($matchedDevice.systemName) (ID: $($matchedDevice.id))"
                $item.Tag = @{ ClusterNode = $clusterNode; Device = $matchedDevice }
                $matchedDevicesList.Items.Add($item)
                Write-SafeLog "Matched $nodeName to device ID $($matchedDevice.id)" 'INFO'
            } else {
                Write-SafeLog "No matching device found for cluster node: $nodeName" 'WARN'
            }
        }
        
        Write-SafeLog "Device matching completed: $($script:ClusterState.Matched.Count) matches found" 'INFO'
    } catch {
        Write-SafeLog "Failed to match cluster nodes: $($_.Exception.Message)" 'ERROR'
    }
}

function Start-MaintenanceMode {
    $durationBox = Get-UIControl -Name 'DurationBox'
    $disablePatching = Get-UIControl -Name 'DisablePatching'
    $disableAV = Get-UIControl -Name 'DisableAV'
    $disableMonitoring = Get-UIControl -Name 'DisableMonitoring'
    $disableAutomation = Get-UIControl -Name 'DisableAutomation'
    
    if ($script:ClusterState.Matched.Count -eq 0) {
        Write-SafeLog "No matched devices to put in maintenance mode" 'WARN'
        return
    }
    
    try {
        $duration = [int]$durationBox.Text
        $endTime = (Get-Date).AddHours($duration)
        
        Write-SafeLog "Starting maintenance mode for $($script:ClusterState.Matched.Count) devices (Duration: $duration hours)" 'INFO'
        
        $config = Get-NinjaSuiteConfig
        $tokenResult = Get-NinjaOneAccessToken -Instance $config.NinjaOne.Instance -ClientId $config.NinjaOne.ClientId -ClientSecret $config.NinjaOne.ClientSecret
        if (-not $tokenResult.Success -or -not $tokenResult.Data) {
            throw "Token acquisition failed: $($tokenResult.ErrorMessage)"
        }
        $tokenInfo = $tokenResult.Data
        
        foreach ($deviceName in $script:ClusterState.Matched.Keys) {
            $device = $script:ClusterState.Matched[$deviceName]
            
            $maintenanceParams = @{
                TokenInfo = $tokenInfo
                DeviceId = $device.id
                StartTime = Get-Date
                EndTime = $endTime
                DisablePatching = $disablePatching.IsChecked
                DisableAV = $disableAV.IsChecked
                DisableMonitoring = $disableMonitoring.IsChecked
                DisableAutomation = $disableAutomation.IsChecked
            }
            
            Set-NinjaOneDeviceMaintenanceMode @maintenanceParams
            Write-SafeLog "Started maintenance mode for device: $($device.systemName)" 'INFO'
        }
        
        Write-SafeLog "Maintenance mode started for all matched devices until $($endTime.ToString('yyyy-MM-dd HH:mm'))" 'INFO'
    } catch {
        Write-SafeLog "Failed to start maintenance mode: $($_.Exception.Message)" 'ERROR'
    }
}

function End-MaintenanceMode {
    if ($script:ClusterState.Matched.Count -eq 0) {
        Write-SafeLog "No matched devices to remove from maintenance mode" 'WARN'
        return
    }
    
    try {
        Write-SafeLog "Ending maintenance mode for $($script:ClusterState.Matched.Count) devices" 'INFO'
        
        $config = Get-NinjaSuiteConfig
        $tokenResult = Get-NinjaOneAccessToken -Instance $config.NinjaOne.Instance -ClientId $config.NinjaOne.ClientId -ClientSecret $config.NinjaOne.ClientSecret
        if (-not $tokenResult.Success -or -not $tokenResult.Data) {
            throw "Token acquisition failed: $($tokenResult.ErrorMessage)"
        }
        $tokenInfo = $tokenResult.Data
        
        foreach ($deviceName in $script:ClusterState.Matched.Keys) {
            $device = $script:ClusterState.Matched[$deviceName]
            Remove-NinjaOneDeviceMaintenanceMode -TokenInfo $tokenInfo -DeviceId $device.id
            Write-SafeLog "Ended maintenance mode for device: $($device.systemName)" 'INFO'
        }
        
        Write-SafeLog "Maintenance mode ended for all matched devices" 'INFO'
    } catch {
        Write-SafeLog "Failed to end maintenance mode: $($_.Exception.Message)" 'ERROR'
    }
}

function Invoke-PauseDrain {
    if (-not $script:ClusterState.ClusterName) {
        Write-SafeLog "No cluster connected" 'WARN'
        return
    }
    
    $clusterNodesList = Get-UIControl -Name 'ClusterNodesList'
    if ($clusterNodesList.SelectedItems.Count -eq 0) {
        Write-SafeLog "Please select cluster nodes to pause and drain" 'WARN'
        return
    }
    
    try {
        Write-SafeLog "Pausing and draining selected cluster nodes..." 'INFO'
        
        foreach ($selectedItem in $clusterNodesList.SelectedItems) {
            $clusterNode = $selectedItem.Tag
            $nodeName = $clusterNode.Name
            
            # Pause the node
            Suspend-ClusterNode -Name $nodeName -Cluster $script:ClusterState.ClusterName -Drain
            Write-SafeLog "Paused and drained cluster node: $nodeName" 'INFO'
        }
        
        # Refresh the display
        Refresh-ClusterNodes
    } catch {
        Write-SafeLog "Failed to pause/drain cluster nodes: $($_.Exception.Message)" 'ERROR'
    }
}

function Invoke-HealthCheck {
    Write-SafeLog "Health check functionality not yet implemented" 'INFO'
}

function Invoke-WindowsUpdates {
    Write-SafeLog "Windows updates functionality not yet implemented" 'INFO'
}

function Invoke-CustomScript {
    Write-SafeLog "Custom script functionality not yet implemented" 'INFO'
}

function Open-FullClusterUI {
    try {
        if (Get-Command "failclusters.msc" -ErrorAction SilentlyContinue) {
            Start-Process "failclusters.msc"
            Write-SafeLog "Opened Failover Cluster Manager" 'INFO'
        } else {
            Write-SafeLog "Failover Cluster Manager not available on this system" 'WARN'
        }
    } catch {
        Write-SafeLog "Failed to open Failover Cluster Manager: $($_.Exception.Message)" 'ERROR'
    }
}

function Write-SafeLog {
    param($Message, $Level = 'INFO')
    
    # Write to plugin log
    $clusterTabLog = Get-UIControl -Name 'ClusterTabLog' -ErrorAction SilentlyContinue
    if ($clusterTabLog) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $clusterTabLog.AppendText("[$timestamp] [$Level] $Message`r`n")
        $clusterTabLog.ScrollToEnd()
    }
    
    # Write to main log if available
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
Export-ModuleMember -Function Initialize-ClusterManagerPlugin, Initialize-ClusterManagerUI

# Module loaded (no UI calls during module loading)
# Use proper logging instead of Write-Host to respect log level settings
if (Get-Command "Write-Log" -ErrorAction SilentlyContinue) {
    Write-Log "Cluster Manager plugin module loaded" 'DEBUG'
}
