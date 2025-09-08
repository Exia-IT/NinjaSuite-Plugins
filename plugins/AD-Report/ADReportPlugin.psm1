# ADReportPlugin.psm1 - Active Directory Report Plugin for NinjaSuite
# 
# This plugin generates comprehensive Active Directory reports with graphed analytics
# covering users, groups, computers, organizational units, and group policies.
# Based on the original PSHTML-AD.ps1 script by Bradley Wyatt

#region Plugin Lifecycle Functions

function Initialize-ADReportPlugin {

# Fallback functions for standardized error handling
if (-not (Get-Command Write-NinjaLog -ErrorAction SilentlyContinue)) {
    function Write-NinjaLog {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $output = "[$timestamp] [$Level] $Message"
        
        switch ($Level) {
            'ERROR' { Write-Error $output }
            'WARN' { Write-Warning $output }
            'DEBUG' { if ($VerbosePreference -ne 'SilentlyContinue') { Write-Verbose $output } }
            default { Write-Host $output }
        }
    }
}

if (-not (Get-Command New-NinjaResult -ErrorAction SilentlyContinue)) {
    function New-NinjaResult {
        param(
            [bool]$Success,
            [object]$Data = $null,
            [string]$ErrorMessage = $null,
            [string]$Context = $null
        )
        
        return [PSCustomObject]@{
            Success = $Success
            Data = $Data
            ErrorMessage = $ErrorMessage
            Context = $Context
            Timestamp = Get-Date
        }
    }
}

# Import memory optimization functions if available
if (-not (Get-Command -Name Invoke-MemoryCleanup -ErrorAction SilentlyContinue)) {
    $memoryOptPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Modules\NinjaSuite.MemoryOptimization.psm1'
    if (Test-Path $memoryOptPath) {
        try {
            Import-Module $memoryOptPath -Force -ErrorAction SilentlyContinue
        } catch {
            # Memory optimization not critical for plugins
        }
    }
}

# Plugin memory cleanup function
function Invoke-PluginMemoryCleanup {
    param([string]$Context = "Plugin operation")
    
    if (Get-Command -Name Invoke-MemoryCleanup -ErrorAction SilentlyContinue) {
        try {
            Invoke-MemoryCleanup -Context $Context
        } catch {
            # Memory cleanup failure shouldn't affect plugin operation
        }
    }
}

    <#
    .SYNOPSIS
    Initializes the AD Report plugin and validates dependencies.
    
    .DESCRIPTION
    This function is automatically called when the plugin loads. It validates
    Active Directory module availability and sets up initial state.
    #>
    
    try {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "AD Report plugin initialization started..." 'INFO'
        }
        
        # Check for required modules
        $requiredModules = @('ActiveDirectory', 'GroupPolicy')
        $missingModules = @()
        
        foreach ($module in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                $missingModules += $module
            }
        }
        
        if ($missingModules.Count -gt 0) {
            $errorMsg = "Missing required modules: $($missingModules -join ', '). Please install RSAT tools."
            if (Get-Command "Log" -ErrorAction SilentlyContinue) {
                Write-Log $errorMsg 'ERROR'
            }
            throw $errorMsg
        }
        
        # Check for ReportHTML module
        if (-not (Get-Module -ListAvailable -Name "ReportHTML")) {
            if (Get-Command "Log" -ErrorAction SilentlyContinue) {
                Write-Log "ReportHTML module not found, will attempt to install during report generation" 'WARNING'
            }
        }
        
        # Initialize plugin data
        $script:PluginData = @{
            LoadTime = Get-Date
            Version = "1.0.0"
            Status = "Ready"
            LastReport = $null
            ReportsGenerated = 0
        }
        
        # Load plugin configuration
        $script:PluginConfig = @{
            CompanyLogo = ""
            RightLogo = "https://www.psmpartners.com/wp-content/uploads/2017/10/porcaro-stolarek-mete.png"
            ReportTitle = "Active Directory Report"
            ReportSavePath = "C:\Automation\"
            Days = 30
            UserCreatedDays = 7
            DaysUntilPWExpireINT = 7
            ADModNumber = 3
            AutoOpenReport = $true
        }
        
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "AD Report plugin initialized successfully!" 'INFO'
        }
        
        return $true
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "AD Report plugin initialization failed: $($_.Exception.Message)" 'ERROR'
        }
        return $false
    }
}

#endregion

#region Core AD Report Functions

