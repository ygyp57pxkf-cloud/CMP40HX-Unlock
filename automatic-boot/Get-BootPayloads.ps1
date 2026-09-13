[CmdletBinding()]
param([string]$ArchivePath='',[string]$ShellPath='')
$ErrorActionPreference='Stop'
$destination=Join-Path $PSScriptRoot 'payloads'
if(Test-Path -LiteralPath $destination){throw 'Payload directory exists; verify it instead of overwriting'}
$scratch=Join-Path $env:TEMP ('40hx-verified-payload-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
try {
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 if(!$ArchivePath){$ArchivePath=Join-Path $scratch 'upstream.zip';Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/PZH1gdmu/CMP40HX-Unlock/releases/download/3.1.2-win/40HXUnlock_v3.1.2_win.zip' -OutFile $ArchivePath}
 if((Get-FileHash -LiteralPath $ArchivePath).Hash -ne 'BDC5A57385D63135D05B04134C616AE05EABDC675409E8FB1162269899D60EAC'){throw 'Upstream archive hash mismatch'}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $archive=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath).Path)
 try{$entries=@($archive.Entries|Where-Object {$_.Name -ceq '40HXInstaller.exe'});if($entries.Count -ne 1){throw 'Expected exactly one installer'};$installer=Join-Path $scratch '40HXInstaller.exe';[IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],$installer,$false)}finally{$archive.Dispose()}
 if((Get-FileHash -LiteralPath $installer).Hash -ne '74B1265260F266F34853192A640E0D3547F147E0FBCF5280783E6D4F59D71F79'){throw 'Installer hash mismatch'}
 $bytes=[IO.File]::ReadAllBytes($installer);$efi=New-Object byte[] 586260
 [Array]::Copy($bytes,3396544,$efi,0,$efi.Length)
 $efiPath=Join-Path $scratch '40HXUNLK.EFI';[IO.File]::WriteAllBytes($efiPath,$efi)
 if((Get-FileHash -LiteralPath $efiPath).Hash -ne 'F0D7CA1EABAB01C4410459C078B84CF3B150DA5AFECCBD73965E03D9C2AE7230'){throw 'Embedded EFI hash mismatch'}
 if(!$ShellPath){$ShellPath=Join-Path $scratch 'shellx64.efi';Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/pbatard/UEFI-Shell/releases/download/26H1/shellx64.efi' -OutFile $ShellPath}
 if((Get-FileHash -LiteralPath $ShellPath).Hash -ne '4EA080DDD576117CD04F5C02D16712EA5D9249C0752214D8E4055E460D7B11E0'){throw 'Shell hash mismatch'}
 New-Item -ItemType Directory -Path $destination|Out-Null
 foreach($file in @($installer,$efiPath,$ShellPath)){Copy-Item -LiteralPath $file -Destination (Join-Path $destination ([IO.Path]::GetFileName($file)))}
 # Normalize the Shell filename when a verified offline source had a different name.
 if([IO.Path]::GetFileName($ShellPath) -cne 'shellx64.efi'){Copy-Item -LiteralPath $ShellPath -Destination (Join-Path $destination 'shellx64.efi')}
 Write-Output 'Verified original installer, its embedded EFI, and EDK2 Shell prepared locally. Nothing was executed or installed.'
} finally {
 $resolved=[IO.Path]::GetFullPath($scratch);$parent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
 if(!$resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike '40hx-verified-payload-*'){throw 'Unsafe temporary cleanup path'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
