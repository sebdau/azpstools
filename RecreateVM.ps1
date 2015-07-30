$SubscriptionId = '7fb3973d-3253-47d7-bc3e-456c3a0b33f7'
$StorageAccountName = 'sebdauvs15' 
$OSDiskName = 'sebdauvs15-sebdauvs15-os-1438250832440'
$DestServiceName = 'sbdauvs15-recover'
#path to vm export xml (usually created while running recoverVM.ps1)
$VMExportPath = $env:TEMP + '\' + $DestServiceName + '_'  + $DestVMName + '.xml'

#default values only used when vm export path can not be imported as vm
$DestVMName = 'sebdauvs15'
$DestVMSize = 'Standard_DS2' 
$PublicRdpPort = 3389
$SubNetNames = '' #"PubSubnet","PrivSubnet" #leave empty if not required
$DataDiskNames = $null #'sebdauvs15-sebdauvs15-data-1'. 'sebdauvs15-sebdauvs15-data-1' #leave empty if not required
###################################################################################################################

#set subscription and premium storage account where os disk is 
Set-AzureSubscription -SubscriptionId $SubscriptionId -CurrentStorageAccountName $StorageAccountName

#get location from storage account
$location = (Get-AzureStorageAccount -StorageAccountName $StorageAccountName).Location

#get the unattached os disk
$OSDisk = Get-AzureDisk -DiskName $OSDiskName
if ( $OSDisk.AttachedTo ) #asuming this disk is attached to recovery vm
{
    $attachedVm = Get-AzureVM -ServiceName $OSDisk.AttachedTo.HostedServiceName -Name $OSDisk.AttachedTo.RoleName
    $attachedVm | Remove-AzureDataDisk -LUN 0 | Update-AzureVM
    Start-Sleep -Seconds 30
} 

try
{
   $vm = Import-AzureVM   -Path $VMExportPath    
}
catch
{

    #prepare the 
    $vm = New-AzureVMConfig -Name $DestVMName -InstanceSize $DestVMSize -DiskName $OSDiskName

    #Attached the data disks to the new VM
    foreach ($dataDiskName in $DataDiskNames)
    {    
        $vm | Add-AzureDataDisk -DiskName $DataDiskName
    } 

    # Edit this if you want to add more custimization to the new VM
    $vm | Add-AzureEndpoint -Protocol tcp -LocalPort 3389 -PublicPort $PublicRdpPort -Name 'Rdp'
    if ( ! [string]::IsNullOrEmpty($SubNetNames ))
    {
        $vm | Set-AzureSubnet $SubNetNames
    }
}

New-AzureVM -ServiceName $DestServiceName -VMs $vm -Location $location -WaitForBoot