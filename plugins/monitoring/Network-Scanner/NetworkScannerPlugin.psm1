# NetworkScannerPlugin.psm1
# Advanced Network Discovery and Scanning Plugin for NinjaSuite
# Based on illsk1lls/IPScanner (https://github.com/illsk1lls/IPScanner)

#region Classes and Data Structures

class NetworkDevice {
    [string]$IPAddress
    [string]$Hostname
    [string]$MacAddress
    [string]$Vendor
    [string]$Status
    [int]$ResponseTime
    [string[]]$OpenPorts
    [datetime]$LastSeen
    [string]$DeviceType
    
    NetworkDevice([string]$ip) {
        $this.IPAddress = $ip
        $this.Hostname = ""
        $this.MacAddress = ""
        $this.Vendor = ""
        $this.Status = "Unknown"
        $this.ResponseTime = -1
        $this.OpenPorts = @()
        $this.LastSeen = Get-Date
        $this.DeviceType = "Unknown"
    }
}

class ScanResult {
    [NetworkDevice[]]$Devices
    [string]$Subnet
    [datetime]$ScanStartTime
    [datetime]$ScanEndTime
    [int]$TotalDevicesFound
    [int]$OnlineDevices
    [int]$OfflineDevices
    
    ScanResult([string]$subnet) {
        $this.Devices = @()
        $this.Subnet = $subnet
        $this.ScanStartTime = Get-Date
        $this.TotalDevicesFound = 0
        $this.OnlineDevices = 0
        $this.OfflineDevices = 0
    }
}

#endregion

#region Network Discovery Functions

function Start-NetworkScan {
    <#
    .SYNOPSIS
    Performs a comprehensive network scan of the specified subnet.
    
    .PARAMETER Subnet
    Network subnet to scan (e.g., "192.168.1.0/24")
    
    .PARAMETER Timeout
    Ping timeout in milliseconds (default: 1000)
    
    .PARAMETER MaxConcurrent
    Maximum concurrent operations (default: 50)
    
    .PARAMETER IncludePortScan
    Whether to perform port scanning on discovered devices
    
    .PARAMETER ProgressCallback
    Callback function for progress updates
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subnet,
        
        [int]$Timeout = 1000,
        [int]$MaxConcurrent = 50,
        [bool]$IncludePortScan = $true,
        [scriptblock]$ProgressCallback
    )
    
    try {
        $scanResult = [ScanResult]::new($Subnet)
        
        # Parse subnet
        $ipRange = Get-IPRange -Subnet $Subnet
        $totalIPs = $ipRange.Count
        
        if ($ProgressCallback) {
            & $ProgressCallback -Activity "Starting network scan" -Status "Preparing to scan $totalIPs addresses" -PercentComplete 0
        }
        
        # Perform ping sweep with throttling
        $jobs = @()
        $completed = 0
        
        foreach ($ip in $ipRange) {
            # Throttle concurrent jobs
            while ((Get-Job -State Running).Count -ge $MaxConcurrent) {
                Start-Sleep -Milliseconds 100
                
                # Collect completed jobs
                $completedJobs = Get-Job -State Completed
                foreach ($job in $completedJobs) {
                    $result = Receive-Job $job
                    Remove-Job $job
                    
                    if ($result -and $result.Status -eq "Online") {
                        $device = [NetworkDevice]::new($result.IPAddress)
                        $device.Status = $result.Status
                        $device.ResponseTime = $result.ResponseTime
                        $device.Hostname = $result.Hostname
                        $scanResult.Devices += $device
                        $scanResult.OnlineDevices++
                    } else {
                        $scanResult.OfflineDevices++
                    }
                    
                    $completed++
                    $percentComplete = [math]::Round(($completed / $totalIPs) * 50, 1)
                    
                    if ($ProgressCallback) {
                        & $ProgressCallback -Activity "Scanning network" -Status "Scanned $completed of $totalIPs addresses" -PercentComplete $percentComplete
                    }
                }
            }
            
            # Start new ping job
            $job = Start-Job -ScriptBlock {
                param($IPAddress, $Timeout)
                
                try {
                    $ping = New-Object System.Net.NetworkInformation.Ping
                    $reply = $ping.Send($IPAddress, $Timeout)
                    
                    if ($reply.Status -eq 'Success') {
                        # Get hostname
                        $hostname = ""
                        try {
                            $hostname = [System.Net.Dns]::GetHostEntry($IPAddress).HostName
                        } catch {
                            $hostname = $IPAddress
                        }
                        
                        return @{
                            IPAddress = $IPAddress
                            Status = "Online"
                            ResponseTime = $reply.RoundtripTime
                            Hostname = $hostname
                        }
                    }
                } catch {
                    # Silent fail for offline devices
                }
                
                return @{
                    IPAddress = $IPAddress
                    Status = "Offline"
                    ResponseTime = -1
                    Hostname = ""
                }
            } -ArgumentList $ip, $Timeout
            
            $jobs += $job
        }
        
        # Wait for remaining jobs
        if ($ProgressCallback) {
            & $ProgressCallback -Activity "Finalizing scan" -Status "Waiting for remaining ping operations" -PercentComplete 60
        }
        
        $jobs | Wait-Job | ForEach-Object {
            $result = Receive-Job $_
            Remove-Job $_
            
            if ($result -and $result.Status -eq "Online") {
                $device = [NetworkDevice]::new($result.IPAddress)
                $device.Status = $result.Status
                $device.ResponseTime = $result.ResponseTime
                $device.Hostname = $result.Hostname
                $scanResult.Devices += $device
                $scanResult.OnlineDevices++
            } else {
                $scanResult.OfflineDevices++
            }
            
            $completed++
        }
        
        # Enhance device information
        if ($scanResult.OnlineDevices -gt 0) {
            if ($ProgressCallback) {
                & $ProgressCallback -Activity "Gathering device information" -Status "Resolving MAC addresses and vendors" -PercentComplete 70
            }
            
            $arpTable = Get-ArpTable
            
            foreach ($device in $scanResult.Devices) {
                if ($device.Status -eq "Online") {
                    # Get MAC address from ARP table
                    $arpEntry = $arpTable | Where-Object { $_.IPAddress -eq $device.IPAddress }
                    if ($arpEntry) {
                        $device.MacAddress = $arpEntry.MacAddress
                        $device.Vendor = Get-VendorFromMac -MacAddress $device.MacAddress
                    }
                    
                    # Determine device type
                    $device.DeviceType = Get-DeviceType -Device $device
                    
                    # Port scanning if enabled
                    if ($IncludePortScan) {
                        $device.OpenPorts = Get-OpenPorts -IPAddress $device.IPAddress -CommonPortsOnly
                    }
                }
            }
        }
        
        $scanResult.ScanEndTime = Get-Date
        $scanResult.TotalDevicesFound = $scanResult.OnlineDevices
        
        if ($ProgressCallback) {
            & $ProgressCallback -Activity "Scan complete" -Status "Found $($scanResult.OnlineDevices) online devices" -PercentComplete 100
        }
        
        return $scanResult
        
    } catch {
        if (Get-Command 'Write-Log' -ErrorAction SilentlyContinue) {
            Write-SafeLog "Network scan failed: $($_.Exception.Message)" 'ERROR'
        }
        throw
    }
}