function Invoke-ADReportGeneration {
    <#
    .SYNOPSIS
    Generates a comprehensive Active Directory report.
    
    .DESCRIPTION
    Creates an HTML report with detailed analytics on AD objects including
    users, groups, computers, OUs, and GPOs with graphical charts.
    
    .PARAMETER CompanyLogo
    URL or UNC path to company logo for the report header
    
    .PARAMETER RightLogo
    URL or UNC path to right-side logo for the report header
    
    .PARAMETER ReportTitle
    Title to display on the generated report
    
    .PARAMETER ReportSavePath
    Directory where the report will be saved
    
    .PARAMETER Days
    Users that have not logged in X amount of days or more
    
    .PARAMETER UserCreatedDays
    Users that have been created within X amount of days
    
    .PARAMETER DaysUntilPWExpireINT
    Users password expires within X amount of days
    
    .PARAMETER ADModNumber
    AD Objects that have been modified within X amount of days
    
    .PARAMETER ShowReport
    Whether to automatically open the report after generation
    #>
    
    param(
        [string]$CompanyLogo = $script:PluginConfig.CompanyLogo,
        [string]$RightLogo = $script:PluginConfig.RightLogo,
        [string]$ReportTitle = $script:PluginConfig.ReportTitle,
        [string]$ReportSavePath = $script:PluginConfig.ReportSavePath,
        [int]$Days = $script:PluginConfig.Days,
        [int]$UserCreatedDays = $script:PluginConfig.UserCreatedDays,
        [int]$DaysUntilPWExpireINT = $script:PluginConfig.DaysUntilPWExpireINT,
        [int]$ADModNumber = $script:PluginConfig.ADModNumber,
        [bool]$ShowReport = $script:PluginConfig.AutoOpenReport
    )
    
    try {
        # Ensure ReportHTML module is available
        if (-not (Get-Module -ListAvailable -Name "ReportHTML")) {
            if (Get-Command "Log" -ErrorAction SilentlyContinue) {
                Write-Log "Installing ReportHTML module..." 'INFO'
            }
            Install-Module -Name ReportHTML -Force -ErrorAction Stop
        }
        Import-Module ReportHTML -ErrorAction Stop
        
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Starting AD Report generation..." 'INFO'
        }
        
        # Ensure save directory exists
        if (-not (Test-Path $ReportSavePath)) {
            New-Item -Path $ReportSavePath -ItemType Directory -Force | Out-Null
        }
        
        # Get all AD data
        $reportData = Get-ADReportData -Days $Days -UserCreatedDays $UserCreatedDays -DaysUntilPWExpireINT $DaysUntilPWExpireINT -ADModNumber $ADModNumber
        
        # Generate HTML report
        $finalReport = Build-ADHTMLReport -ReportData $reportData -CompanyLogo $CompanyLogo -RightLogo $RightLogo -ReportTitle $ReportTitle
        
        # Save report
        $day = (Get-Date).Day
        $month = (Get-Date).Month
        $year = (Get-Date).Year
        $reportName = "$day - $month - $year - AD Report"
        
        Save-HTMLReport -ReportContent $finalReport -ShowReport:$ShowReport -ReportName $reportName -ReportPath $ReportSavePath
        
        # Update plugin state
        $script:PluginData.LastReport = Get-Date
        $script:PluginData.ReportsGenerated++
        
        $reportPath = Join-Path $ReportSavePath "$reportName.html"
        
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "AD Report generated successfully: $reportPath" 'INFO'
        }
        
        return @{
            Success = $true
            ReportPath = $reportPath
            ReportName = $reportName
            GeneratedAt = Get-Date
        }
        
    } catch {
        $errorMsg = "Failed to generate AD report: $($_.Exception.Message)"
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log $errorMsg 'ERROR'
        }
        throw $errorMsg
    }
}

function Get-ADReportData {
    <#
    .SYNOPSIS
    Collects all Active Directory data for report generation.
    
    .DESCRIPTION
    Gathers comprehensive AD information including users, groups, computers, 
    OUs, GPOs, and security events for analysis and reporting.
    #>
    
    param(
        [int]$Days,
        [int]$UserCreatedDays,
        [int]$DaysUntilPWExpireINT,
        [int]$ADModNumber
    )
    
    try {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Collecting AD data..." 'INFO'
        }
        
        # Initialize data collections
        $reportData = @{
            Users = @()
            Groups = @()
            Computers = @()
            OUs = @()
            GPOs = @()
            Domain = @{}
            Statistics = @{}
        }
        
        # Get all users (main data source)
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Retrieving all AD users..." 'INFO'
        }
        $allUsers = Get-ADUser -Filter * -Properties *
        $reportData.Users = $allUsers
        
        # Get GPOs
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Retrieving Group Policies..." 'INFO'
        }
        try {
            $gpos = Get-GPO -All | Select-Object DisplayName, GPOStatus, ModificationTime, 
                @{ Label = "ComputerVersion"; Expression = { $_.computer.dsversion } }, 
                @{ Label = "UserVersion"; Expression = { $_.user.dsversion } }
            $reportData.GPOs = $gpos
        } catch {
            if (Get-Command "Log" -ErrorAction SilentlyContinue) {
                Write-Log "Could not retrieve GPOs: $($_.Exception.Message)" 'WARNING'
            }
            $reportData.GPOs = @()
        }
        
        # Get domain information
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Retrieving domain information..." 'INFO'
        }
        $adInfo = Get-ADDomain
        $forestObj = Get-ADForest
        $reportData.Domain = @{
            Forest = $adInfo.Forest
            InfrastructureMaster = $adInfo.InfrastructureMaster
            RIDMaster = $adInfo.RIDMaster
            PDCEmulator = $adInfo.PDCEmulator
            DomainNamingMaster = $forestObj.DomainNamingMaster
            SchemaMaster = $forestObj.SchemaMaster
            RecycleBinStatus = Get-ADRecycleBinStatus
        }
        
        # Get groups
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Retrieving AD groups..." 'INFO'
        }
        $groups = Get-ADGroup -Filter * -Properties *
        $reportData.Groups = $groups
        
        # Get computers
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Retrieving AD computers..." 'INFO'
        }
        $computers = Get-ADComputer -Filter * -Properties *
        $reportData.Computers = $computers
        
        # Get OUs
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Retrieving Organizational Units..." 'INFO'
        }
        $ous = Get-ADOrganizationalUnit -Filter * -Properties *
        $reportData.OUs = $ous
        
        # Calculate statistics
        $reportData.Statistics = Get-ADStatistics -Users $allUsers -Groups $groups -Computers $computers -OUs $ous -Days $Days -UserCreatedDays $UserCreatedDays -DaysUntilPWExpireINT $DaysUntilPWExpireINT -ADModNumber $ADModNumber
        
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "AD data collection completed" 'INFO'
        }
        
        return $reportData
        
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error collecting AD data: $($_.Exception.Message)" 'ERROR'
        }
        throw
    }
}

