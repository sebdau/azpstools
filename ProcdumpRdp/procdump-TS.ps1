$svcNames = @("termservice","lsm")
$procNames = @("services")

$workingFolder = "c:\procdump-TS\"
$pdZip = "Procdump.zip"

md $workingFolder
cd $workingFolder
$source = "https://download.sysinternals.com/files/"+$pdZip
$pdZipDest = $workingFolder+$pdZip


Invoke-WebRequest $source -OutFile $pdZipDest


Add-Type -assembly “system.io.compression.filesystem”
[io.compression.zipfile]::ExtractToDirectory($pdZipDest, $workingFolder)


$procIds = gwmi Win32_Service |where name -In $svcNames | where State -EQ Running | select -ExpandProperty ProcessId
$procIds += Get-Process | where name -In $procNames | select -ExpandProperty Id


foreach ( $procId in $procIds ) 
{    
    .\procdump.exe -accepteula -o -ma  $procId    
}


