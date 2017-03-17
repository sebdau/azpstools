function RunRepairDataDiskFromRmRecoveryVm  (
    [string] $RecourceGroup,
    [string] $RecoveryVmName,
    [string] $GuestRecoveryScriptUri = 'https://raw.githubusercontent.com/sebdau/azpstools/master/FixDisk/TS_RecoveryWorker2.ps1',
    [string] $GuestRecoveryScript= "TS_RecoveryWorker2.ps1"
    )
{   

    $VM = Get-AzureRmVM -ResourceGroupName $RecourceGroup -Name $RecoveryVmName
    
    #see if this vm already has the csext enabled... 
    $ext = get-AzureRmVM $RecourceGroup $RecoveryVmName | select  -ExpandProperty Extensions | where VirtualMachineExtensionType -EQ 'CustomScriptExtension'
    if ( $ext )
    {
        Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $RecourceGroup -VMName $RecoveryVmName -Name $ext.Name -Force
    }

    if ( $VM.OSProfile.WindowsConfiguration )
    {     
        
        #build a unique name for this script run (one per minute)
        $ScriptExtInstance = 'Recovery' + $(get-date -f yyMMddHHmm)    

        $temp = Set-AzureRmVMCustomScriptExtension -Location $vm.Location -ResourceGroupName $RecourceGroup -VMName $RecoveryVmName -FileUri $GuestRecoveryScriptUri  -Run $GuestRecoveryScript -Name $ScriptExtInstance 
        
        $status = Get-AzureRmVMExtension -ResourceGroupName $RecourceGroup -VMName $RecoveryVmName -Name $ScriptExtInstance -Status
        
        Write-Output $status.SubStatuses
                
        Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $RecourceGroup -VMName $RecoveryVmName -Name $ScriptExtInstance -Force
    }
    else
    {
        Write-Host "Linux guest os recovery scripting not enabled yet"
        Write-Host "Please ssh into the recovery vm yourself and fix the attached data disk: see step 22..."
        Write-host "https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/"
        Read-Host -Prompt "press any key once done to continue with recreation"
    }
}