function Get-IPRange {
    <#
    .SYNOPSIS
    Generates IP address range from subnet notation.
    #>
    param([string]$Subnet)
    
    try {
        # Parse CIDR notation (e.g., "192.168.1.0/24")
        $parts = $Subnet -split '/'
        $baseIP = $parts[0]
        $prefixLength = [int]$parts[1]
        
        # Calculate subnet mask
        $mask = [math]::Pow(2, 32 - $prefixLength) - 1
        $networkMask = (-bnot $mask) -band 0xFFFFFFFF
        
        # Convert IP to integer
        $ipBytes = $baseIP -split '\.' | ForEach-Object { [int]$_ }
        $ipInt = ($ipBytes[0] -shl 24) + ($ipBytes[1] -shl 16) + ($ipBytes[2] -shl 8) + $ipBytes[3]
        
        # Calculate network and broadcast addresses
        $networkInt = $ipInt -band $networkMask
        $broadcastInt = $networkInt -bor $mask
        
        # Generate IP range
        $ipRange = @()
        for ($i = $networkInt + 1; $i -lt $broadcastInt; $i++) {
            $a = ($i -shr 24) -band 0xFF
            $b = ($i -shr 16) -band 0xFF
            $c = ($i -shr 8) -band 0xFF
            $d = $i -band 0xFF
            $ipRange += "$a.$b.$c.$d"
        }
        
        return $ipRange
        
    } catch {
        throw "Invalid subnet format: $Subnet"
    }
}

function Get-ArpTable {
    <#
    .SYNOPSIS
    Retrieves the ARP table for MAC address resolution.
    #>
    try {
        $arpEntries = @()
        
        # Use arp command to get MAC addresses
        $arpOutput = & arp -a 2>$null
        
        foreach ($line in $arpOutput) {
            if ($line -match '^\s*(\d+\.\d+\.\d+\.\d+)\s+([0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2}-[0-9a-f]{2})\s+(\w+)') {
                $arpEntries += @{
                    IPAddress = $matches[1]
                    MacAddress = $matches[2].ToUpper()
                    Type = $matches[3]
                }
            }
        }
        
        return $arpEntries
        
    } catch {
        return @()
    }
}

