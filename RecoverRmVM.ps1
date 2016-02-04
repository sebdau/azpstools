$Global:TVM
$Global:RVM


$subId = 'dfdb5f22-fa43-40bf-bb13-c631f7e63a89'
$rgName = 'sebdauv2-vm5-rg'
$vmName = 'sebdauv2-vm'

Function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}

Function InstallWinRMCertificateForVM()
{
    param([string] $ServiceName, [string] $VMName)
	if((IsAdmin) -eq $false)
	{
		Write-Error "Must run PowerShell elevated to install WinRM certificates."
		return
	}
	
    Write-Host "Installing WinRM Certificate for remote access: $ServiceName $VMName"
	$WinRMCert = (Get-AzureVM -ServiceName $ServiceName -Name $VMName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
	$AzureX509cert = Get-AzureCertificate -ServiceName $ServiceName -Thumbprint $WinRMCert -ThumbprintAlgorithm sha1

	$certTempFile = [IO.Path]::GetTempFileName()
	$AzureX509cert.Data | Out-File $certTempFile

	# Target The Cert That Needs To Be Imported
	$CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certTempFile

	$store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
	$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
	$store.Add($CertToImport)
	$store.Close()
	
    Import-Certificate -FilePath $certTempFile -CertStoreLocation "Cert:\localmachine\root" 

    Import-Certificate 
	Remove-Item $certTempFile
}

function RemoteFixDisk($rgName, $RecVMName)
{    
    $secPassword = ConvertTo-SecureString  $RecoveryPW -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($RecoveryAdmin, $secPassword)
    
    if ( $RecoveryVMName -eq $null)
    {
        Write-Host 'Please specify the recovery VM name:'
        $RecoveryVMName = Read-Host 
    }

    InstallWinRMCertificateForVM  -ServiceName $ServiceName  -VMName $RecoveryVMName -debug
    $uri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $RecoveryVMName 
    Invoke-Command –ConnectionUri $uri –Credential $credential –ScriptBlock     { chkdsk F: /F } | Write-Debug
    Invoke-Command –ConnectionUri $uri –Credential $credential –ScriptBlock     { bcdedit /store F:\boot\bcd /set {default} recoveryenabled no } | Write-Debug        
    Invoke-Command –ConnectionUri $uri –Credential $credential –ScriptBlock     { 
        [string]$bcdout = bcdedit /store F:\boot\bcd /enum
        if ( $bcdout.Contains('unknown'))
        {
            bcdedit /store F:\boot\bcd  /set {default} osdevice boot
            bcdedit /store F:\boot\bcd  /set {default} device boot
        } 
    } | Write-Debug        
        
     Invoke-Command –ConnectionUri $uri –Credential $credential –ScriptBlock     { 
        dir F:\Windows\System32\Config\RegBack\SYSTEM
        if ((Get-Item 'F:\Windows\System32\Config\RegBack\SYSTEM').length -gt 0kb) 
        { 
            move F:\windows\system32\config\system F:\windows\system32\config\system_org 
            copy F:\windows\system32\config\Regback\system F:\windows\system32\config\system 
        }  
     } | Write-Debug            
    
}

function SetupAccount(	
	[string]$subId
)
{
	$pspTempPath = $env:TEMP+'\'+$subid+'.acnt'

	if ( Test-Path $pspTempPath )
	{
		Select-AzureRmProfile -Path $pspTempPath        
	}
    
    $Error.Clear()
    $vms = Get-AzureRmVM 
    if ($Error.Count -gt 0 )
    {	
		$acnt= Login-AzureRmAccount		
		Save-AzureRmProfile -Path( $env:TEMP+'\'+$subid+'.acnt')
	}

    Select-AzureRmSubscription -SubscriptionId $subId 
	
}

function CreateVmAttachRestoreDisk(
    [string]$rgName,
    [string]$targetVmName,
    [string]$targetVmSize,      
    [string]$targetVmNicId,
    [string]$targetVmVhdUri,
    [bool]$targetVmIsWin = $true,
    [string]$targetVmLocation 
)
{

#create reco vm with ts in name
$recoveryVMName = $targetVmName + 'RC' + $(get-date -f yyMMddHHmm)
$recoveryVm = New-AzureRmVMConfig -VMName $recoveryVMName -VMSize $targetVmSize;
#add nic 1 to reco vm	 
$recoveryVm = Add-AzureRmVMNetworkInterface -VM $recoveryVm -Id $targetVmNicId;

#$pib = Get-AzureRmPublicIpAddress -ResourceGroupName $rgName | where Id -EQ 
#$recoveryVm = Set-AzureRmPublicIpAddress 

#attach disk	
$cred=Get-Credential -Message "Define name and password for recovery VM"
	
if ( $targetVmIsWin )
{
	# Specify the image and local administrator account, and then add the NIC
	$pubName="MicrosoftWindowsServer"
	$offerName="WindowsServer"
	$skuName="2012-R2-Datacenter"		
	$recoveryVm=Set-AzureRmVMOperatingSystem -VM $recoveryVm -Windows -ComputerName $targetVmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
	$recoveryVm=Set-AzureRmVMSourceImage -VM $recoveryVm -PublisherName $pubName -Offer $offerName -Skus $skuName -Version "latest"		
}
else
{
	# Specify the image and local administrator account, and then add the NIC
	$pubName="Canonical"
	$offerName="UbuntuServer"
	$skuName="15.04-DAILY"		
	$recoveryVm=Set-AzureRmVMOperatingSystem -VM $recoveryVm -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
	$recoveryVm=Set-AzureRmVMSourceImage -VM $recoveryVm -PublisherName $pubName -Offer $offerName -Skus $skuName -Version "latest"		
}
	
#set os disk name

$vhdURI = $targetVmVhdUri
$vhdURI = $vhdURI.Substring(0,$vhdURI.LastIndexOf('/')+1) + $recoveryVMName + '.vhd'

$recoveryVm=Set-AzureRmVMOSDisk -VM $recoveryVm -Name ($recoveryVMName + 'OsDisk') -VhdUri $vhdURI -CreateOption fromImage
#deploy
New-AzureRmVM -ResourceGroupName $rgName -vm $recoveryVm -Location $targetVmLocation

#attach disk after creation because of xio bug
$recoveryVm = Get-AzureRmVM -ResourceGroupName $rgName -Name $recoveryVMName
$recoveryVm = Add-AzureRmVMDataDisk -VM $recoveryVm -Name 'osDiskToRecover' -Caching None -Lun 0 -VhdUri $targetVmVhdUri -CreateOption attach -DiskSizeInGB $null

$recoveryVm | Update-AzureRmVM

$Global:RVM = $recoveryVm

}

function RecreateVm(
    $rgName,
    $vmName,
    $vmSize,
    $nicId,
    $vmLocation,
    $osDiskUri)
{
        

	$vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize;
	 
	
		 
	$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nicId;
	 
	$osDiskName = $vmName + "-OSDISK"
	
	 
	$vm = Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskUri  -Name $osDiskName -CreateOption attach -Windows
	 
	New-AzureRmVM -ResourceGroupName $rgname -Location $vmLocation -VM $vm

}

function RemoveVm($rgName, $vmName)
{
    
    $Global:TVM= Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName
    Remove-azurermvm -ResourceGroupName $rgName -Name $vmName    
    
}

SetupAccount -subId $subId
RemoveVM $rgName $vmName

CreateVmAttachRestoreDisk $rgName $Global:TVM.Name $Global:TVM.HardwareProfile.VmSize `
                            $Global:TVM.NetworkInterfaceIDs[0] `
                            $Global:TVM.StorageProfile.OSDisk.Vhd.Uri `
                            $true $Global:TVM.Location

#RemoteFixDisk
Write-Host 'You can now rdp/ssh to the recovery vm to fix the disk.' -ForegroundColor Yellow
Write-Host 'Press any key when done to recreate the target vm' -ForegroundColor Red
Read-Host

RemoveVM $rgName $Global:RVM.Name

RecreateVm $rgName $Global:RVM.Name `
           $Global:RVM.HardwareProfile.VmSize `
           $Global:RVM.NetworkInterfaceIDs[0] `
           $Global:RVM.Location `           $Global:RVM.StorageProfile.OSDisk.Vhd.Uri



