[CmdletBinding()]
param([string]$ArchivePath='')
$ErrorActionPreference='Stop'
$url='https://github.com/RefindPlusRepo/RefindPlus/releases/download/v0.14.2.AE/x64-RefindPlus_001402-AE.zip'
$zipHash='D60E6157FA1D7BDB7E14FFAFA77B2CD8F99C5DED8B08B1732D6B5F4913D4EE89'
$efiHash='6E829EC28E06304DBB2D7A1235CE276E71C181D6EE433588C089F70AE6F43F5D'
$destination=Join-Path $PSScriptRoot 'diagnostic-loader\trace_x64.efi'
if(Test-Path -LiteralPath $destination){
    if((Get-FileHash -LiteralPath $destination).Hash -ne $efiHash){throw 'Existing trace payload has unexpected hash; refusing overwrite'}
    Write-Output 'Pinned DEBUG payload already present; no firmware changes.';exit 0
}
$scratch=Join-Path $env:TEMP ('40hx-payload-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch|Out-Null
try {
    if(!$ArchivePath){
        $ArchivePath=Join-Path $scratch 'release.zip'
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $ArchivePath
    }
    if((Get-FileHash -LiteralPath $ArchivePath).Hash -ne $zipHash){throw 'Release archive SHA256 mismatch'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath).Path)
    try {
        # Extract just the reviewed file, never arbitrary paths or optional drivers.
        $entries=@($archive.Entries|Where-Object {$_.FullName -ceq 'x64-RefindPlus_001402-AE/x64_RefindPlus_DBG.efi'})
        if($entries.Count -ne 1){throw 'Expected one pinned DEBUG archive entry'}
        $candidate=Join-Path $scratch 'trace_x64.efi'
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],$candidate,$false)
    } finally {$archive.Dispose()}
    if((Get-FileHash -LiteralPath $candidate).Hash -ne $efiHash){throw 'DEBUG payload SHA256 mismatch'}
    Copy-Item -LiteralPath $candidate -Destination $destination
    if((Get-FileHash -LiteralPath $destination).Hash -ne $efiHash){throw 'Copied payload differs'}
    Write-Output 'Pinned DEBUG payload prepared locally. No ESP, NVRAM, driver or reboot operation performed.'
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch);$tempParent=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($tempParent,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike '40hx-payload-*'){throw 'Unsafe temporary cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
