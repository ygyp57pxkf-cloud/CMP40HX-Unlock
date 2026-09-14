#ifndef UEFI_MIN_H
#define UEFI_MIN_H
#include <stddef.h>
typedef unsigned char U8;
typedef unsigned short U16;
typedef unsigned int U32;
typedef unsigned long long U64;
typedef unsigned long long UINTN;
typedef U64 EFI_STATUS;
typedef void *EFI_HANDLE;
typedef U16 CHAR16;
#define EFIAPI __attribute__((ms_abi))
#define ERROR_BIT 0x8000000000000000ULL
#define EFI_ERROR(s) (((s) & ERROR_BIT) != 0)
#define EFI_SUCCESS 0ULL
#define EFI_LOAD_ERROR (ERROR_BIT | 1)
#define EFI_INVALID_PARAMETER (ERROR_BIT | 2)
#define EFI_UNSUPPORTED (ERROR_BIT | 3)
#define EFI_DEVICE_ERROR (ERROR_BIT | 7)
#define EFI_OUT_OF_RESOURCES (ERROR_BIT | 9)
#define EFI_ABORTED (ERROR_BIT | 21)
typedef struct {U32 a; U16 b,c; U8 d[8];} EFI_GUID;
typedef struct {U64 Signature; U32 Revision,HeaderSize,CRC32,Reserved;} EFI_TABLE_HEADER;
typedef struct {U8 Type,SubType; U16 Length;} DEVICE_PATH;
typedef struct {U16 Year; U8 Month,Day,Hour,Minute,Second,Pad1; U32 Nanosecond; short TimeZone; U8 Daylight,Pad2;} EFI_TIME;
typedef struct FILE_PROTOCOL FILE_PROTOCOL;
struct FILE_PROTOCOL {
 U64 Revision;
 EFI_STATUS(EFIAPI *Open)(FILE_PROTOCOL*,FILE_PROTOCOL**,CHAR16*,U64,U64);
 EFI_STATUS(EFIAPI *Close)(FILE_PROTOCOL*);
 void *Delete,*Read;
 EFI_STATUS(EFIAPI *Write)(FILE_PROTOCOL*,UINTN*,void*);
 void *GetPosition;
 EFI_STATUS(EFIAPI *SetPosition)(FILE_PROTOCOL*,U64);
 void *GetInfo,*SetInfo;
 EFI_STATUS(EFIAPI *Flush)(FILE_PROTOCOL*);
};
typedef struct {U64 Revision; EFI_STATUS(EFIAPI *OpenVolume)(void*,FILE_PROTOCOL**);} SIMPLE_FS;
typedef struct {
 U32 Revision; EFI_HANDLE ParentHandle; void *SystemTable; EFI_HANDLE DeviceHandle;
 DEVICE_PATH *FilePath; void *Reserved; U32 LoadOptionsSize; void *LoadOptions;
 void *ImageBase; U64 ImageSize; U32 ImageCodeType,ImageDataType; void *Unload;
} LOADED_IMAGE;
typedef struct {
 EFI_TABLE_HEADER Hdr;
 void *RaiseTPL,*RestoreTPL,*AllocatePages,*FreePages,*GetMemoryMap;
 EFI_STATUS(EFIAPI *AllocatePool)(U32,UINTN,void**);
 EFI_STATUS(EFIAPI *FreePool)(void*);
 void *CreateEvent,*SetTimer,*WaitForEvent,*SignalEvent,*CloseEvent,*CheckEvent;
 void *InstallProtocolInterface,*ReinstallProtocolInterface,*UninstallProtocolInterface;
 EFI_STATUS(EFIAPI *HandleProtocol)(EFI_HANDLE,EFI_GUID*,void**);
 void *Reserved,*RegisterProtocolNotify,*LocateHandle,*LocateDevicePath,*InstallConfigurationTable;
 EFI_STATUS(EFIAPI *LoadImage)(U8,EFI_HANDLE,DEVICE_PATH*,void*,UINTN,EFI_HANDLE*);
 EFI_STATUS(EFIAPI *StartImage)(EFI_HANDLE,UINTN*,CHAR16**);
 void *Exit;
 EFI_STATUS(EFIAPI *UnloadImage)(EFI_HANDLE);
 void *ExitBootServices,*GetNextMonotonicCount;
 EFI_STATUS(EFIAPI *Stall)(UINTN);
 void *SetWatchdogTimer,*ConnectController,*DisconnectController,*OpenProtocol,*CloseProtocol;
 void *OpenProtocolInformation,*ProtocolsPerHandle,*LocateHandleBuffer,*LocateProtocol;
 void *InstallMultipleProtocolInterfaces,*UninstallMultipleProtocolInterfaces;
 void *CalculateCrc32,*CopyMem,*SetMem,*CreateEventEx;
} BOOT_SERVICES;
typedef struct {EFI_TABLE_HEADER Hdr; EFI_STATUS(EFIAPI *GetTime)(EFI_TIME*,void*);} RUNTIME_SERVICES;
typedef struct {
 EFI_TABLE_HEADER Hdr; CHAR16 *FirmwareVendor; U32 FirmwareRevision;
 EFI_HANDLE ConsoleInHandle; void *ConIn; EFI_HANDLE ConsoleOutHandle; void *ConOut;
 EFI_HANDLE StandardErrorHandle; void *StdErr; RUNTIME_SERVICES *RuntimeServices;
 BOOT_SERVICES *BootServices; UINTN NumberOfTableEntries; void *ConfigurationTable;
} SYSTEM_TABLE;
_Static_assert(sizeof(void*)==8,"x64 only");
_Static_assert(sizeof(CHAR16)==2,"UEFI strings are UTF16");
_Static_assert(sizeof(EFI_TIME)==16,"EFI_TIME layout");
_Static_assert(sizeof(EFI_TABLE_HEADER)==24,"table header layout");
_Static_assert(sizeof(SYSTEM_TABLE)==120,"system table layout");
_Static_assert(offsetof(SYSTEM_TABLE,BootServices)==96,"BootServices offset");
_Static_assert(sizeof(BOOT_SERVICES)==376,"boot services layout");
_Static_assert(offsetof(BOOT_SERVICES,HandleProtocol)==152,"HandleProtocol offset");
_Static_assert(offsetof(BOOT_SERVICES,LoadImage)==200,"LoadImage offset");
_Static_assert(offsetof(BOOT_SERVICES,StartImage)==208,"StartImage offset");
_Static_assert(offsetof(BOOT_SERVICES,Stall)==248,"Stall offset");
_Static_assert(offsetof(LOADED_IMAGE,LoadOptions)==56,"LoadOptions offset");
_Static_assert(sizeof(LOADED_IMAGE)==96,"loaded image layout");
_Static_assert(offsetof(FILE_PROTOCOL,Write)==40,"file Write offset");
_Static_assert(offsetof(FILE_PROTOCOL,Flush)==80,"file Flush offset");
#endif
