param([string]$Package=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Package 'Manage-TraceLoader.ps1') -LibraryOnly
$EspGuid=[guid]'11111111-2222-3333-4444-555555555555'
function Assert($Value,$Name){if(!$Value){throw "FAIL: $Name"};Write-Output "PASS: $Name"}
function Reject([scriptblock]$Body,$Name){$rejected=$false;try{& $Body}catch{$rejected=$true};Assert $rejected $Name}
# A synthetic GPT load option: no real NVRAM or device access in this suite.
[byte[]]$hd=New-Object byte[] 42;$hd[0]=4;$hd[1]=1;$hd[2]=42;$hd[40]=2;$hd[41]=2
[Array]::Copy(([guid]'11111111-2222-3333-4444-555555555555').ToByteArray(),0,$hd,24,16)
$path=[Text.Encoding]::Unicode.GetBytes('\EFI\40HX-AUTO\SHELLX64.EFI'+[char]0)
[byte[]]$device=$hd+[byte[]]@(4,4)+[BitConverter]::GetBytes([uint16]($path.Length+4))+$path+[byte[]]@(127,255,4,0)
[byte[]]$original=[BitConverter]::GetBytes([uint32]1)+[BitConverter]::GetBytes([uint16]$device.Length)+[Text.Encoding]::Unicode.GetBytes('40HX Auto Trial - SameEfiConnect'+[char]0)+$device+[Text.Encoding]::Unicode.GetBytes('old BCD data')
$result=New-TraceOption $original;$layout=Get-OptionLayout $result
Assert ($layout.OptionalLength -eq 0 -and $layout.Path -ceq '\EFI\40HX-Trace\trace_x64.efi') 'native trace path contains no Windows OptionalData'
Assert (Test-EqualBytes $layout.Nodes[0] $hd) 'GPT partition and device addressing preserved'
Reject {New-TraceOption ([byte[]]@(1,2))} 'truncated input refused'
$bad=[byte[]]$original.Clone();$bad[4]=255;$bad[5]=255
Reject {New-TraceOption $bad} 'oversized path refused'
$oldGuid=$EspGuid;$EspGuid=[guid]::NewGuid()
Reject {New-TraceOption $original} 'different machine partition refused';$EspGuid=$oldGuid
Reject {ConvertTo-OrderBytes @(4,0,4)} 'duplicate order refused'
$script:fake=@{};$script:writes=0;$script:corrupt=$false
function Read-Variable([string]$Name){$script:fake[$Name]}
function Write-Variable([string]$Name,[byte[]]$Bytes,[uint32]$Attributes){$script:writes++;$script:fake[$Name]=[pscustomobject]@{Bytes=if($script:corrupt){[byte[]]@(255,255)}else{$Bytes};Attributes=$Attributes}}
Set-VerifiedVariable 'Boot0004' $null $result 7
Assert ($script:writes -eq 1) 'new absent slot creates once with verified read-back'
Reject {Set-VerifiedVariable 'Boot0004' $null $result 7} 'existing slot cannot be overwritten'
Assert ($script:writes -eq 1) 'conflict causes zero additional writes'
$script:fake['BootOrder']=[pscustomobject]@{Bytes=[byte[]]@(0,0,2,0,1,0);Attributes=7}
$before=[pscustomobject]@{Bytes=[byte[]]@(2,0,0,0,1,0);Attributes=7}
Reject {Set-VerifiedVariable 'BootOrder' $before (ConvertTo-OrderBytes @(4,0,2,1)) 7} 'concurrent BootOrder change refused'
$script:fake['BootOrder']=$before;$script:corrupt=$true
Reject {Set-VerifiedVariable 'BootOrder' $before (ConvertTo-OrderBytes @(4,0,2,1)) 7} 'firmware read-back mismatch cannot report success'
$script:corrupt=$false;$script:fake['BootOrder']=$before
Set-VerifiedVariable 'BootOrder' $before (ConvertTo-OrderBytes @(4,0,2,1)) 7
Assert (Test-EqualBytes $script:fake['BootOrder'].Bytes ([byte[]]@(4,0,0,0,2,0,1,0))) 'trace first, Windows second verified'
. (Join-Path $Package 'Collect-Evidence.ps1') -LibraryOnly
$testRoot=Join-Path $env:TEMP ('40hx-trace-test-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'EFI\nested') -Force|Out-Null
    foreach($file in @('26r13k2455.log','26r13m0011.log','unrelated.log','26r13l2455.log')){Set-Content -LiteralPath (Join-Path $testRoot ('EFI\'+$file)) -Value 'fixture'}
    Set-Content -LiteralPath (Join-Path $testRoot 'EFI\nested\26r13k1111.log') -Value 'fixture'
    $logs=@(Get-TraceLogCandidates $testRoot)
    Assert ($logs.Count -eq 2) 'log collector excludes unrelated and nested files'
}finally{
    $resolved=[IO.Path]::GetFullPath($testRoot);$parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike '40hx-trace-test-*'){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output 'Trace guard and log-selection tests passed; firmware execution is not covered.'