function Get-ADRecycleBinStatus {
    <#
    .SYNOPSIS
    Checks if AD Recycle Bin is enabled.
    #>
    
    try {
        $recycleBinStatus = (Get-ADOptionalFeature -Filter 'name -like "Recycle Bin Feature"').EnabledScopes
        if ($recycleBinStatus.Count -lt 1) {
            return "Disabled"
        } else {
            return "Enabled"
        }
    } catch {
        return "Unknown"
    }
}

function Get-ADStatistics {
    <#
    .SYNOPSIS
    Calculates various AD statistics for the report.
    #>
    
    param(
        $Users,
        $Groups,
        $Computers,
        $OUs,
        [int]$Days,
        [int]$UserCreatedDays,
        [int]$DaysUntilPWExpireINT,
        [int]$ADModNumber
    )
    
    try {
        # User statistics
        $enabledUsers = ($Users | Where-Object { $_.Enabled -eq $true }).Count
        $disabledUsers = ($Users | Where-Object { $_.Enabled -eq $false }).Count
        
        # Group statistics
        $securityGroups = ($Groups | Where-Object { $_.GroupCategory -eq "Security" }).Count
        $distributionGroups = ($Groups | Where-Object { $_.GroupCategory -eq "Distribution" }).Count
        
        # Computer statistics
        $enabledComputers = ($Computers | Where-Object { $_.Enabled -eq $true }).Count
        $disabledComputers = ($Computers | Where-Object { $_.Enabled -eq $false }).Count
        
        # Recently created users
        $recentUsers = $Users | Where-Object { $_.whenCreated -ge ((Get-Date).AddDays(-$UserCreatedDays)).Date }
        
        # Users with expiring passwords
        $usersWithExpiringPasswords = Get-UsersWithExpiringPasswords -Users $Users -DaysUntilExpire $DaysUntilPWExpireINT
        
        # Users not logged on recently
        $inactiveUsers = Get-InactiveUsers -Users $Users -Days $Days
        
        # Recently modified AD objects
        $recentlyModifiedObjects = Get-RecentlyModifiedADObjects -Days $ADModNumber
        
        return @{
            Users = @{
                Total = $Users.Count
                Enabled = $enabledUsers
                Disabled = $disabledUsers
                RecentlyCreated = $recentUsers.Count
                WithExpiringPasswords = $usersWithExpiringPasswords.Count
                Inactive = $inactiveUsers.Count
            }
            Groups = @{
                Total = $Groups.Count
                Security = $securityGroups
                Distribution = $distributionGroups
            }
            Computers = @{
                Total = $Computers.Count
                Enabled = $enabledComputers
                Disabled = $disabledComputers
            }
            OUs = @{
                Total = $OUs.Count
            }
            RecentlyModifiedObjects = $recentlyModifiedObjects.Count
        }
        
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error calculating statistics: $($_.Exception.Message)" 'WARNING'
        }
        return @{}
    }
}

function Get-UsersWithExpiringPasswords {
    <#
    .SYNOPSIS
    Gets users with passwords expiring within specified days.
    #>
    
    param(
        $Users,
        [int]$DaysUntilExpire
    )
    
    $expiringUsers = @()
    $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days
    
    foreach ($user in $Users) {
        if (($user.PasswordNeverExpires -eq $false) -and ($user.Enabled -eq $true)) {
            $passwordSetDate = $user.PasswordLastSet
            
            if ($passwordSetDate) {
                # Check for Fine Grained Passwords
                try {
                    $passwordPol = Get-ADUserResultantPasswordPolicy $user
                    if ($passwordPol) {
                        $maxPasswordAge = $passwordPol.MaxPasswordAge.Days
                    }
                } catch {
                    # Use default policy
                }
                
                $expiresOn = $passwordSetDate.AddDays($maxPasswordAge)
                $daysToExpire = (New-TimeSpan -Start (Get-Date) -End $expiresOn).Days
                
                if ($daysToExpire -le $DaysUntilExpire -and $daysToExpire -gt 0) {
                    $expiringUsers += [PSCustomObject]@{
                        Name = $user.Name
                        DaysUntilExpire = $daysToExpire
                        ExpiresOn = $expiresOn
                    }
                }
            }
        }
    }
    
    return $expiringUsers
}

function Get-InactiveUsers {
    <#
    .SYNOPSIS
    Gets users who haven't logged on recently.
    #>
    
    param(
        $Users,
        [int]$Days
    )
    
    $inactiveUsers = @()
    $cutoffDate = (Get-Date).AddDays(-$Days)
    
    foreach ($user in $Users) {
        if ($user.Enabled -eq $true -and $user.LastLogon) {
            $lastLogon = [DateTime]::FromFileTime($user.LastLogon)
            if ($lastLogon -lt $cutoffDate) {
                $inactiveUsers += [PSCustomObject]@{
                    Name = $user.Name
                    LastLogon = $lastLogon
                    DaysSinceLogon = (New-TimeSpan -Start $lastLogon -End (Get-Date)).Days
                }
            }
        }
    }
    
    return $inactiveUsers
}