function Get-VendorFromMac {
    <#
    .SYNOPSIS
    Attempts to identify device vendor from MAC address.
    #>
    param([string]$MacAddress)
    
    if (-not $MacAddress) { return "Unknown" }
    
    # Get OUI (first 6 characters)
    $oui = ($MacAddress -replace '[:-]', '').Substring(0, 6).ToUpper()
    
    # Common vendor mappings (simplified)
    $vendors = @{
        '001B63' = 'Apple'
        '00D0C9' = 'Intel'
        '00E04C' = 'Realtek'
        '000C29' = 'VMware'
        '080027' = 'VirtualBox'
        'B827EB' = 'Raspberry Pi'
        '2C5A0F' = 'Samsung'
        '78A50E' = 'Dell'
        '001E4C' = 'HP'
        '00248C' = 'Lenovo'
    }
    
    if ($vendors.ContainsKey($oui)) {
        return $vendors[$oui]
    }
    
    return "Unknown"
}

function Get-DeviceType {
    <#
    .SYNOPSIS
    Attempts to determine device type based on available information.
    #>
    param([NetworkDevice]$Device)
    
    # Basic device type detection
    if ($Device.Hostname -match '(router|gateway|modem)') { return "Router/Gateway" }
    if ($Device.Hostname -match '(switch|hub)') { return "Switch" }
    if ($Device.Hostname -match '(printer|hp|canon|epson)') { return "Printer" }
    if ($Device.Hostname -match '(camera|cam|nvr)') { return "Security Camera" }
    if ($Device.Vendor -match '(Apple|iPhone|iPad)') { return "Apple Device" }
    if ($Device.Vendor -match '(Samsung|Android)') { return "Android Device" }
    if ($Device.Vendor -match '(VMware|VirtualBox)') { return "Virtual Machine" }
    if ($Device.Vendor -match '(Raspberry)') { return "IoT Device" }
    
    # Check common ports for service identification
    if ($Device.OpenPorts -contains 80 -or $Device.OpenPorts -contains 443) { return "Web Server" }
    if ($Device.OpenPorts -contains 22) { return "Linux/Unix Server" }
    if ($Device.OpenPorts -contains 3389) { return "Windows Computer" }
    if ($Device.OpenPorts -contains 139 -or $Device.OpenPorts -contains 445) { return "Windows Computer" }
    
    return "Computer"
}

function Get-OpenPorts {
    <#
    .SYNOPSIS
    Scans for open ports on a target IP address.
    #>
    param(
        [string]$IPAddress,
        [switch]$CommonPortsOnly,
        [int[]]$PortList = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 993, 995, 1723, 3389, 5985, 5986, 8080)
    )
    
    $openPorts = @()
    
    foreach ($port in $PortList) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $result = $tcpClient.BeginConnect($IPAddress, $port, $null, $null)
            $success = $result.AsyncWaitHandle.WaitOne(1000)
            
            if ($success -and $tcpClient.Connected) {
                $openPorts += $port
            }
            
            $tcpClient.Close()
        } catch {
            # Port is closed or filtered
        }
    }
    
    return $openPorts
}

#endregion

#region Export Functions

function Export-ScanResults {
    <#
    .SYNOPSIS
    Exports scan results to various formats.
    #>
    param(
        [Parameter(Mandatory)]
        [ScanResult]$ScanResult,
        
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [ValidateSet('HTML', 'CSV', 'JSON', 'XML')]
        [string]$Format = 'HTML'
    )
    
    try {
        switch ($Format) {
            'HTML' {
                $html = Export-ToHtml -ScanResult $ScanResult
                $html | Out-File -FilePath $FilePath -Encoding UTF8
            }
            'CSV' {
                $ScanResult.Devices | Export-Csv -Path $FilePath -NoTypeInformation
            }
            'JSON' {
                $ScanResult | ConvertTo-Json -Depth 3 | Out-File -FilePath $FilePath -Encoding UTF8
            }
            'XML' {
                $ScanResult.Devices | Export-Clixml -Path $FilePath
            }
        }
        
        if (Get-Command 'Write-Log' -ErrorAction SilentlyContinue) {
            Write-SafeLog "Scan results exported to: $FilePath" 'INFO'
        }
        
    } catch {
        if (Get-Command 'Write-Log' -ErrorAction SilentlyContinue) {
            Write-SafeLog "Failed to export scan results: $($_.Exception.Message)" 'ERROR'
        }
        throw
    }
}

