function RunRepairDataDiskFromRecoveryVm  (
    [string] $ServiceName,
    [string] $RecoVmName,
    [string] $GuestRecoveryScriptUri = 'https://raw.githubusercontent.com/sebdau/azpstools/master/FixDisk/TS_RecoveryWorker2.ps1',
    [string] $GuestRecoveryScript= "TS_RecoveryWorker2.ps1"
    )
{
    Add-Type -AssemblyName System.Web

    $VM = get-azurevm $ServiceName  $RecoVmName

    if ( $VM.VM.OSVirtualHardDisk.OS -eq "Windows")
    {
        $csex = $vm |Get-AzureVMCustomScriptExtension
        if ( $csex) 
        {
            $temp = $vm |Remove-AzureVMCustomScriptExtension | Update-AzureVM
        }

        $temp = $vm | Set-AzureVMCustomScriptExtension -FileUri $GuestRecoveryScriptUri  -Run $GuestRecoveryScript | Update-AzureVM 
        
        $lastOutput =""

        do
        {            
            $VM = get-azurevm $ServiceName  $RecoVmName
            $csStatus = $vm.ResourceExtensionStatusList | where HandlerName -EQ 'Microsoft.Compute.CustomScriptExtension' | select -ExpandProperty ExtensionSettingStatus
            if ( $csStatus.Status -eq  'Error' )
            {
                Write-Error ($csStatus.SubStatusList | where Name -EQ 'StdErr' | select -ExpandProperty FormattedMessage | select -ExpandProperty Message)                
                $exit = $true
            }
            elseif ( ($csStatus.Status -eq 'Ready') -or ($csStatus.Status -eq 'Success'))
            {
                $exit = $true
                $outMsg = $csStatus.SubStatusList | where Name -EQ 'StdOut' | select -ExpandProperty FormattedMessage | select -ExpandProperty Message
                $outMsg = [System.Web.HttpUtility]::HtmlDecode($outMsg)
                $outMsg = $outMsg -replace "\\n","`n"
                if ( $outMsg -ne $lastOutput)
                {
                    Write-Warning "Current output from recovery vm:"
                    Write-Output $outMsg
                    $lastOutput = $outMsg
                }                
            }
            else
            {        
                $exit = $false                       
                Start-Sleep -Seconds 15 | Out-Null
                $outMsg = $csStatus.SubStatusList | where Name -EQ 'StdOut' | select -ExpandProperty FormattedMessage | select -ExpandProperty Message
                $outMsg = [System.Web.HttpUtility]::HtmlDecode($outMsg)
                $outMsg = $outMsg -replace "\\n","`n"
                if ( $outMsg -ne $lastOutput)
                {
                    Write-Warning "Current output from recovery vm:"
                    Write-Output $outMsg
                    $lastOutput = $outMsg
                }
            }          
            

        }until ($exit)
    }
    else
    {
        Write-Host "Linux guest os recovery scripting not enabled yet"
        Write-Host "Please ssh into the recovery vm yourself and fix the attached data disk: see step 22..."
        Write-host "https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/"
        Read-Host -Prompt "press any key once done to continue with recreation"
    }
}