function Get-RecentlyModifiedADObjects {
    <#
    .SYNOPSIS
    Gets AD objects modified within specified days.
    #>
    
    param(
        [int]$Days
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$Days)
        $modifiedObjects = Get-ADObject -Filter { 
            whenchanged -gt $cutoffDate -and 
            ObjectClass -ne "domainDNS" -and 
            ObjectClass -ne "rIDManager" -and 
            ObjectClass -ne "rIDSet" 
        } -Properties *
        
        return $modifiedObjects
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error getting recently modified objects: $($_.Exception.Message)" 'WARNING'
        }
        return @()
    }
}

function LastLogonConvert {
    <#
    .SYNOPSIS
    Converts file time to readable date format.
    #>
    
    param($ftDate)
    
    if (-not $ftDate -or $ftDate -eq 0) {
        return "Never"
    }
    
    try {
        $date = [DateTime]::FromFileTime($ftDate)
        if ($date -lt (Get-Date '1/1/1900')) {
            return "Never"
        }
        return $date
    } catch {
        return "Never"
    }
}

#endregion

#region HTML Report Building Functions

function Build-ADHTMLReport {
    <#
    .SYNOPSIS
    Builds the complete HTML report from collected AD data.
    #>
    
    param(
        $ReportData,
        [string]$CompanyLogo,
        [string]$RightLogo,
        [string]$ReportTitle
    )
    
    try {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Building HTML report..." 'INFO'
        }
        
        # Create data tables for different sections
        $tables = Build-ADReportTables -ReportData $ReportData
        
        # Create charts
        $charts = Build-ADReportCharts
        
        # Build the final report
        $tabArray = @('Dashboard', 'Groups', 'Organizational Units', 'Users', 'Group Policy', 'Computers')
        
        $finalReport = New-Object 'System.Collections.Generic.List[System.Object]'
        $finalReport.Add($(Get-HTMLOpenPage -TitleText $ReportTitle -LeftLogoString $CompanyLogo -RightLogoString $RightLogo))
        $finalReport.Add($(Get-HTMLTabHeader -TabNames $tabArray))
        
        # Dashboard Tab
        $finalReport.Add($(Get-HTMLTabContentopen -TabName $tabArray[0] -TabHeading ("Report: " + (Get-Date -Format MM-dd-yyyy))))
        $finalReport.Add($(Get-HTMLContentOpen -HeaderText "Domain Information"))
        $finalReport.Add($(Get-HTMLContentTable $tables.DomainInfo))
        $finalReport.Add($(Get-HTMLContentClose))
        
        # Add dashboard sections
        Add-DashboardSections -FinalReport $finalReport -Tables $tables
        
        $finalReport.Add($(Get-HTMLTabContentClose))
        
        # Groups Tab
        $finalReport.Add($(Get-HTMLTabContentopen -TabName $tabArray[1] -TabHeading ("Report: " + (Get-Date -Format MM-dd-yyyy))))
        Add-GroupsSections -FinalReport $finalReport -Tables $tables -Charts $charts
        $finalReport.Add($(Get-HTMLTabContentClose))
        
        # OUs Tab
        $finalReport.Add($(Get-HTMLTabContentopen -TabName $tabArray[2] -TabHeading ("Report: " + (Get-Date -Format MM-dd-yyyy))))
        Add-OUSections -FinalReport $finalReport -Tables $tables -Charts $charts
        $finalReport.Add($(Get-HTMLTabContentClose))
        
        # Users Tab
        $finalReport.Add($(Get-HTMLTabContentopen -TabName $tabArray[3] -TabHeading ("Report: " + (Get-Date -Format MM-dd-yyyy))))
        Add-UsersSections -FinalReport $finalReport -Tables $tables -Charts $charts
        $finalReport.Add($(Get-HTMLTabContentClose))
        
        # GPO Tab
        $finalReport.Add($(Get-HTMLTabContentopen -TabName $tabArray[4] -TabHeading ("Report: " + (Get-Date -Format MM-dd-yyyy))))
        Add-GPOSections -FinalReport $finalReport -Tables $tables
        $finalReport.Add($(Get-HTMLTabContentClose))
        
        # Computers Tab
        $finalReport.Add($(Get-HTMLTabContentopen -TabName $tabArray[5] -TabHeading ("Report: " + (Get-Date -Format MM-dd-yyyy))))
        Add-ComputersSections -FinalReport $finalReport -Tables $tables -Charts $charts
        $finalReport.Add($(Get-HTMLTabContentClose))
        
        $finalReport.Add($(Get-HTMLClosePage))
        
        return $finalReport
        
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error building HTML report: $($_.Exception.Message)" 'ERROR'
        }
        throw
    }
}