function Export-ToHtml {
    param([ScanResult]$ScanResult)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Scan Results - $($ScanResult.Subnet)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .stats { display: flex; gap: 20px; margin-bottom: 20px; }
        .stat-card { background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 8px; overflow: hidden; }
        th { background: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f8f9fa; }
        .online { color: #27ae60; font-weight: bold; }
        .offline { color: #e74c3c; font-weight: bold; }
        .port-list { font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Network Scan Results</h1>
        <p>Subnet: $($ScanResult.Subnet) | Scan Date: $($ScanResult.ScanStartTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>
    </div>
    
    <div class="stats">
        <div class="stat-card">
            <h3>Total Devices</h3>
            <p style="font-size: 24px; margin: 0;">$($ScanResult.TotalDevicesFound)</p>
        </div>
        <div class="stat-card">
            <h3>Online</h3>
            <p style="font-size: 24px; margin: 0; color: #27ae60;">$($ScanResult.OnlineDevices)</p>
        </div>
        <div class="stat-card">
            <h3>Scan Duration</h3>
            <p style="font-size: 24px; margin: 0;">$([math]::Round(($ScanResult.ScanEndTime - $ScanResult.ScanStartTime).TotalSeconds, 1))s</p>
        </div>
    </div>
    
    <table>
        <thead>
            <tr>
                <th>IP Address</th>
                <th>Hostname</th>
                <th>MAC Address</th>
                <th>Vendor</th>
                <th>Device Type</th>
                <th>Status</th>
                <th>Response Time</th>
                <th>Open Ports</th>
            </tr>
        </thead>
        <tbody>
"@
    
    foreach ($device in ($ScanResult.Devices | Sort-Object { [System.Version]$_.IPAddress })) {
        $statusClass = if ($device.Status -eq "Online") { "online" } else { "offline" }
        $ports = if ($device.OpenPorts.Count -gt 0) { $device.OpenPorts -join ', ' } else { 'None detected' }
        
        $html += @"
            <tr>
                <td>$($device.IPAddress)</td>
                <td>$($device.Hostname)</td>
                <td>$($device.MacAddress)</td>
                <td>$($device.Vendor)</td>
                <td>$($device.DeviceType)</td>
                <td class="$statusClass">$($device.Status)</td>
                <td>$($device.ResponseTime)ms</td>
                <td class="port-list">$ports</td>
            </tr>
"@
    }
    
    $html += @"
        </tbody>
    </table>
    
    <div style="margin-top: 20px; text-align: center; color: #666; font-size: 0.9em;">
        Generated by NinjaSuite Network Scanner Plugin
    </div>
</body>
</html>
"@
    
}

#endregion

#region Utility Functions

function Get-IPRange {
    <#
    .SYNOPSIS
    Gets IP range from CIDR notation.
    #>
    param([string]$Subnet)
    
    try {
        if ($Subnet -match '^(\d+\.\d+\.\d+\.\d+)/(\d+)$') {
            $networkIP = $matches[1]
            $prefixLength = [int]$matches[2]
            
            $ip = [System.Net.IPAddress]::Parse($networkIP)
            $ipBytes = $ip.GetAddressBytes()
            
            # Calculate subnet mask
            $maskBits = ('1' * $prefixLength).PadRight(32, '0')
            $mask = [Convert]::ToUInt32($maskBits, 2)
            $maskBytes = [BitConverter]::GetBytes($mask)
            [Array]::Reverse($maskBytes)
            
            # Calculate network address
            $networkBytes = @()
            for ($i = 0; $i -lt 4; $i++) {
                $networkBytes += $ipBytes[$i] -band $maskBytes[$i]
            }
            
            # Calculate broadcast address
            $broadcastBytes = @()
            for ($i = 0; $i -lt 4; $i++) {
                $broadcastBytes += $networkBytes[$i] -bor (255 - $maskBytes[$i])
            }
            
            # Generate IP range
            $startIP = [System.Net.IPAddress]::new($networkBytes)
            $endIP = [System.Net.IPAddress]::new($broadcastBytes)
            
            $ipRange = @()
            $current = $startIP.GetAddressBytes()
            $end = $endIP.GetAddressBytes()
            
            do {
                $ipRange += ([System.Net.IPAddress]::new($current)).ToString()
                
                # Increment IP
                $carry = 1
                for ($i = 3; $i -ge 0; $i--) {
                    $current[$i] += $carry
                    if ($current[$i] -le 255) {
                        $carry = 0
                        break
                    } else {
                        $current[$i] = 0
                    }
                }
            } while ($carry -eq 0 -and (Compare-IPBytes $current $end) -le 0)
            
            return $ipRange
        } else {
            throw "Invalid subnet format. Use CIDR notation (e.g., 192.168.1.0/24)"
        }
    } catch {
        throw "Failed to parse subnet: $($_.Exception.Message)"
    }
}

function Compare-IPBytes {
    param($ip1, $ip2)
    for ($i = 0; $i -lt 4; $i++) {
        if ($ip1[$i] -lt $ip2[$i]) { return -1 }
        if ($ip1[$i] -gt $ip2[$i]) { return 1 }
    }
    return 0
}

function Get-ArpTable {
    <#
    .SYNOPSIS
    Gets the ARP table.
    #>
    try {
        $arpOutput = arp -a
        $arpEntries = @()
        
        foreach ($line in $arpOutput) {
            if ($line -match '^\s*(\d+\.\d+\.\d+\.\d+)\s+([0-9a-f-]{17})\s+(\w+)') {
                $arpEntries += @{
                    IPAddress = $matches[1]
                    MacAddress = $matches[2]
                    Type = $matches[3]
                }
            }
        }
        
        return $arpEntries
    } catch {
        return @()
    }
}

function Get-VendorFromMac {
    <#
    .SYNOPSIS
    Gets vendor from MAC address.
    #>
    param([string]$MacAddress)
    
    # Simplified vendor lookup - in a real implementation, you'd use an OUI database
    if ([string]::IsNullOrEmpty($MacAddress)) { return "Unknown" }
    
    $oui = $MacAddress.Substring(0, 8).Replace('-', ':').ToUpper()
    
    $vendors = @{
        '00:50:56' = 'VMware'
        '08:00:27' = 'VirtualBox'
        '52:54:00' = 'QEMU'
        '00:15:5D' = 'Hyper-V'
        '00:1B:21' = 'Intel'
        '00:22:48' = 'Intel'
        '00:26:B9' = 'Intel'
        'DC:A6:32' = 'Raspberry Pi'
        'B8:27:EB' = 'Raspberry Pi'
    }
    
    if ($vendors.ContainsKey($oui)) {
        return $vendors[$oui]
    }
    
    return "Unknown"
}

function Get-DeviceType {
    <#
    .SYNOPSIS
    Determines device type based on various factors.
    #>
    param($Device)
    
    # Simple device type detection based on hostname and MAC
    $hostname = $Device.Hostname.ToLower()
    $vendor = $Device.Vendor.ToLower()
    
    if ($vendor -like "*vmware*" -or $vendor -like "*virtualbox*" -or $vendor -like "*qemu*" -or $vendor -like "*hyper-v*") {
        return "Virtual Machine"
    }
    
    if ($hostname -like "*server*" -or $hostname -like "*srv*") {
        return "Server"
    }
    
    if ($hostname -like "*pc*" -or $hostname -like "*desktop*" -or $hostname -like "*workstation*") {
        return "Workstation"
    }
    
    if ($vendor -like "*raspberry*") {
        return "IoT Device"
    }
    
    return "Unknown"
}

function Get-OpenPorts {
    <#
    .SYNOPSIS
    Gets open ports for an IP address.
    #>
    param([string]$IPAddress, [switch]$CommonPortsOnly)
    
    $commonPorts = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 993, 995, 3389, 5985, 5986)
    $openPorts = @()
    
    foreach ($port in $commonPorts) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcpClient.BeginConnect($IPAddress, $port, $null, $null)
            $wait = $asyncResult.AsyncWaitHandle.WaitOne(1000, $false)
            
            if ($wait -and $tcpClient.Connected) {
                $openPorts += $port
            }
            
            $tcpClient.Close()
        } catch {
            # Port is closed or filtered
        }
    }
    
    return $openPorts
}

#endregion

#region Plugin Initialization and UI Handlers

function Initialize-NetworkScannerPlugin {
    <#
    .SYNOPSIS
    Initializes the Network Scanner plugin and sets up UI event handlers.
    #>
    param([System.Windows.Controls.TabItem]$TabItem = $null)
    
    try {
        Write-SafeLog "Network Scanner plugin initialized" 'INFO'
        
        # Store reference to plugin tab item
        if ($TabItem) {
            $script:PluginTabItem = $TabItem
        }
        
        # Get UI controls
        $settingsButton = Get-UIControl -Name 'SettingsButton'
        $exportButton = Get-UIControl -Name 'ExportButton'
        $refreshButton = Get-UIControl -Name 'RefreshButton'
        $startScanButton = Get-UIControl -Name 'StartScanButton'
        $subnetTextBox = Get-UIControl -Name 'SubnetTextBox'
        $portScanCheckBox = Get-UIControl -Name 'PortScanCheckBox'
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $deviceCountText = Get-UIControl -Name 'DeviceCountText'
        $statusText = Get-UIControl -Name 'StatusText'
        $scanProgressBar = Get-UIControl -Name 'ScanProgressBar'
        $lastScanText = Get-UIControl -Name 'LastScanText'
        $pingDeviceButton = Get-UIControl -Name 'PingDeviceButton'
        $portScanDeviceButton = Get-UIControl -Name 'PortScanDeviceButton'
        $openRDPButton = Get-UIControl -Name 'OpenRDPButton'
        $deviceInfoPanel = Get-UIControl -Name 'DeviceInfoPanel'
        $noSelectionText = Get-UIControl -Name 'NoSelectionText'
        $selectedIPText = Get-UIControl -Name 'SelectedIPText'
        $selectedHostnameText = Get-UIControl -Name 'SelectedHostnameText'
        $selectedMacText = Get-UIControl -Name 'SelectedMacText'
        $selectedVendorText = Get-UIControl -Name 'SelectedVendorText'
        $selectedTypeText = Get-UIControl -Name 'SelectedTypeText'
        $selectedStatusText = Get-UIControl -Name 'SelectedStatusText'
        $openPortsList = Get-UIControl -Name 'OpenPortsList'
        
        # Global scan result storage
        $script:LastScanResult = $null
        
        # Start Scan button event
        if ($startScanButton) {
            $startScanButton.Add_Click({
                Start-NetworkScanUI
            })
        }
        
        # Export button event
        if ($exportButton) {
            $exportButton.Add_Click({
                Export-ScanResultsUI
            })
        }
        
        # Refresh button event
        if ($refreshButton) {
            $refreshButton.Add_Click({
                if ($script:LastScanResult) {
                    $subnetTextBox.Text = $script:LastScanResult.Subnet
                    Start-NetworkScanUI
                } else {
                    Start-NetworkScanUI
                }
            })
        }
        
        # Settings button event
        if ($settingsButton) {
            $settingsButton.Add_Click({
                Show-NetworkScannerSettings
            })
        }
        
        # Device list selection changed
        if ($deviceListView) {
            $deviceListView.Add_SelectionChanged({
                Update-DeviceDetails
            })
        }
        
        # Ping Device button
        if ($pingDeviceButton) {
            $pingDeviceButton.Add_Click({
                Ping-SelectedDevice
            })
        }
        
        # Port Scan Device button
        if ($portScanDeviceButton) {
            $portScanDeviceButton.Add_Click({
                PortScan-SelectedDevice
            })
        }
        
        # Remote Desktop button
        if ($openRDPButton) {
            $openRDPButton.Add_Click({
                Open-RemoteDesktop
            })
        }
        
        # Initialize UI state
        if ($deviceInfoPanel) { $deviceInfoPanel.Visibility = 'Collapsed' }
        if ($noSelectionText) { $noSelectionText.Visibility = 'Visible' }
        if ($scanProgressBar) { $scanProgressBar.Visibility = 'Collapsed' }
        if ($statusText) { $statusText.Text = "Ready to scan" }
        if ($deviceCountText) { $deviceCountText.Text = "0 devices" }
        
        return $true
        
    } catch {
        Write-SafeLog "Failed to initialize Network Scanner plugin: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Start-NetworkScanUI {
    <#
    .SYNOPSIS
    Starts a network scan from the UI.
    #>
    
    try {
        $subnetTextBox = Get-UIControl -Name 'SubnetTextBox'
        $portScanCheckBox = Get-UIControl -Name 'PortScanCheckBox'
        $statusText = Get-UIControl -Name 'StatusText'
        $scanProgressBar = Get-UIControl -Name 'ScanProgressBar'
        $startScanButton = Get-UIControl -Name 'StartScanButton'
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $lastScanText = Get-UIControl -Name 'LastScanText'
        
        $subnet = $subnetTextBox.Text
        $includePortScan = $portScanCheckBox.IsChecked
        
        if ([string]::IsNullOrEmpty($subnet)) {
            $statusText.Text = "Please enter a subnet to scan"
            return
        }
        
        # Update UI for scanning
        $startScanButton.IsEnabled = $false
        $scanProgressBar.Visibility = 'Visible'
        $scanProgressBar.Value = 0
        $statusText.Text = "Starting scan..."
        $deviceListView.Items.Clear()
        
        # Progress callback
        $progressCallback = {
            param($Activity, $Status, $PercentComplete)
            
            $scanProgressBar.Value = $PercentComplete
            $statusText.Text = $Status
        }
        
        # Run scan in background
        $scanJob = Start-Job -ScriptBlock {
            param($Subnet, $IncludePortScan, $ModulePath)
            
            # Import the module in the job
            Import-Module $ModulePath -Force
            
            # Perform the scan
            Start-NetworkScan -Subnet $Subnet -IncludePortScan $IncludePortScan
            
        } -ArgumentList $subnet, $includePortScan, $PSCommandPath
        
        # Monitor the job
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Add_Tick({
            if ($scanJob.State -eq 'Completed') {
                $timer.Stop()
                $result = Receive-Job $scanJob
                Remove-Job $scanJob
                
                # Update UI with results
                Complete-NetworkScanUI -ScanResult $result
            } elseif ($scanJob.State -eq 'Failed') {
                $timer.Stop()
                $error = Receive-Job $scanJob -ErrorAction SilentlyContinue
                Remove-Job $scanJob
                
                $statusText.Text = "Scan failed: $($error.Exception.Message)"
                $scanProgressBar.Visibility = 'Collapsed'
                $startScanButton.IsEnabled = $true
            }
        })
        $timer.Start()
        
    } catch {
        Write-SafeLog "Failed to start network scan: $($_.Exception.Message)" 'ERROR'
        $statusText.Text = "Scan failed: $($_.Exception.Message)"
        $scanProgressBar.Visibility = 'Collapsed'
        $startScanButton.IsEnabled = $true
    }
}

function Complete-NetworkScanUI {
    <#
    .SYNOPSIS
    Completes the network scan and updates the UI with results.
    #>
    param([object]$ScanResult)
    
    try {
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $deviceCountText = Get-UIControl -Name 'DeviceCountText'
        $statusText = Get-UIControl -Name 'StatusText'
        $scanProgressBar = Get-UIControl -Name 'ScanProgressBar'
        $startScanButton = Get-UIControl -Name 'StartScanButton'
        $lastScanText = Get-UIControl -Name 'LastScanText'
        
        # Store result globally
        $script:LastScanResult = $ScanResult
        
        # Update device list
        $deviceListView.Items.Clear()
        foreach ($device in $ScanResult.Devices) {
            $deviceListView.Items.Add($device)
        }
        
        # Update UI
        $deviceCountText.Text = "$($ScanResult.TotalDevicesFound) devices"
        $statusText.Text = "Scan completed - Found $($ScanResult.OnlineDevices) online devices"
        $lastScanText.Text = (Get-Date).ToString("HH:mm:ss")
        $scanProgressBar.Visibility = 'Collapsed'
        $startScanButton.IsEnabled = $true
        
    } catch {
        Write-SafeLog "Failed to complete network scan UI update: $($_.Exception.Message)" 'ERROR'
    }
}

function Update-DeviceDetails {
    <#
    .SYNOPSIS
    Updates the device details panel when a device is selected.
    #>
    
    try {
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $deviceInfoPanel = Get-UIControl -Name 'DeviceInfoPanel'
        $noSelectionText = Get-UIControl -Name 'NoSelectionText'
        $selectedIPText = Get-UIControl -Name 'SelectedIPText'
        $selectedHostnameText = Get-UIControl -Name 'SelectedHostnameText'
        $selectedMacText = Get-UIControl -Name 'SelectedMacText'
        $selectedVendorText = Get-UIControl -Name 'SelectedVendorText'
        $selectedTypeText = Get-UIControl -Name 'SelectedTypeText'
        $selectedStatusText = Get-UIControl -Name 'SelectedStatusText'
        $openPortsList = Get-UIControl -Name 'OpenPortsList'
        
        $selectedDevice = $deviceListView.SelectedItem
        
        if ($selectedDevice) {
            # Show device details
            $deviceInfoPanel.Visibility = 'Visible'
            $noSelectionText.Visibility = 'Collapsed'
            
            $selectedIPText.Text = $selectedDevice.IPAddress
            $selectedHostnameText.Text = "Hostname: $($selectedDevice.Hostname)"
            $selectedMacText.Text = "MAC: $($selectedDevice.MacAddress)"
            $selectedVendorText.Text = "Vendor: $($selectedDevice.Vendor)"
            $selectedTypeText.Text = "Type: $($selectedDevice.DeviceType)"
            $selectedStatusText.Text = $selectedDevice.Status
            
            # Set status color
            if ($selectedDevice.Status -eq "Online") {
                $selectedStatusText.Foreground = [System.Windows.Media.Brushes]::Green
            } else {
                $selectedStatusText.Foreground = [System.Windows.Media.Brushes]::Red
            }
            
            # Update ports list
            $openPortsList.Items.Clear()
            if ($selectedDevice.OpenPorts -and $selectedDevice.OpenPorts.Count -gt 0) {
                foreach ($port in $selectedDevice.OpenPorts) {
                    $openPortsList.Items.Add($port)
                }
            }
        } else {
            # Hide device details
            $deviceInfoPanel.Visibility = 'Collapsed'
            $noSelectionText.Visibility = 'Visible'
        }
        
    } catch {
        Write-SafeLog "Failed to update device details: $($_.Exception.Message)" 'ERROR'
    }
}

function Export-ScanResultsUI {
    <#
    .SYNOPSIS
    Exports scan results with UI dialog.
    #>
    
    try {
        if (-not $script:LastScanResult) {
            $statusText = Get-UIControl -Name 'StatusText'
            $statusText.Text = "No scan results to export"
            return
        }
        
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter = "HTML files (*.html)|*.html|CSV files (*.csv)|*.csv|JSON files (*.json)|*.json|XML files (*.xml)|*.xml"
        $dialog.DefaultExt = "html"
        $dialog.FileName = "NetworkScan-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        
        if ($dialog.ShowDialog() -eq $true) {
            $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLower()
            $format = switch ($extension) {
                '.html' { 'HTML' }
                '.csv' { 'CSV' }
                '.json' { 'JSON' }
                '.xml' { 'XML' }
                default { 'HTML' }
            }
            
            Export-ScanResults -ScanResult $script:LastScanResult -FilePath $dialog.FileName -Format $format
            
            $statusText = Get-UIControl -Name 'StatusText'
            $statusText.Text = "Results exported to $($dialog.FileName)"
            
            # Ask to open file
            $result = [System.Windows.MessageBox]::Show("Export completed. Would you like to open the file?", "Export Complete", 'YesNo', 'Question')
            if ($result -eq 'Yes') {
                Start-Process $dialog.FileName
            }
        }
        
    } catch {
        Write-SafeLog "Failed to export scan results: $($_.Exception.Message)" 'ERROR'
        $statusText = Get-UIControl -Name 'StatusText'
        $statusText.Text = "Export failed: $($_.Exception.Message)"
    }
}

function Show-NetworkScannerSettings {
    <#
    .SYNOPSIS
    Shows the Network Scanner settings dialog.
    #>
    
    try {
        [System.Windows.MessageBox]::Show("Network Scanner Settings coming soon!", "Settings", 'OK', 'Information')
    } catch {
        Write-SafeLog "Failed to show settings: $($_.Exception.Message)" 'ERROR'
    }
}

function Ping-SelectedDevice {
    <#
    .SYNOPSIS
    Pings the selected device.
    #>
    
    try {
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $selectedDevice = $deviceListView.SelectedItem
        
        if ($selectedDevice) {
            $statusText = Get-UIControl -Name 'StatusText'
            $statusText.Text = "Pinging $($selectedDevice.IPAddress)..."
            
            # Ping the device
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($selectedDevice.IPAddress, 5000)
            
            if ($reply.Status -eq 'Success') {
                $statusText.Text = "Ping successful: $($selectedDevice.IPAddress) responded in $($reply.RoundtripTime)ms"
            } else {
                $statusText.Text = "Ping failed: $($selectedDevice.IPAddress) - $($reply.Status)"
            }
        }
        
    } catch {
        Write-SafeLog "Failed to ping device: $($_.Exception.Message)" 'ERROR'
        $statusText = Get-UIControl -Name 'StatusText'
        $statusText.Text = "Ping failed: $($_.Exception.Message)"
    }
}

function PortScan-SelectedDevice {
    <#
    .SYNOPSIS
    Performs port scan on selected device.
    #>
    
    try {
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $selectedDevice = $deviceListView.SelectedItem
        
        if ($selectedDevice) {
            [System.Windows.MessageBox]::Show("Port scan feature coming soon!", "Port Scan", 'OK', 'Information')
        }
        
    } catch {
        Write-SafeLog "Failed to port scan device: $($_.Exception.Message)" 'ERROR'
    }
}

function Open-RemoteDesktop {
    <#
    .SYNOPSIS
    Opens Remote Desktop to selected device.
    #>
    
    try {
        $deviceListView = Get-UIControl -Name 'DeviceListView'
        $selectedDevice = $deviceListView.SelectedItem
        
        if ($selectedDevice) {
            Start-Process "mstsc" -ArgumentList "/v:$($selectedDevice.IPAddress)"
        }
        
    } catch {
        Write-SafeLog "Failed to open remote desktop: $($_.Exception.Message)" 'ERROR'
    }
}

# Helper function for safe logging
function Write-SafeLog {
    param($Message, $Level = 'INFO')
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level
    }
}

# Helper function to get UI controls
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
        
        # Fallback: try to find the Network Scanner tab
        $windows = [System.Windows.Application]::Current.Windows
        foreach ($window in $windows) {
            if ($window.Content) {
                # Try to find MainTabs control
                $mainTabs = $window.Content.FindName('MainTabs')
                if ($mainTabs) {
                    foreach ($tabItem in $mainTabs.Items) {
                        if ($tabItem.Tag -eq "Network Scanner" -or $tabItem.Header -eq "Network Scanner") {
                            $control = $tabItem.Content.FindName($Name)
                            if ($control) {
                                return $control
                            }
                        }
                    }
                }
            }
        }
        
        return $null
    } catch {
        return $null
    }
}

#endregion

# Export the main functions
Export-ModuleMember -Function Initialize-NetworkScannerPlugin, Start-NetworkScan, Export-ScanResults
