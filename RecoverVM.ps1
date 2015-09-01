Param(
[Parameter(Mandatory=$true)][string]$SubscriptionId ,
[Parameter(Mandatory=$true)][string]$StorageAccountName ,
[Parameter(Mandatory=$true)][string]$ServiceName ,
[Parameter(Mandatory=$true)][string]$VMName , 
[string]$VMExportPath = $env:TEMP + '\' + $ServiceName + '_'  + $VMName + '.xml',
[string]$RecoveryAdmin = 'recoveryAdmin',
[string]$RecoveryPW = 'LetMeInNow123'
)
$IsWindows 
#todo: debug disk attachement

function RecoverVM ()
{
    $RecoveryVMName = 'RC' + $(get-date -f yyMMddHHmm)    

    #get defect vm object and export cfg to disk (temp)
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $VMName
    $vm | Export-AzureVM -Path $VMExportPath
    Write-Host 'Original VM Configuration written to ' $VMExportPath -ForegroundColor Yellow

    Write-host 'Creating VM (may take a few minutes)'

    if ( $vm.VM.OSVirtualHardDisk.OS -eq 'Windows' )
    {
        $RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Windows Server 2012 R2 Datacenter'  | sort PublishedDate -Descending | select  -First 1
        $recoveryVM = New-AzureQuickVM -Windows -WaitForBoot -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -AdminUsername $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName -EnableWinRMHttp
    }
    else
    {
        $RecoveryImage =  Get-AzureVMImage |where ImageFamily -eq 'Ubuntu Server 14.04 LTS'  | sort PublishedDate -Descending | select  -First 1
        $recoveryVM = New-AzureQuickVM -Windows $false -WaitForBoot -ServiceName $ServiceName -Name $RecoveryVMName -InstanceSize $vm.InstanceSize -AdminUsername $RecoveryAdmin -Password $RecoveryPW -ImageName $RecoveryImage.ImageName -EnableWinRMHttp
    }
    Write-Host 'Recovery VM' $RecoveryVMName 'was created with credentials' $RecoveryAdmin $RecoveryPW 

    Write-host 'Removing faulty vm and attaching its os disk as data disk to recovery vm'
    #create new recovery in size of the defect vm (will create premium storage vm if needed)
    #once the recovery vm has booted in the same cloud service (to prevent VIP loss) we get rid of the defect vm (but keep disks)
    Remove-AzureVm -ServiceName $ServiceName -Name $VMName 

    #now we need to wait for a few secs until the os disk was released
    Start-Sleep -Seconds 120 | Out-Null

    #than we try to add the 
    $recoveryVM = Get-AzureVM -ServiceName $ServiceName -Name $RecoveryVMName
    $recoveryVM | Add-AzureDataDisk -Import -DiskName $vm.VM.OSVirtualHardDisk.DiskName  -LUN 0 | Update-AzureVM 
        

    return $vm.VM.OSVirtualHardDisk.DiskName
}

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

function FixDisk()
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

function RecreateVM([Parameter(Mandatory=$true)][string] $OSDiskName, [bool] $DeleteAttachedVM)
{
    
    #default values only used when vm export path can not be imported as vm
    $VMSize = 'Standard_DS2' 
    $PublicRdpPort = 3389
    $SubNetNames = '' #"PubSubnet","PrivSubnet" #leave empty if not required
    $DataDiskNames = $null #'vm-disk-data-1'. 'vm-disk-data-1' #leave empty if not required
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

        if ( Test-Path -Path $VMExportPath  )  
        {
            $vm = Import-AzureVM   -Path $VMExportPath    
        }
        else
        {
          throw 'no vm export found ... using defaults'   
        }

    }
    catch
    {

        #prepare the 
        $vm = New-AzureVMConfig -Name $VMName -InstanceSize $VMSize -DiskName $OSDiskName

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

    New-AzureVM -ServiceName $ServiceName -VMs $vm -Location $location -WaitForBoot
    if ( $attachedVm )
    {
        if ( $DeleteAttachedVM)
        {
            Remove-AzureVM -ServiceName $attachedVm.ServiceName -Name $attachedVm.Name
        }
    }
}


#set subscription and premium storage account where os disk is 
Set-AzureSubscription -SubscriptionId $SubscriptionId -CurrentStorageAccountName $StorageAccountName 
Select-AzureSubscription -SubscriptionId $SubscriptionId


Do 
{
    Write-Host 'Azure VM Recovery - choose an option!'
    Write-Host '1 - Attach a faulty OS disk to a recovery VM (will delete the faulty VM but keep the disks)'
    Write-Host '2 - Run well known VHD recovery operations on the recovery VM (step 1) such as ckdisk'
    Write-Host '3 - Recreate the faulty VM using the OS disk'
    Write-Host '0 - EXIT (CTRL+C)'
    $Option = Read-Host
    $osDiskName = 'sebdauvs15RTM-RC1509011502-0-201509011308130580'
    switch ($Option)
    {
        '1' { $osDiskName = RecoverVM }
        '2' { FixDisk }
        '3' {
            if ( ! $osDiskName )
                {
                    Write-Host 'Specify the os disk name>'
                    $osDiskName = Read-Host 
                } 
            RecreateVM -OSDiskName $osDiskName 
        }
    }    
    
} While ($Option -ne '0')




