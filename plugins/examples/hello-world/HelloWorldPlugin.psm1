# Hello World Plugin for NinjaSuite
# Simple example plugin demonstrating basic functionality

function Initialize-HelloWorldPlugin {
    param($PluginConfig, $NinjaSuiteContext)
    
    Write-Log "Hello World plugin initialized!" -Level 'INFO'
    return @{ Status = 'Success'; Message = 'Plugin ready' }
}

function Invoke-HelloWorldOperation {
    param($Parameters)
    
    $message = "Hello from the NinjaSuite plugin system!"
    Write-Log $message -Level 'INFO'
    
    return New-NinjaResult -Success $true -Data @{
        Message = $message
        Timestamp = Get-Date
        PluginVersion = "1.0.0"
    }
}

function Show-HelloWorldUI {
    param($ParentWindow)
    
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Hello from the Hello World plugin!`n`nThis is an example of plugin UI integration.",
        "Hello World Plugin",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

Export-ModuleMember -Function Initialize-HelloWorldPlugin, Invoke-HelloWorldOperation, Show-HelloWorldUI