function Build-ADReportTables {
    <#
    .SYNOPSIS
    Builds all data tables needed for the AD report.
    #>
    
    param($ReportData)
    
    try {
        $tables = @{}
        
        # Domain Information Table
        $tables.DomainInfo = @([PSCustomObject]@{
            'Domain' = $ReportData.Domain.Forest
            'AD Recycle Bin' = $ReportData.Domain.RecycleBinStatus
            'Infrastructure Master' = $ReportData.Domain.InfrastructureMaster
            'RID Master' = $ReportData.Domain.RIDMaster
            'PDC Emulator' = $ReportData.Domain.PDCEmulator
            'Domain Naming Master' = $ReportData.Domain.DomainNamingMaster
            'Schema Master' = $ReportData.Domain.SchemaMaster
        })
        
        # Groups Table
        $tables.Groups = @()
        foreach ($group in $ReportData.Groups) {
            $members = try {
                if ($group.Name -ne "Domain Users") {
                    $membersList = Get-ADGroupMember -Identity $group | Sort-Object DisplayName | Select-Object -ExpandProperty Name
                    if ($membersList) {
                        ($membersList -join ", ")
                    } else {
                        "No members"
                    }
                } else {
                    "Skipped Domain Users Membership"
                }
            } catch {
                "Error retrieving members"
            }
            
            $groupType = if ($group.GroupCategory -eq "Distribution") {
                "Distribution Group"
            } elseif ($group.GroupCategory -eq "Security") {
                try {
                    $email = (Get-ADGroup $group -Properties mail).mail
                    if ($email) {
                        "Mail-Enabled Security Group"
                    } else {
                        "Security Group"
                    }
                } catch {
                    "Security Group"
                }
            } else {
                $group.GroupCategory
            }
            
            $tables.Groups += [PSCustomObject]@{
                'Name' = $group.Name
                'Type' = $groupType
                'Members' = $members
                'Protected from Deletion' = $group.ProtectedFromAccidentalDeletion
            }
        }
        
        # Users Table
        $tables.Users = @()
        foreach ($user in $ReportData.Users) {
            $lastLogon = LastLogonConvert $user.LastLogon
            
            $tables.Users += [PSCustomObject]@{
                'Name' = $user.Name
                'UserPrincipalName' = $user.UserPrincipalName
                'Enabled' = $user.Enabled
                'Protected from Deletion' = $user.ProtectedFromAccidentalDeletion
                'Last Logon' = $lastLogon
                'Email Address' = $user.EmailAddress
                'Password Never Expires' = $user.PasswordNeverExpires
                'Password Last Set' = $user.PasswordLastSet
            }
        }
        
        # Computers Table  
        $tables.Computers = @()
        foreach ($computer in $ReportData.Computers) {
            $tables.Computers += [PSCustomObject]@{
                'Name' = $computer.Name
                'Enabled' = $computer.Enabled
                'Operating System' = $computer.OperatingSystem
                'Modified Date' = $computer.Modified
                'Password Last Set' = $computer.PasswordLastSet
                'Protect from Deletion' = $computer.ProtectedFromAccidentalDeletion
            }
        }
        
        # OUs Table
        $tables.OUs = @()
        foreach ($ou in $ReportData.OUs) {
            $linkedGPOs = "None"
            if ($ou.linkedgrouppolicyobjects -and $ou.linkedgrouppolicyobjects.Count -gt 0) {
                $gpoNames = @()
                foreach ($gpoLink in $ou.linkedgrouppolicyobjects) {
                    try {
                        $gpoGuid = ($gpoLink -split "{" | Select-Object -Last 1) -split "}" | Select-Object -First 1
                        $gpoName = (Get-GPO -Guid $gpoGuid -ErrorAction SilentlyContinue).DisplayName
                        if ($gpoName) { $gpoNames += $gpoName }
                    } catch {
                        # Skip invalid GPO links
                    }
                }
                if ($gpoNames.Count -gt 0) {
                    $linkedGPOs = $gpoNames -join ", "
                }
            }
            
            $tables.OUs += [PSCustomObject]@{
                'Name' = $ou.Name
                'Linked GPOs' = $linkedGPOs
                'Modified Date' = $ou.WhenChanged
                'Protected from Deletion' = $ou.ProtectedFromAccidentalDeletion
            }
        }
        
        # GPOs Table
        $tables.GPOs = @()
        foreach ($gpo in $ReportData.GPOs) {
            $tables.GPOs += [PSCustomObject]@{
                'Name' = $gpo.DisplayName
                'Status' = $gpo.GpoStatus
                'Modified Date' = $gpo.ModificationTime
                'User Version' = $gpo.UserVersion
                'Computer Version' = $gpo.ComputerVersion
            }
        }
        
        # Statistics tables
        $tables.UserStats = @([PSCustomObject]@{
            'Total Users' = $ReportData.Statistics.Users.Total
            'Enabled Users' = $ReportData.Statistics.Users.Enabled
            'Disabled Users' = $ReportData.Statistics.Users.Disabled
            'Recently Created' = $ReportData.Statistics.Users.RecentlyCreated
            'Expiring Passwords' = $ReportData.Statistics.Users.WithExpiringPasswords
            'Inactive Users' = $ReportData.Statistics.Users.Inactive
        })
        
        $tables.GroupStats = @([PSCustomObject]@{
            'Total Groups' = $ReportData.Statistics.Groups.Total
            'Security Groups' = $ReportData.Statistics.Groups.Security
            'Distribution Groups' = $ReportData.Statistics.Groups.Distribution
        })
        
        $tables.ComputerStats = @([PSCustomObject]@{
            'Total Computers' = $ReportData.Statistics.Computers.Total
            'Enabled Computers' = $ReportData.Statistics.Computers.Enabled
            'Disabled Computers' = $ReportData.Statistics.Computers.Disabled
        })
        
        return $tables
        
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error building data tables: $($_.Exception.Message)" 'ERROR'
        }
        throw
    }
}

