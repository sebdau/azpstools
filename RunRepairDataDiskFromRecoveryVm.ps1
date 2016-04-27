function RunRepairDataDiskFromRecoveryVm (
    [string] $ServiceName,
    [string] $RecoVmName,
    [string] $GuestRecoveryScriptUri = 'https://raw.githubusercontent.com/sedau/azpstools/master/procdump-TS.ps1',
    [string] $GuestRecoveryScript= "TS_RecoveryWorker2.ps1"
    )
{
    
    $VM = get-azurevm $ServiceName , $RecoVmName

    if ( $VM.OSVirtualHardDisk.OS -eq "Windows")
    {
        $vm | Set-AzureVMCustomScriptExtension -VM $VM -FileUri $GuestRecoveryScriptUri  -Run 'procdump-TS.ps1' | Update-AzureVM 

    }
    else
    {
        Write-Host "Linux guest os recovery scripting not enabled yet"
        Write-Host "Please ssh into the recovery vm yourself and fix the attached data disk: see step 22..."
        Write-host "https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/"
        Read-Host -Prompt "press any key once done to continue with recreation"
    }
}