[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ZigPath)
$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot 'bin';New-Item -ItemType Directory -Path $out -Force|Out-Null
$version=& $ZigPath version
if($version -ne '0.14.1'){throw 'Use the reviewed Zig 0.14.1 toolchain'}
& $ZigPath cc -target x86_64-windows-gnu -std=c11 -O1 -Wall -Wextra -Werror (Join-Path $PSScriptRoot 'src\test_guard.c') -o (Join-Path $out 'guard-tests.exe')
if($LASTEXITCODE -ne 0){throw 'Host test compilation failed'}
& (Join-Path $out 'guard-tests.exe')
if($LASTEXITCODE -ne 0){throw 'Fault-injection tests failed'}
& $ZigPath cc -target x86_64-windows-msvc -std=c11 -Os -ffreestanding -fshort-wchar -mno-red-zone -fno-stack-protector -fno-builtin -mno-stack-arg-probe -nostdlib -Wall -Wextra -Werror (Join-Path $PSScriptRoot 'src\guard.c') '-Wl,/subsystem:efi_application' -o (Join-Path $out 'guard_x64.efi')
if($LASTEXITCODE -ne 0){throw 'EFI compilation failed'}
$bytes=[IO.File]::ReadAllBytes((Join-Path $out 'guard_x64.efi'))
$pe=[BitConverter]::ToInt32($bytes,0x3c);$opt=$pe+24
if([BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664 -or [BitConverter]::ToUInt16($bytes,$opt) -ne 0x20b -or [BitConverter]::ToUInt16($bytes,$opt+68) -ne 10){throw 'Not an x64 EFI application'}
if([BitConverter]::ToUInt32($bytes,$opt+120) -ne 0 -or [BitConverter]::ToUInt32($bytes,$opt+124) -ne 0){throw 'EFI image must not import Windows DLLs'}
if([BitConverter]::ToUInt32($bytes,$opt+152) -eq 0){throw 'EFI image lacks relocations'}
Get-FileHash -LiteralPath (Join-Path $out 'guard_x64.efi')|Select-Object Path,Hash