function Build-ADReportCharts {
    <#
    .SYNOPSIS
    Creates chart objects for the AD report.
    #>
    
    try {
        $charts = @{}
        
        # User Status Pie Chart
        $charts.UserStatus = Get-HTMLPieChartObject
        $charts.UserStatus.Title = "Users Enabled vs Disabled"
        $charts.UserStatus.Size.Height = 250
        $charts.UserStatus.Size.Width = 250
        $charts.UserStatus.ChartStyle.ChartType = 'doughnut'
        $charts.UserStatus.ChartStyle.ColorSchemeName = 'Random'
        $charts.UserStatus.DataDefinition.DataNameColumnName = 'Name'
        $charts.UserStatus.DataDefinition.DataValueColumnName = 'Count'
        
        # Group Type Pie Chart
        $charts.GroupType = Get-HTMLPieChartObject
        $charts.GroupType.Title = "Group Types"
        $charts.GroupType.Size.Height = 250
        $charts.GroupType.Size.Width = 250
        $charts.GroupType.ChartStyle.ChartType = 'doughnut'
        $charts.GroupType.ChartStyle.ColorSchemeName = 'Random'
        $charts.GroupType.DataDefinition.DataNameColumnName = 'Name'
        $charts.GroupType.DataDefinition.DataValueColumnName = 'Count'
        
        # Computer Status Pie Chart
        $charts.ComputerStatus = Get-HTMLPieChartObject
        $charts.ComputerStatus.Title = "Computers Enabled vs Disabled"
        $charts.ComputerStatus.Size.Height = 250
        $charts.ComputerStatus.Size.Width = 250
        $charts.ComputerStatus.ChartStyle.ChartType = 'doughnut'
        $charts.ComputerStatus.ChartStyle.ColorSchemeName = 'Random'
        $charts.ComputerStatus.DataDefinition.DataNameColumnName = 'Name'
        $charts.ComputerStatus.DataDefinition.DataValueColumnName = 'Count'
        
        return $charts
        
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error creating charts: $($_.Exception.Message)" 'WARNING'
        }
        return @{}
    }
}

function Add-DashboardSections {
    param($FinalReport, $Tables)
    
    # User Statistics
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "User Statistics"))
    $FinalReport.Add($(Get-HTMLContentTable $Tables.UserStats))
    $FinalReport.Add($(Get-HTMLContentClose))
    
    # Group Statistics
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Group Statistics"))
    $FinalReport.Add($(Get-HTMLContentTable $Tables.GroupStats))
    $FinalReport.Add($(Get-HTMLContentClose))
    
    # Computer Statistics
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Computer Statistics"))
    $FinalReport.Add($(Get-HTMLContentTable $Tables.ComputerStats))
    $FinalReport.Add($(Get-HTMLContentClose))
}

function Add-GroupsSections {
    param($FinalReport, $Tables, $Charts)
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Groups Overview"))
    $FinalReport.Add($(Get-HTMLContentTable $Tables.GroupStats))
    $FinalReport.Add($(Get-HTMLContentClose))
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Active Directory Groups"))
    $FinalReport.Add($(Get-HTMLContentDataTable $Tables.Groups -HideFooter))
    $FinalReport.Add($(Get-HTMLContentClose))
}

function Add-OUSections {
    param($FinalReport, $Tables, $Charts)
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Organizational Units"))
    $FinalReport.Add($(Get-HTMLContentDataTable $Tables.OUs -HideFooter))
    $FinalReport.Add($(Get-HTMLContentClose))
}

function Add-UsersSections {
    param($FinalReport, $Tables, $Charts)
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Users Overview"))
    $FinalReport.Add($(Get-HTMLContentTable $Tables.UserStats))
    $FinalReport.Add($(Get-HTMLContentClose))
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Active Directory Users"))
    $FinalReport.Add($(Get-HTMLContentDataTable $Tables.Users -HideFooter))
    $FinalReport.Add($(Get-HTMLContentClose))
}

function Add-GPOSections {
    param($FinalReport, $Tables)
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Group Policies"))
    $FinalReport.Add($(Get-HTMLContentDataTable $Tables.GPOs -HideFooter))
    $FinalReport.Add($(Get-HTMLContentClose))
}

function Add-ComputersSections {
    param($FinalReport, $Tables, $Charts)
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Computers Overview"))
    $FinalReport.Add($(Get-HTMLContentTable $Tables.ComputerStats))
    $FinalReport.Add($(Get-HTMLContentClose))
    
    $FinalReport.Add($(Get-HTMLContentOpen -HeaderText "Active Directory Computers"))
    $FinalReport.Add($(Get-HTMLContentDataTable $Tables.Computers -HideFooter))
    $FinalReport.Add($(Get-HTMLContentClose))
}

#endregion

#region Plugin Data and UI Functions

function Get-ADReportPluginData {
    <#
    .SYNOPSIS
    Retrieves current plugin data for display in the UI.
    #>
    
    try {
        $uptime = if ($script:PluginData.LoadTime) {
            (Get-Date) - $script:PluginData.LoadTime
        } else {
            New-TimeSpan
        }
        
        return @{
            Status = $script:PluginData.Status
            LoadTime = $script:PluginData.LoadTime.ToString("yyyy-MM-dd HH:mm:ss")
            Uptime = "{0:dd}d {0:hh}h {0:mm}m {0:ss}s" -f $uptime
            ReportsGenerated = $script:PluginData.ReportsGenerated
            LastReport = if ($script:PluginData.LastReport) { 
                $script:PluginData.LastReport.ToString("yyyy-MM-dd HH:mm:ss") 
            } else { 
                "Never" 
            }
            Configuration = $script:PluginConfig
        }
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error getting plugin data: $($_.Exception.Message)" 'ERROR'
        }
        return @{
            Status = "Error"
            Error = $_.Exception.Message
        }
    }
}

function Get-ADReportPluginSettings {
    <#
    .SYNOPSIS
    Retrieves current plugin settings.
    #>
    
    return $script:PluginConfig
}

