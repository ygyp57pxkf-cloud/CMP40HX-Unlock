[CmdletBinding()]
param([string]$OutputDirectory='', [string]$WindowsDiagnosticPath='', [ValidateRange(0,120)][int]$SettleSeconds=60, [switch]$LibraryOnly)
$ErrorActionPreference='Stop'
function Get-TraceLogCandidates([string]$Esp) {
 @(Get-ChildItem -LiteralPath (Join-Path $Esp 'EFI') -File -Filter '*.log'|Where-Object {$_.Name -match '^\d{2}[bcfhjknprtvx]\d{2}[a-kmnp-z]\d{4}\.log$'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 6)
}
function Read-WindowsDiagnostic([string]$Path) {
    # Upstream reports are UTF-8 without BOM; PS5.1 otherwise decodes them as ANSI.
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}
function Get-EvidenceVerdict([datetime]$BootTime,[datetime]$EfiTime,[string]$EfiText,[string]$WindowsText) {
 $age=($BootTime.ToUniversalTime()-$EfiTime.ToUniversalTime()).TotalSeconds
 $efi='StaleOrUncorrelated'
 if($age -ge -5 -and $age -le 180){
  $final=@([regex]::Matches($EfiText,'(?im)^\[v\d+ final\]:[^\r\n]*'))
  if($final.Count){
   $line=$final[-1].Value
   if($line -match 'SS0=0x88888888\b' -and $line -match 'SS1=0x00000008\b'){$efi='FreshUnlocked'}
   elseif($line -match 'SS0=0x00000000\b'){$efi='FreshBooterFailure'}else{$efi='FreshOtherResult'}
  }else{$efi='FreshNoFinalResult'}
 }
 $compute='NotMeasuredInWindows';$pcie='NotMeasuredFromRawRegisters'
 $stamp=[regex]::Match($WindowsText,'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
 if($stamp.Success){
  $time=[datetime]::ParseExact($stamp.Value,'yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
  if($time -ge $BootTime -and $time -le (Get-Date).AddMinutes(2)){
   $status=[regex]::Match($WindowsText,'(?m)^\s*算力\s*:([^\r\n]*)')
   if($status.Success){if($status.Value -match 'SS0=0x88888888\b' -and $status.Value -match 'SS1=0x00000008\b'){$compute='Unlocked'}else{$compute='LockedOrUnexpected'}}
   $link=[regex]::Match($WindowsText,'(?im)^\s*LNKSTA\s*=\s*0x([0-9a-f]+)')
   if($link.Success){$raw=[Convert]::ToUInt32($link.Groups[1].Value,16);$gen=$raw -band 15;$lanes=($raw -shr 4) -band 63;$pcie='Gen'+$gen+'x'+$lanes}
  }else{$compute='DiagnosticFromAnotherBoot'}
 }
 [pscustomobject]@{Efi=$efi;WindowsCompute=$compute;PcieRaw=$pcie;DualUnlockVerified=($efi -eq 'FreshUnlocked' -and $compute -eq 'Unlocked' -and $pcie -eq 'Gen2x16');GspOverwriteProven=$false}
}
if($LibraryOnly){return}
function Invoke-SmiRead {
 $p=New-Object Diagnostics.Process
 $p.StartInfo=New-Object Diagnostics.ProcessStartInfo
 $p.StartInfo.FileName="$env:SystemRoot\System32\nvidia-smi.exe"
 $p.StartInfo.Arguments='--query-gpu=name,driver_version,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader'
 $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
 $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
 if(!$p.Start()){throw 'Could not start read-only nvidia-smi query'}
 $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
 if(!$p.WaitForExit(15000)){
  # Only stop this collector's own read-only query, never an installer or driver.
  try{$p.Kill()}catch{};$p.Dispose()
  return [pscustomobject]@{ExitCode=71;Text='Read-only nvidia-smi query timed out'}
 }
 $r=[pscustomobject]@{ExitCode=$p.ExitCode;Text=($out.Result+$err.Result).Trim()};$p.Dispose();return $r
}
if(!$OutputDirectory){$OutputDirectory=Join-Path $env:LOCALAPPDATA ('CMP40HX-AutoBoot\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Use a new output directory to preserve prior evidence'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
. (Join-Path $PSScriptRoot 'FirmwareVariables.ps1')
$vars=[ordered]@{};foreach($name in @('BootCurrent','BootOrder','BootNext')){$v=[TraceFirmwareApi]::Read($name);$vars[$name]=if($v){[BitConverter]::ToString($v.Bytes)}else{$null}}
$vars|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputDirectory 'firmware.json') -Encoding UTF8
$mounted=$false;$efiText='';$efiTime=[datetime]::MinValue;$meta=@()
try{
 $used=@(Get-Volume|Where-Object DriveLetter|ForEach-Object {$_.DriveLetter.ToString()})
 $letter=[string]([char[]](84..90)|Where-Object {[string]$_ -notin $used -and !(Test-Path ([string]$_+':\'))}|Select-Object -First 1)
 if(!$letter){throw 'No free ESP mount letter'}
 & mountvol.exe ($letter+':') /S|Out-Null;if($LASTEXITCODE -ne 0){throw 'ESP mount failed'};$mounted=$true;$esp=$letter+':\'
 $files=@();foreach($relative in @('40hx_log.txt','EFI\40HX-Auto\preboot.log','EFI\40HX-Auto\boot-current.txt','EFI\40HX-Auto\pci-root-before.txt','EFI\40HX-Auto\pci-root-after.txt','EFI\40HX-Auto\pci-gpu-before.txt','EFI\40HX-Auto\pci-gpu-after.txt')){$path=Join-Path $esp $relative;if(Test-Path -LiteralPath $path){$files+=Get-Item -LiteralPath $path}}
 $files+=Get-TraceLogCandidates $esp;$budget=16MB
 foreach($file in $files){$copy=$file.Length -le 4MB -and $file.Length -le $budget;$meta+=[pscustomobject]@{Name=$file.Name;LastWriteTimeUtc=$file.LastWriteTimeUtc.ToString('o');Length=$file.Length;Copied=$copy};if($copy){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $OutputDirectory $file.Name);$budget-=$file.Length}}
 $efiFile=Join-Path $esp '40hx_log.txt';if(Test-Path -LiteralPath $efiFile){$efiTime=(Get-Item -LiteralPath $efiFile).LastWriteTimeUtc;$efiText=Get-Content -LiteralPath $efiFile -Raw}
}finally{if($mounted){& mountvol.exe ($letter+':') /D|Out-Null}}
$meta|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $OutputDirectory 'efi-file-times.json') -Encoding UTF8
$samples=@();$deadline=(Get-Date).AddSeconds($SettleSeconds);$consecutive=0
do{
 $gpu=@(Get-CimInstance Win32_VideoController|Where-Object {$_.PNPDeviceID -match '^PCI\\VEN_10DE&DEV_1F0B&'})
 $smi=Invoke-SmiRead
 $exit=$smi.ExitCode;$code=if($gpu.Count -eq 1){[int]$gpu[0].ConfigManagerErrorCode}else{-1}
 $samples+=[pscustomobject]@{Time=(Get-Date).ToString('o');ProblemCode=$code;SmiExit=$exit;SmiText=$smi.Text}
 if($code -eq 0 -and $exit -eq 0){$consecutive++}else{$consecutive=0}
 if($consecutive -ge 2 -or (Get-Date) -ge $deadline){break};Start-Sleep -Seconds 5
}while($true)
$windowsText='';if($WindowsDiagnosticPath){$windowsText=Read-WindowsDiagnostic $WindowsDiagnosticPath;Copy-Item -LiteralPath $WindowsDiagnosticPath -Destination (Join-Path $OutputDirectory 'windows-diagnostic.txt')}
$verdict=Get-EvidenceVerdict $boot $efiTime $efiText $windowsText
$report=[ordered]@{BootTime=$boot.ToString('o');CapturedAt=(Get-Date).ToString('o');Mode='ReadOnly';GpuMutations=0;InitialTransient=($samples[0].SmiExit -ne 0 -and $consecutive -ge 2);DriverReadyObservedTwice=($consecutive -ge 2);Evidence=$verdict;Samples=$samples}
$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
$report|ConvertTo-Json -Depth 7
if($consecutive -lt 2){exit 70}
