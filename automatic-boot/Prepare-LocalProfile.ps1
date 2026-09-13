[CmdletBinding()]
param(
 [string]$ShellVariable='Boot0002',
 [string]$WindowsVariable='Boot0000',
 [string]$LegacyVariable='Boot0001',
 [string]$OutputDirectory=$PSScriptRoot
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Manage-TraceLoader.ps1') -LibraryOnly
. (Join-Path $PSScriptRoot 'FirmwareVariables.ps1')
$profileFile=Join-Path $OutputDirectory 'profile.local.json'
$configFile=Join-Path $OutputDirectory 'diagnostic-loader\config.conf'
if((Test-Path -LiteralPath $profileFile) -or (Test-Path -LiteralPath $configFile)){throw 'Local profile/config already exists; refusing overwrite'}
foreach($name in @($ShellVariable,$WindowsVariable,$LegacyVariable)){if($name -notmatch '^Boot[0-9A-F]{4}$'){throw 'Use a BootNNNN variable name'} }
if(@(@($ShellVariable,$WindowsVariable,$LegacyVariable)|Select-Object -Unique).Count -ne 3){throw 'Select three distinct entries'}
$shell=Get-OptionLayout (Read-Variable $ShellVariable).Bytes
$win=Get-OptionLayout (Read-Variable $WindowsVariable).Bytes
$legacy=Get-OptionLayout (Read-Variable $LegacyVariable).Bytes
if($shell.Path -ine '\EFI\40HX-Auto\shellx64.efi' -or $win.Path -ine '\EFI\Microsoft\Boot\bootmgfw.efi' -or $legacy.Path -ine '\EFI\40HX\40HXUNLK.EFI'){throw 'Selected entry paths do not match the documented existing chain'}
if($shell.Guid -ne $win.Guid -or $shell.Guid -ne $legacy.Guid){throw 'Boot entries must point to the same verified ESP'}
$order=Read-Variable 'BootOrder';[int[]]$ids=@();for($i=0;$i -lt $order.Bytes.Length;$i+=2){$ids+=[BitConverter]::ToUInt16($order.Bytes,$i)}
foreach($name in @($ShellVariable,$WindowsVariable,$LegacyVariable)){if([Convert]::ToInt32($name.Substring(4),16) -notin $ids){throw 'Selected entry is not in current BootOrder'}}
$mounted=$false
try {
 $used=@(Get-Volume|Where-Object DriveLetter|ForEach-Object {$_.DriveLetter.ToString()})
 $letter=[string]([char[]](84..90)|Where-Object {[string]$_ -notin $used -and !(Test-Path ([string]$_+':\'))}|Select-Object -First 1)
 if(!$letter){throw 'No free mount letter'}
 & mountvol.exe ($letter+':') /S|Out-Null;if($LASTEXITCODE -ne 0){throw 'ESP mount failed'};$mounted=$true
 $esp=$letter+':\';$volume=Get-Volume -FilePath $esp
 $partitions=@(Get-Partition|Where-Object {$_.AccessPaths -contains $volume.UniqueId})
 if($partitions.Count -ne 1 -or [guid]$partitions[0].Guid -ne $win.Guid){throw 'Mounted ESP does not match selected entries'}
 $files=foreach($path in @('EFI\Microsoft\Boot\bootmgfw.efi','EFI\Boot\bootx64.efi','EFI\40HX\40HXUNLK.EFI','EFI\40HX-Auto\shellx64.efi','EFI\40HX-Auto\startup.nsh')){[pscustomobject]@{Path=$path;SHA256=(Get-FileHash -LiteralPath (Join-Path $esp $path)).Hash}}
 New-Item -ItemType Directory -Path (Split-Path $configFile) -Force|Out-Null
 $template=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'diagnostic-loader\config.template.conf') -Raw
 [IO.File]::WriteAllText($configFile,$template.Replace('@ESP_GUID@',$win.Guid.ToString()),[Text.UTF8Encoding]::new($false))
 [ordered]@{SchemaVersion=1;EspGuid=$win.Guid.ToString();ShellVariable=$ShellVariable;WindowsVariable=$WindowsVariable;LegacyVariable=$LegacyVariable;ShellDescription=$shell.Description;ExpectedBootOrder=$ids;ProtectedFiles=@($files);ConfigSHA256=(Get-FileHash -LiteralPath $configFile).Hash;Purpose='Local state capture, not proof that payloads or boot chain work'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $profileFile -Encoding UTF8
 Write-Output ('Local profile/config captured: '+$OutputDirectory+'. No ESP or firmware variable was written. Review payload provenance and Windows recovery before Apply.')
}finally{if($mounted){& mountvol.exe ($letter+':') /D|Out-Null}}
