$SubscriptionId = '7fb3973d-3253-47d7-bc3e-456c3a0b33f7'
$StorageAccountName = 'sebdauvs15' 
$ServiceName = 'sbdauvs15-recover'
$VMName = 'sebdauvs15' 
$RecoveryAdmin = 'recoveryAdmin'
$RecoveryPW = 'LetMeInNow123'

$RecoveryVMName = 'RC' + $(get-date -f yyMMddHHmm)
$VMExportPath = $env:TEMP + '\' + $ServiceName + '_'  + $VMName + '.xml'

$RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Windows Server 2012 R2 Datacenter'  | sort PublishedDate -Descending | select  -First 1

#set subscription and premium storage account where os disk is 
Set-AzureSubscription -SubscriptionId $SubscriptionId -CurrentStorageAccountName $StorageAccountName 

#get defect vm object and export cfg to disk (temp)
$vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
$vm | Export-AzureVM -Path $VMExportPath
Write-Host 'Original VM Configuration written to ' $VMExportPath -ForegroundColor Yellow

#create new recovery in size of the defect vm (will create premium storage vm if needed)
$recoveryVM = New-AzureQuickVM -WaitForBoot -Windows -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -AdminUsername $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName 

#once the recovery vm has booted in the same cloud service (to prevent VIP loss) we get rid of the defect vm (but keep disks)
Remove-AzureVm -ServiceName $ServiceName -Name $VMName 

#now we need to wait for a few secs until the os disk was released
Start-Sleep -Seconds 60 | Out-Null

#than we try to add the 
$recoveryVM = Get-AzureVM -ServiceName $ServiceName -Name $RecoveryVMName
$recoveryVM | Add-AzureDataDisk -Import -DiskName $vm.VM.OSVirtualHardDisk.DiskName  -LUN 0 | Update-AzureVM 

Write-Output 'you can now connect remote desktop to the recovery vm ' $RecoveryVMName ' and fix issues on drive f: which is the os disk of the temp deleted vm ' $VMName
Write-Output 'once you are done please setup and run recreatevm.ps'


