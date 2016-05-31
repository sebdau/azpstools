# Overview
Occasionally Azure IaaS VMs fail on RDP connections due to server-side RDP issues. 
To have microsoft customer support investigate such complex issues it is often useful to investigate the process dump of the services involved.

# Current version supports
- download procdump
- unzip procdump
- get the process ids of relevant processes
- instruct procdump to pull full user mode dumps of processes by id and write them to local disk 
- The dumps are stored on your VMs OS disk: c:\procdump-TS\*.dmp

# Scenarios

##  When would you use the script?
You can reach your VM using the network (tcping) but RDP fails after a while,
Its not usefull to apply this script when the network causes issues.

# Execution guidance
The script must be executed with elevated previleges.

You can use the custom script exptension to invoke the script:

```PowerShell
get-azurevm -servicename YOURVMSERVICE -name YOURVM | Set-AzureVMCustomScriptExtension -FileUri 'https://raw.githubusercontent.com/sebdau/azpstools/master/ProcdumpRdp/procdump-TS.ps1' -Run 'procdump-TS.ps1' | Update-AzureVM 
```

To query the execution status you can use your VMs custom script extion view or use the below command:

```PowerShell
$vm = get-azurevm -servicename YOURVMSERVICE -name YOURVM
$vm.ResourceExtensionStatusList[1].ExtensionSettingStatus.SubStatusList.FormattedMessage 
```

The dumps are stored on your VMs OS disk: c:\procdump-TS\*.dmp

## Parameters or input
- NONE

# Supported Platforms / Dependencies
The VM running the recovery script must:
- be running Windows 2008 - 2012R2
- have PowerShell installed


