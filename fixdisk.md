# Purpose / overview
Occationally Azure IaaS VMs may not start because there is something wrong with the OS disk so that it does not boot up correctly.
In such cases it is a common practice to:

- Delete the VM (but keep the disks)
- Attach the disk(s) to another bootable VM as a Data Disk
- Run the script https://github.com/sedau/azpstools/blob/master/TS_RecoveryWorker2.ps1 as an elevated administrator from the recovery VM
- Detach the disk and recreate the original VM based on the recovered disk

> the full details are explained in this blog post:
> https://blogs.msdn.microsoft.com/mast/2014/11/20/recover-azure-vm-by-attaching-os-disk-to-another-azure-vm/

# Current version supports
- run chkdsk do fix file system corruptions
- run sfc to replace invalid system files
- reconfigure boot configuration (bcdedit) (supports multi partion layouts)
- collect a list of invalid system files that were not recovered and writes it to c:\WindowsAzure\Logs\ChkDsk-SysReg.log on the recovery VM

# Scenarios

##  when would you use the script?
- Azure Windows VM does not boot (VM screen shot does not show login screen but boot issue)

# Any execution guidance needed 
The script must be executed from a windows vm that has a data disk attached) with elevated previleges 

## Parameters or input
- NONE

# Support platforms / dependencies  (for example)

- Needs PowerShell
- Needs a particular version of Windows (2008 - 2012R2)

