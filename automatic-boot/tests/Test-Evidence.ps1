$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
foreach($file in Get-ChildItem -LiteralPath $package -Filter '*.ps1' -Recurse){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors);if($errors){throw ($errors|Out-String)}}
. (Join-Path $package 'Collect-Evidence.ps1') -LibraryOnly
function Check($Value,$Name){if(!$Value){throw ('FAIL: '+$Name)};Write-Output ('PASS: '+$Name)}
$boot=(Get-Date).AddMinutes(-10)
$stamp=$boot.AddMinutes(1).ToString('yyyy-MM-dd HH:mm:ss')
$diag="$stamp`n 算力 : 满血 (SS0=0x88888888 SS1=0x00000008)`n LNKSTA =0x00001102"
$success='[v55 final]: PLM=0xffffff8f SS0=0x88888888 SS1=0x00000008'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) $success $diag
Check $r.DualUnlockVerified 'same-boot EFI and Windows raw measurements establish dual unlock'
$r=Get-EvidenceVerdict $boot $boot.AddDays(-1) $success $diag
Check (!$r.DualUnlockVerified -and $r.Efi -eq 'StaleOrUncorrelated') 'yesterday EFI success cannot establish this boot'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) $success $diag.Replace($stamp,$boot.AddHours(-1).ToString('yyyy-MM-dd HH:mm:ss'))
Check ($r.WindowsCompute -eq 'DiagnosticFromAnotherBoot') 'copied old Windows report remains old by embedded timestamp'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) $success ''
Check (!$r.DualUnlockVerified -and $r.WindowsCompute -eq 'NotMeasuredInWindows') 'EFI success alone is insufficient'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) ($success+"`n[v55 final]: SS0=0x00000000") $diag
Check ($r.Efi -eq 'FreshBooterFailure') 'last final result wins over intermediate success'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) 'SEC2 unlocked; probe SS0=0x88888888' $diag
Check ($r.Efi -eq 'FreshNoFinalResult') 'probe or SEC2 flag is not final compute success'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) $success $diag.Replace('0x00001102','0x00001101')
Check (!$r.DualUnlockVerified -and $r.PcieRaw -eq 'Gen1x16') 'raw Gen1 does not pass dual-unlock acceptance'
$r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) $success $diag.Replace('0x88888888','0x02300004')
Check (!$r.GspOverwriteProven -and !$r.DualUnlockVerified) 'EFI-Windows mismatch does not prove GSP causation'
$fixture=Join-Path $env:TEMP ('40hx-diagnostic-'+[guid]::NewGuid().ToString('N')+'.txt')
try{
 [IO.File]::WriteAllText($fixture,$diag,[Text.UTF8Encoding]::new($false))
 $r=Get-EvidenceVerdict $boot $boot.AddSeconds(-2) $success (Read-WindowsDiagnostic $fixture)
 Check $r.DualUnlockVerified 'real UTF-8 without BOM diagnostic survives PS5.1 file decoding'
}finally{Remove-Item -LiteralPath $fixture -Force}
Write-Output '9 evidence checks and PowerShell syntax checks passed.'