function Set-ADReportPluginSettings {
    <#
    .SYNOPSIS
    Updates plugin settings.
    #>
    
    param(
        [hashtable]$Settings
    )
    
    try {
        foreach ($key in $Settings.Keys) {
            if ($script:PluginConfig.ContainsKey($key)) {
                $script:PluginConfig[$key] = $Settings[$key]
            }
        }
        
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Plugin settings updated" 'INFO'
        }
        
        return $true
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error updating plugin settings: $($_.Exception.Message)" 'ERROR'
        }
        return $false
    }
}

#endregion

#region UI Integration and Event Handlers

function Initialize-ADReportPluginUI {
    <#
    .SYNOPSIS
    Initializes the plugin UI elements and event handlers.
    
    .DESCRIPTION
    This function is called to set up UI event handlers and initialize form values.
    It should be called after the XAML is loaded and UI elements are available.
    #>
    
    param(
        $UIElements
    )
    
    try {
        # Store UI element references
        $script:UIElements = $UIElements
        
        # Initialize form values from configuration
        if ($UIElements.ReportTitleTextBox) {
            $UIElements.ReportTitleTextBox.Text = $script:PluginConfig.ReportTitle
        }
        if ($UIElements.CompanyLogoTextBox) {
            $UIElements.CompanyLogoTextBox.Text = $script:PluginConfig.CompanyLogo
        }
        if ($UIElements.RightLogoTextBox) {
            $UIElements.RightLogoTextBox.Text = $script:PluginConfig.RightLogo
        }
        if ($UIElements.SavePathTextBox) {
            $UIElements.SavePathTextBox.Text = $script:PluginConfig.ReportSavePath
        }
        if ($UIElements.DaysTextBox) {
            $UIElements.DaysTextBox.Text = $script:PluginConfig.Days.ToString()
        }
        if ($UIElements.UserCreatedDaysTextBox) {
            $UIElements.UserCreatedDaysTextBox.Text = $script:PluginConfig.UserCreatedDays.ToString()
        }
        if ($UIElements.PasswordExpireDaysTextBox) {
            $UIElements.PasswordExpireDaysTextBox.Text = $script:PluginConfig.DaysUntilPWExpireINT.ToString()
        }
        if ($UIElements.ModifiedDaysTextBox) {
            $UIElements.ModifiedDaysTextBox.Text = $script:PluginConfig.ADModNumber.ToString()
        }
        if ($UIElements.AutoOpenCheckBox) {
            $UIElements.AutoOpenCheckBox.IsChecked = $script:PluginConfig.AutoOpenReport
        }
        
        # Set up event handlers
        if ($UIElements.GenerateButton) {
            $UIElements.GenerateButton.Add_Click($global:ADReportPlugin_GenerateClick)
        }
        if ($UIElements.BrowseSavePath) {
            $UIElements.BrowseSavePath.Add_Click($global:ADReportPlugin_BrowsePathClick)
        }
        if ($UIElements.BrowseCompanyLogo) {
            $UIElements.BrowseCompanyLogo.Add_Click($global:ADReportPlugin_BrowseCompanyLogoClick)
        }
        if ($UIElements.BrowseRightLogo) {
            $UIElements.BrowseRightLogo.Add_Click($global:ADReportPlugin_BrowseRightLogoClick)
        }
        if ($UIElements.RefreshButton) {
            $UIElements.RefreshButton.Add_Click($global:ADReportPlugin_RefreshClick)
        }
        if ($UIElements.ClearLogButton) {
            $UIElements.ClearLogButton.Add_Click($global:ADReportPlugin_ClearLogClick)
        }
        
        # Initialize status
        Update-ADReportPluginStatus "Ready to generate AD report"
        Add-ADReportPluginLog "AD Report plugin UI initialized successfully"
        
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "AD Report plugin UI initialized" 'INFO'
        }
        
        return $true
        
    } catch {
        if (Get-Command "Log" -ErrorAction SilentlyContinue) {
            Write-Log "Error initializing AD Report plugin UI: $($_.Exception.Message)" 'ERROR'
        }
        return $false
    }
}

function Update-ADReportPluginStatus {
    <#
    .SYNOPSIS
    Updates the status display in the plugin UI.
    #>
    
    param(
        [string]$Status,
        [string]$DetailedStatus = $null
    )
    
    try {
        if ($script:UIElements.StatusTextBlock) {
            $script:UIElements.StatusTextBlock.Text = $Status
        }
        if ($DetailedStatus -and $script:UIElements.DetailedStatusTextBlock) {
            $script:UIElements.DetailedStatusTextBlock.Text = $DetailedStatus
        }
    } catch {
        # Silently continue if UI elements aren't available
    }
}

function Add-ADReportPluginLog {
    <#
    .SYNOPSIS
    Adds a message to the plugin's activity log.
    #>
    
    param(
        [string]$Message
    )
    
    try {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $logEntry = "[$timestamp] $Message"
        
        if ($script:UIElements.ActivityLogTextBox) {
            $script:UIElements.ActivityLogTextBox.AppendText("$logEntry`r`n")
            $script:UIElements.ActivityLogTextBox.ScrollToEnd()
        }
    } catch {
        # Silently continue if UI elements aren't available
    }
}

function Show-ADReportProgress {
    <#
    .SYNOPSIS
    Shows or hides the progress indicator.
    #>
    
    param(
        [bool]$Show
    )
    
    try {
        if ($script:UIElements.ReportProgress) {
            $script:UIElements.ReportProgress.Visibility = if ($Show) { 'Visible' } else { 'Collapsed' }
        }
        if ($script:UIElements.GenerateButton) {
            $script:UIElements.GenerateButton.IsEnabled = -not $Show
        }
    } catch {
        # Silently continue if UI elements aren't available
    }
}

