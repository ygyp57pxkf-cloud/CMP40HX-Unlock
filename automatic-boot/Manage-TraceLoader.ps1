[CmdletBinding()]
param(
    [ValidateSet('Inspect','Apply','Disable')][string]$Action='Inspect',
    [string]$Root='C:\ProgramData\40HX-Automation\TraceLoader',
    [string]$ProfilePath=(Join-Path $PSScriptRoot 'profile.local.json'),
    [switch]$LibraryOnly
)
$ErrorActionPreference='Stop'
$EspGuid=[guid]::Empty
$ShellDescription='40HX Auto Trial - SameEfiConnect'
$TracePath='\EFI\40HX-Trace\trace_x64.efi'
$TraceHash='6E829EC28E06304DBB2D7A1235CE276E71C181D6EE433588C089F70AE6F43F5D'

function Test-EqualBytes($A,$B) {
    if($null -eq $A -or $null -eq $B){return ($null -eq $A -and $null -eq $B)}
    return [Convert]::ToBase64String([byte[]]$A) -ceq [Convert]::ToBase64String([byte[]]$B)
}
function Get-OptionLayout([byte[]]$Bytes) {
    if($Bytes.Length -lt 12){throw 'Truncated EFI option'}
    $end=6
    while($end+1 -lt $Bytes.Length -and ($Bytes[$end] -ne 0 -or $Bytes[$end+1] -ne 0)){$end+=2}
    if($end+1 -ge $Bytes.Length){throw 'Missing description terminator'}
    $start=$end+2; $stop=$start+[BitConverter]::ToUInt16($Bytes,4)
    if($stop -gt $Bytes.Length){throw 'Truncated device path'}
    $nodes=@();$paths=@();$guids=@();$ended=$false
    for($p=$start;$p -lt $stop;){
        if($p+4 -gt $stop){throw 'Truncated node header'}
        $len=[BitConverter]::ToUInt16($Bytes,$p+2)
        if($len -lt 4 -or $p+$len -gt $stop){throw 'Invalid node length'}
        $node=[byte[]]$Bytes[$p..($p+$len-1)]
        if($node[0] -eq 4 -and $node[1] -eq 4){
            if($len -lt 6 -or $len%2 -ne 0 -or $node[$len-1] -ne 0 -or $node[$len-2] -ne 0){throw 'Invalid file path'}
            $paths+= [Text.Encoding]::Unicode.GetString($node,4,$len-4).TrimEnd([char]0)
        }
        if($node[0] -eq 4 -and $node[1] -eq 1){
            if($len -ne 42 -or $node[41] -ne 2){throw 'Expected GPT hard drive node'}
            $guids+= [guid]::new([byte[]]$node[24..39])
        }
        if($node[0] -eq 127){
            if($node[1] -ne 255 -or $len -ne 4 -or $p+$len -ne $stop){throw 'Unexpected end node or multiple instances'}
            $ended=$true
        }
        $nodes+= ,$node; $p+=$len
    }
    if(!$ended -or $paths.Count -ne 1 -or $guids.Count -ne 1){throw 'Expected one GPT partition and file path'}
    [pscustomobject]@{Description=[Text.Encoding]::Unicode.GetString($Bytes,6,$end-6);Path=$paths[0];Guid=$guids[0];Nodes=$nodes;OptionalLength=$Bytes.Length-$stop}
}
function New-TraceOption([byte[]]$Template) {
    $layout=Get-OptionLayout $Template
    if($layout.Guid -ne $EspGuid -or $layout.Path -ine '\EFI\40HX-AUTO\SHELLX64.EFI' -or $layout.Description -cne $ShellDescription -or ([BitConverter]::ToUInt32($Template,0) -band 1) -eq 0){throw 'Unexpected Shell template'}
    $pathBytes=[Text.Encoding]::Unicode.GetBytes($TracePath+[char]0)
    [byte[]]$device=@()
    foreach($node in $layout.Nodes){
        if($node[0] -eq 4 -and $node[1] -eq 4){$device+= [byte[]]@(4,4)+[BitConverter]::GetBytes([uint16]($pathBytes.Length+4))+$pathBytes}
        else{$device+=$node}
    }
    [byte[]]$description=[Text.Encoding]::Unicode.GetBytes('40HX Trace - Auto Shell'+[char]0)
    # Native EFI load option, deliberately no cloned Windows BCDOBJECT data.
    return ,([BitConverter]::GetBytes([uint32]1)+[BitConverter]::GetBytes([uint16]$device.Length)+$description+$device)
}
function ConvertTo-OrderBytes([int[]]$Order) {
    if(!$Order -or @($Order|Select-Object -Unique).Count -ne $Order.Count){throw 'Invalid or duplicate BootOrder'}
    [byte[]]$bytes=@();foreach($n in $Order){$bytes+=[BitConverter]::GetBytes([uint16]$n)};return ,$bytes
}
function Read-Variable([string]$Name){return [TraceFirmwareApi]::Read($Name)}
function Write-Variable([string]$Name,[byte[]]$Bytes,[uint32]$Attributes){[TraceFirmwareApi]::Write($Name,$Bytes,$Attributes)}
function Set-VerifiedVariable([string]$Name,$Expected,[byte[]]$Desired,[uint32]$Attributes) {
    $now=Read-Variable $Name
    if($null -eq $Expected){if($null -ne $now){throw "$Name already exists"}}
    elseif($null -eq $now -or $now.Attributes -ne $Expected.Attributes -or !(Test-EqualBytes $now.Bytes $Expected.Bytes)){throw "$Name changed independently"}
    Write-Variable $Name $Desired $Attributes
    $after=Read-Variable $Name
    if($null -eq $after -or $after.Attributes -ne $Attributes -or !(Test-EqualBytes $after.Bytes $Desired)){throw "$Name read-back mismatch; do not reboot before recovery"}
}
if($LibraryOnly){return}
if(!(Test-Path -LiteralPath $ProfilePath)){throw 'Create a local profile with Prepare-LocalProfile.ps1 first; no firmware changes made'}
$profile=Get-Content -LiteralPath $ProfilePath -Raw|ConvertFrom-Json
$EspGuid=[guid]$profile.EspGuid
if($EspGuid -eq [guid]::Empty){throw 'Empty ESP GUID is a template, not an installable profile'}
$ShellDescription=[string]$profile.ShellDescription
foreach($field in @('ShellVariable','WindowsVariable','LegacyVariable')){if($profile.$field -notmatch '^Boot[0-9A-F]{4}$'){throw 'Invalid local boot variable'}}
$ShellNumber=[Convert]::ToInt32($profile.ShellVariable.Substring(4),16)
$WindowsNumber=[Convert]::ToInt32($profile.WindowsVariable.Substring(4),16)
$LegacyNumber=[Convert]::ToInt32($profile.LegacyVariable.Substring(4),16)
if(@($ShellNumber,$WindowsNumber,$LegacyNumber|Select-Object -Unique).Count -ne 3){throw 'Boot variables must be distinct'}
if($profile.ConfigSHA256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Invalid config digest'}
. (Join-Path $PSScriptRoot 'FirmwareVariables.ps1')
$order=Read-Variable 'BootOrder'
$shell=Read-Variable $profile.ShellVariable
$windows=Read-Variable $profile.WindowsVariable
$legacy=Read-Variable $profile.LegacyVariable
$next=Read-Variable 'BootNext'
$statePath=Join-Path $Root 'state.json'
if($Action -eq 'Inspect'){
    $current=Read-Variable 'BootCurrent'
    [pscustomobject]@{Time=(Get-Date).ToString('o');BootCurrent=if($current){[BitConverter]::ToString($current.Bytes)}else{$null};BootOrder=[BitConverter]::ToString($order.Bytes);BootNextPresent=($null -ne $next);Shell=Get-OptionLayout $shell.Bytes|Select-Object Description,Path,Guid;Windows=Get-OptionLayout $windows.Bytes|Select-Object Description,Path,Guid}|ConvertTo-Json -Depth 4
    if(Test-Path -LiteralPath $statePath){Get-Content -LiteralPath $statePath -Raw};exit 0
}
if($next){throw 'BootNext exists; inspect before changing persistent order'}
$winLayout=Get-OptionLayout $windows.Bytes
if($winLayout.Guid -ne $EspGuid -or $winLayout.Path -ine '\EFI\Microsoft\Boot\bootmgfw.efi'){throw 'Windows recovery entry differs from expected ESP/path'}
if($Action -eq 'Disable'){
    $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
    $entry=Read-Variable $state.Variable
    if(!(Test-EqualBytes $entry.Bytes ([Convert]::FromBase64String($state.EntryBase64)))){throw 'Trace entry changed; inspect before recovery'}
    [int[]]$ids=@();for($i=0;$i -lt $order.Bytes.Length;$i+=2){$ids+=[BitConverter]::ToUInt16($order.Bytes,$i)}
    $safe=ConvertTo-OrderBytes (@($WindowsNumber)+@($ids|Where-Object {$_ -ne $WindowsNumber -and $_ -ne [int]$state.Number}))
    Set-VerifiedVariable 'BootOrder' $order $safe $order.Attributes
    $state.Status='Disabled; Windows first; trace files and entry retained for investigation'
    $state|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Output $state.Status;exit 0
}
if(Test-Path -LiteralPath $Root){throw 'Trace state directory already exists; inspect, do not restage blindly'}
if(Confirm-SecureBootUEFI){throw 'Secure Boot enabled; no changes made'}
if([int](Get-BitLockerVolume -MountPoint C:).ProtectionStatus -ne 0){throw 'BitLocker protection active; no changes made'}
if(!(Test-EqualBytes $order.Bytes (ConvertTo-OrderBytes ([int[]]$profile.ExpectedBootOrder)))){throw 'BootOrder differs from captured local profile'}
$legacyLayout=Get-OptionLayout $legacy.Bytes
if($legacyLayout.Guid -ne $EspGuid -or $legacyLayout.Path -ine '\EFI\40HX\40HXUNLK.EFI'){throw 'Legacy entry changed'}
$entryBytes=New-TraceOption $shell.Bytes
$slot=$null;foreach($candidate in 4..63){if($null -eq (Read-Variable ('Boot{0:X4}' -f $candidate))){$slot=$candidate;break}}
if($null -eq $slot){throw 'No unused native slot found'}
$name='Boot{0:X4}' -f $slot
$desiredOrder=ConvertTo-OrderBytes (@($slot,$WindowsNumber)+@($profile.ExpectedBootOrder|Where-Object {$_ -ne $WindowsNumber}))
$payload=Join-Path $PSScriptRoot 'diagnostic-loader'
if((Get-FileHash -LiteralPath (Join-Path $payload 'trace_x64.efi')).Hash -ne $TraceHash){throw 'Unexpected trace binary'}
if((Get-FileHash -LiteralPath (Join-Path $payload 'config.conf')).Hash -ne $profile.ConfigSHA256){throw 'Configuration differs from reviewed digest'}
$mounted=$false
try {
    $used=@(Get-Volume|Where-Object DriveLetter|ForEach-Object {$_.DriveLetter.ToString()})
    $letter=[string]([char[]](84..90)|Where-Object {[string]$_ -notin $used -and !(Test-Path ([string]$_+':\'))}|Select-Object -First 1)
    if(!$letter){throw 'No free mount letter'}
    & mountvol.exe ($letter+':') /S|Out-Null;if($LASTEXITCODE -ne 0){throw 'ESP mount failed'};$mounted=$true
    $esp=$letter+':\';$volume=Get-Volume -FilePath $esp
    $partitions=@(Get-Partition|Where-Object {$_.AccessPaths -contains $volume.UniqueId})
    if($partitions.Count -ne 1 -or [guid]$partitions[0].Guid -ne $EspGuid){throw 'Mounted ESP GUID mismatch'}
    $destination=Join-Path $esp 'EFI\40HX-Trace'
    if(Test-Path -LiteralPath $destination){throw 'Trace ESP directory already exists'}
    if($volume.SizeRemaining -lt 20MB){throw 'Less than 20 MiB free on ESP'}
    $protected=@($profile.ProtectedFiles|ForEach-Object {$_.Path})
    $hashes=@($profile.ProtectedFiles|ForEach-Object {$_.SHA256})
    if($protected.Count -ne 5){throw 'Expected five protected payloads'}
    for($i=0;$i -lt $protected.Count;$i++){if((Get-FileHash -LiteralPath (Join-Path $esp $protected[$i])).Hash -ne $hashes[$i]){throw ('Baseline payload changed: '+$protected[$i])}}
    New-Item -ItemType Directory -Path $Root|Out-Null
    & icacls.exe $Root /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'|Out-Null;if($LASTEXITCODE -ne 0){throw 'Cannot protect runtime directory'}
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $Root 'Manage-TraceLoader.ps1')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'FirmwareVariables.ps1') -Destination (Join-Path $Root 'FirmwareVariables.ps1')
    Copy-Item -LiteralPath $ProfilePath -Destination (Join-Path $Root 'profile.local.json')
    & bcdedit.exe /export (Join-Path $Root 'BCD.before')|Out-Null;if($LASTEXITCODE -ne 0){throw 'BCD backup failed'}
    $snapshot=@();foreach($var in @('BootOrder',$profile.WindowsVariable,$profile.LegacyVariable,$profile.ShellVariable)){$value=Read-Variable $var;$snapshot+=[pscustomobject]@{Name=$var;Attributes=$value.Attributes;Base64=[Convert]::ToBase64String($value.Bytes)}}
    $snapshot|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $Root 'variables.before.json') -Encoding UTF8
    $state=[pscustomobject]@{CreatedAt=(Get-Date).ToString('o');Status='Prepared; not activated';Variable=$name;Number=$slot;EntryBase64=[Convert]::ToBase64String($entryBytes);OrderBeforeBase64=[Convert]::ToBase64String($order.Bytes);OrderTrialBase64=[Convert]::ToBase64String($desiredOrder);RebootIssued=$false;HardwareGoalPassed=$false}
    $state|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
    New-Item -ItemType Directory -Path $destination|Out-Null
    foreach($file in @('trace_x64.efi','config.conf','LICENSE.txt','INFO.txt')){Copy-Item -LiteralPath (Join-Path $payload $file) -Destination (Join-Path $destination $file);if((Get-FileHash -LiteralPath (Join-Path $payload $file)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $destination $file)).Hash){throw "ESP read-back differs: $file"}}
    foreach($pair in @(@($profile.WindowsVariable,$windows),@($profile.LegacyVariable,$legacy),@($profile.ShellVariable,$shell))){$current=Read-Variable $pair[0];if($current.Attributes -ne $pair[1].Attributes -or !(Test-EqualBytes $current.Bytes $pair[1].Bytes)){throw 'Existing entry changed during staging'}}
    if(Read-Variable 'BootNext'){throw 'BootNext appeared during staging'}
    Set-VerifiedVariable $name $null $entryBytes 7
    Set-VerifiedVariable 'BootOrder' $order $desiredOrder $order.Attributes
    for($i=0;$i -lt $protected.Count;$i++){if((Get-FileHash -LiteralPath (Join-Path $esp $protected[$i])).Hash -ne $hashes[$i]){throw 'Protected payload hash changed'}}
    $state.Status='Deployed and read-back verified; automatic boot and log production pending'
    $state|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
    $state|ConvertTo-Json
} finally {if($mounted){& mountvol.exe ($letter+':') /D|Out-Null}}
