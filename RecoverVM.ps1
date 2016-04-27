Param(
    [Parameter(Mandatory=$true)][string]$ServiceName ,
    [Parameter(Mandatory=$true)][string]$VMName 
)

$Sub = Get-AzureSubscription -Current
if ( ! $Sub ) 
{
    Write-Output "no current subscription set - please run add-azureaccount + select-azuresubscription -current first for the subscription containing your target vm!"
    return
}

. $PSScriptRoot\AttachOsDiskAsDataDiskToRecoveryVm.ps1
. $PSScriptRoot\RecreateVmFromVhd.ps1
. $PSScriptRoot\RunRepairDataDiskFromRecoveryVm.ps1


$recoVM = AttachOsDiskAsDataDiskToRecoveryVm $ServiceName $VMName

RunRepairDataDiskFromRecoveryVm $ServiceName $recoVM.Name

RecreateVmFromVhd $ServiceName $VMName  $true