# Event handler functions
$global:ADReportPlugin_GenerateClick = {
    try {
        # Get current settings from UI
        $settings = @{
            CompanyLogo = $script:UIElements.CompanyLogoTextBox.Text
            RightLogo = $script:UIElements.RightLogoTextBox.Text
            ReportTitle = $script:UIElements.ReportTitleTextBox.Text
            ReportSavePath = $script:UIElements.SavePathTextBox.Text
            Days = [int]$script:UIElements.DaysTextBox.Text
            UserCreatedDays = [int]$script:UIElements.UserCreatedDaysTextBox.Text
            DaysUntilPWExpireINT = [int]$script:UIElements.PasswordExpireDaysTextBox.Text
            ADModNumber = [int]$script:UIElements.ModifiedDaysTextBox.Text
            ShowReport = $script:UIElements.AutoOpenCheckBox.IsChecked
        }
        
        # Update UI
        Update-ADReportPluginStatus "Generating AD report..." "Initializing report generation..."
        Add-ADReportPluginLog "Starting AD report generation..."
        Show-ADReportProgress $true
        
        # Generate report asynchronously (in real implementation, you'd use runspaces)
        $result = Invoke-ADReportGeneration @settings
        
        # Update UI on success
        Update-ADReportPluginStatus "Report generated successfully!" "Report saved to: $($result.ReportPath)"
        Add-ADReportPluginLog "Report generated successfully: $($result.ReportPath)"
        
        if ($script:UIElements.LastReportTextBlock) {
            $script:UIElements.LastReportTextBlock.Text = "Last Report: $($result.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        
        [System.Windows.MessageBox]::Show(
            "AD Report generated successfully!`nSaved to: $($result.ReportPath)",
            "AD Report",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
        
    } catch {
        Update-ADReportPluginStatus "Error generating report" "Error: $($_.Exception.Message)"
        Add-ADReportPluginLog "Error: $($_.Exception.Message)"
        
        [System.Windows.MessageBox]::Show(
            "Error generating report: $($_.Exception.Message)",
            "AD Report Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    } finally {
        Show-ADReportProgress $false
    }
}

$global:ADReportPlugin_BrowsePathClick = {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select folder to save AD reports"
        $folderDialog.ShowNewFolderButton = $true
        $folderDialog.SelectedPath = $script:UIElements.SavePathTextBox.Text
        
        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:UIElements.SavePathTextBox.Text = $folderDialog.SelectedPath
            Add-ADReportPluginLog "Save path updated: $($folderDialog.SelectedPath)"
        }
    } catch {
        [System.Windows.MessageBox]::Show(
            "Error selecting folder: $($_.Exception.Message)",
            "Folder Selection Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
    }
}

$global:ADReportPlugin_BrowseCompanyLogoClick = {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Title = "Select Company Logo"
        $fileDialog.Filter = "Image Files|*.png;*.jpg;*.jpeg;*.gif;*.bmp|All Files|*.*"
        
        if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:UIElements.CompanyLogoTextBox.Text = $fileDialog.FileName
            Add-ADReportPluginLog "Company logo updated: $($fileDialog.FileName)"
        }
    } catch {
        [System.Windows.MessageBox]::Show(
            "Error selecting logo file: $($_.Exception.Message)",
            "File Selection Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
    }
}

$global:ADReportPlugin_BrowseRightLogoClick = {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Title = "Select Right Logo"
        $fileDialog.Filter = "Image Files|*.png;*.jpg;*.jpeg;*.gif;*.bmp|All Files|*.*"
        
        if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:UIElements.RightLogoTextBox.Text = $fileDialog.FileName
            Add-ADReportPluginLog "Right logo updated: $($fileDialog.FileName)"
        }
    } catch {
        [System.Windows.MessageBox]::Show(
            "Error selecting logo file: $($_.Exception.Message)",
            "File Selection Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
    }
}

$global:ADReportPlugin_RefreshClick = {
    try {
        # Reload configuration
        Initialize-ADReportPlugin
        
        # Update UI with current values
        if ($script:UIElements) {
            Initialize-ADReportPluginUI $script:UIElements
        }
        
        Add-ADReportPluginLog "Plugin settings refreshed"
        Update-ADReportPluginStatus "Settings refreshed" "Plugin configuration reloaded"
        
    } catch {
        Add-ADReportPluginLog "Error refreshing settings: $($_.Exception.Message)"
        Update-ADReportPluginStatus "Error refreshing settings"
    }
}

$global:ADReportPlugin_ClearLogClick = {
    try {
        if ($script:UIElements.ActivityLogTextBox) {
            $script:UIElements.ActivityLogTextBox.Clear()
            Add-ADReportPluginLog "Activity log cleared"
        }
    } catch {
        # Silently continue
    }
}

#endregion

# Export functions
Export-ModuleMember -Function Initialize-ADReportPlugin, Invoke-ADReportGeneration, Get-ADReportPluginData, Get-ADReportPluginSettings, Set-ADReportPluginSettings, Initialize-ADReportPluginUI

# Initialize script-level variables
$script:PluginData = @{}
$script:PluginConfig = @{}
$script:UIElements = @{}

# Auto-initialize when module is loaded
if (Get-Command Log -ErrorAction SilentlyContinue) {
    Write-Log "AD Report plugin module loaded - ready for initialization" 'DEBUG'
}

