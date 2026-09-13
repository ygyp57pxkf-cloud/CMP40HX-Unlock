@echo -off
# Keep the exact existing EFI image and path that previously unlocked this card.
if not exist %homefilesystem%\EFI\40HX-Auto\40HX-AUTO.tag then
  echo Wrong ESP marker. Returning to firmware.
  exit
endif
echo Same-EFI automatic initialization trial > %homefilesystem%\EFI\40HX-Auto\preboot.log
date >> %homefilesystem%\EFI\40HX-Auto\preboot.log
time >> %homefilesystem%\EFI\40HX-Auto\preboot.log
dmpstore BootCurrent > %homefilesystem%\EFI\40HX-Auto\boot-current.txt
pci 00 01 00 -i > %homefilesystem%\EFI\40HX-Auto\pci-root-before.txt
pci 01 00 00 -i > %homefilesystem%\EFI\40HX-Auto\pci-gpu-before.txt
if exist %homefilesystem%\EFI\40HX-Auto\connect.enabled then
  echo Connecting loaded UEFI drivers recursively >> %homefilesystem%\EFI\40HX-Auto\preboot.log
  connect -r
  echo Connect return: %lasterror% >> %homefilesystem%\EFI\40HX-Auto\preboot.log
endif
echo Waiting 30 seconds before starting the existing 40HX EFI...
echo Delay start: >> %homefilesystem%\EFI\40HX-Auto\preboot.log
time >> %homefilesystem%\EFI\40HX-Auto\preboot.log
stall 30000000
echo Delay end: >> %homefilesystem%\EFI\40HX-Auto\preboot.log
time >> %homefilesystem%\EFI\40HX-Auto\preboot.log
pci 00 01 00 -i > %homefilesystem%\EFI\40HX-Auto\pci-root-after.txt
pci 01 00 00 -i > %homefilesystem%\EFI\40HX-Auto\pci-gpu-after.txt
if exist %homefilesystem%\EFI\40HX\40HXUNLK.EFI then
  echo Starting existing EFI/40HX/40HXUNLK.EFI >> %homefilesystem%\EFI\40HX-Auto\preboot.log
  %homefilesystem%\EFI\40HX\40HXUNLK.EFI
endif
echo Unlock returned; starting Windows directly >> %homefilesystem%\EFI\40HX-Auto\preboot.log
if exist %homefilesystem%\EFI\Microsoft\Boot\bootmgfw.efi then
  %homefilesystem%\EFI\Microsoft\Boot\bootmgfw.efi
endif
exit
