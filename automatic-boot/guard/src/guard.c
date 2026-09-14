#include "uefi_min.h"
/* MIT. A bounded return-error guard; no firmware-variable writes or GPU access.
 * It cannot recover a child that never returns (including a genuine firmware hang).
 * Keep it behind the existing RefindPlus entry so that initialization stays intact.
 */
static EFI_GUID loaded_guid={0x5b1b31a1,0x9562,0x11d2,{0x8e,0x3f,0,0xa0,0xc9,0x69,0x72,0x3b}};
static EFI_GUID path_guid={0x09576e91,0x6d3f,0x11d2,{0x8e,0x39,0,0xa0,0xc9,0x69,0x72,0x3b}};
static EFI_GUID fs_guid={0x964e5b22,0x6459,0x11d2,{0x8e,0x39,0,0xa0,0xc9,0x69,0x72,0x3b}};
static CHAR16 shell_path[]=L"\\EFI\\40HX-Auto\\shellx64.efi";
static CHAR16 windows_path[]=L"\\EFI\\Microsoft\\Boot\\bootmgfw.efi";
/* Exact options used by the known-working RefindPlus StartEFIImage call. */
static CHAR16 shell_options[]=L"-startup -nointerrupt -noconsolein -exit -delay 0";
/* Keep one referenced absolute data pointer so the PE carries a relocation
 * directory even when the rest of x64 code is RIP-relative. */
static CHAR16 * volatile shell_path_pointer=shell_path;
static BOOT_SERVICES *bs;
static EFI_HANDLE image_handle,device_handle;
static CHAR16 log_path[100];
static UINTN wide_len(const CHAR16 *s){UINTN n=0;while(s[n])n++;return n;}
static void bytes_copy(void *d,const void *s,UINTN n){U8 *a=d;const U8 *b=s;while(n--)*a++=*b++;}
static void put_decimal(CHAR16 *p,U32 n,U32 width){while(width){p[--width]=(CHAR16)('0'+n%10);n/=10;}}
static void set_log_path(SYSTEM_TABLE *st){
 static CHAR16 fallback[]=L"\\EFI\\40HX-Guard\\guard-last.log";
 static CHAR16 dated[]=L"\\EFI\\40HX-Guard\\guard-00000000-000000.log";
 EFI_TIME t={0};EFI_STATUS r=EFI_UNSUPPORTED;
 if(st->RuntimeServices && st->RuntimeServices->GetTime)r=st->RuntimeServices->GetTime(&t,0);
 if(EFI_ERROR(r)||t.Year<2000||t.Year>9999){bytes_copy(log_path,fallback,sizeof(fallback));return;}
 bytes_copy(log_path,dated,sizeof(dated));
 UINTN i=wide_len(L"\\EFI\\40HX-Guard\\guard-");
 put_decimal(log_path+i,t.Year,4);put_decimal(log_path+i+4,t.Month,2);put_decimal(log_path+i+6,t.Day,2);
 put_decimal(log_path+i+9,t.Hour,2);put_decimal(log_path+i+11,t.Minute,2);put_decimal(log_path+i+13,t.Second,2);
}
#ifdef GUARD_TEST
static void test_log(const char*,EFI_STATUS);
#endif
static void log_status(const char *event,EFI_STATUS status){
#ifdef GUARD_TEST
 test_log(event,status);
#endif
 SIMPLE_FS *fs=0;FILE_PROTOCOL *root=0,*file=0;
 if(!device_handle || EFI_ERROR(bs->HandleProtocol(device_handle,&fs_guid,(void**)&fs)) || !fs)return;
 if(EFI_ERROR(fs->OpenVolume(fs,&root))||!root)return;
 EFI_STATUS r=root->Open(root,&file,log_path,0x8000000000000003ULL,0);
 if(!EFI_ERROR(r)&&file){
  char line[180];UINTN n=0;
  while(event[n]&&n<140){line[n]=event[n];n++;}
  line[n++]=' ';line[n++]='0';line[n++]='x';
  for(int shift=60;shift>=0;shift-=4)line[n++]="0123456789ABCDEF"[(status>>shift)&15];
  line[n++]='\r';line[n++]='\n';
  if(!EFI_ERROR(file->SetPosition(file,~0ULL))){UINTN size=n;file->Write(file,&size,line);file->Flush(file);}
  file->Close(file);
 }
 root->Close(root);
}
static void log_phase(const char *prefix,const char *phase,EFI_STATUS status){
 char name[100];UINTN n=0;while(*prefix&&n<60)name[n++]=*prefix++;
 while(*phase&&n<99)name[n++]=*phase++;name[n]=0;log_status(name,status);
}
static EFI_STATUS build_path(CHAR16 *file_name,DEVICE_PATH **result){
 DEVICE_PATH *device=0;*result=0;
 EFI_STATUS r=bs->HandleProtocol(device_handle,&path_guid,(void**)&device);
 if(EFI_ERROR(r)||!device)return EFI_ERROR(r)?r:EFI_INVALID_PARAMETER;
 UINTN prefix=0;U32 nodes=0;
 for(;;){
  if(prefix>4092 || ++nodes>256)return EFI_INVALID_PARAMETER;
  DEVICE_PATH *node=(DEVICE_PATH*)((U8*)device+prefix);UINTN len=node->Length;
  if(len<4||prefix+len>4096)return EFI_INVALID_PARAMETER;
  if(node->Type==0x7f){if(node->SubType!=0xff||len!=4)return EFI_UNSUPPORTED;break;}
  prefix+=len;
 }
 UINTN chars=wide_len(file_name)+1;if(chars>512)return EFI_INVALID_PARAMETER;
 UINTN file_size=4+2*chars,total=prefix+file_size+4;
 U8 *buffer=0;r=bs->AllocatePool(2,total,(void**)&buffer);
 if(EFI_ERROR(r)||!buffer)return EFI_ERROR(r)?r:EFI_OUT_OF_RESOURCES;
 bytes_copy(buffer,device,prefix);
 DEVICE_PATH *file=(DEVICE_PATH*)(buffer+prefix);file->Type=4;file->SubType=4;file->Length=(U16)file_size;
 bytes_copy(buffer+prefix+4,file_name,chars*2);
 DEVICE_PATH *end=(DEVICE_PATH*)(buffer+prefix+file_size);end->Type=0x7f;end->SubType=0xff;end->Length=4;
 *result=(DEVICE_PATH*)buffer;return EFI_SUCCESS;
}
static EFI_STATUS launch(CHAR16 *path,CHAR16 *options,const char *prefix){
 DEVICE_PATH *dp=0;EFI_HANDLE child=0;LOADED_IMAGE *loaded=0;
 EFI_STATUS r=build_path(path,&dp);log_phase(prefix,".path",r);if(EFI_ERROR(r))return r;
 r=bs->LoadImage(0,image_handle,dp,0,0,&child);bs->FreePool(dp);log_phase(prefix,".load",r);
 if(EFI_ERROR(r))return r;
 if(!child){log_phase(prefix,".null_handle",EFI_LOAD_ERROR);return EFI_LOAD_ERROR;}
 r=bs->HandleProtocol(child,&loaded_guid,(void**)&loaded);log_phase(prefix,".protocol",r);
 if(EFI_ERROR(r)||!loaded){bs->UnloadImage(child);return EFI_ERROR(r)?r:EFI_LOAD_ERROR;}
 loaded->LoadOptions=options;loaded->LoadOptionsSize=options?(U32)((wide_len(options)+1)*2):0;
 log_phase(prefix,".start.begin",EFI_SUCCESS);
 r=bs->StartImage(child,0,0);
 /* A working Windows chain transfers control and never returns here. */
 log_phase(prefix,".start.return",r);
 EFI_STATUS unload=bs->UnloadImage(child);log_phase(prefix,".unload",unload);
 return r;
}
static EFI_STATUS run_guard(void){
 log_status("guard.version.1.begin",EFI_SUCCESS);
 EFI_STATUS first=launch(shell_path_pointer,shell_options,"shell.1");
 log_status("shell.1.unexpected_return",first);
 log_status("retry.wait30.begin",EFI_SUCCESS);
 EFI_STATUS wait=bs->Stall(30000000ULL);log_status("retry.wait30.end",wait);
 if(!EFI_ERROR(wait)){
  EFI_STATUS second=launch(shell_path_pointer,shell_options,"shell.2");
  log_status("shell.2.unexpected_return",second);
 }
 log_status("fallback.windows.begin",EFI_SUCCESS);
 EFI_STATUS win=launch(windows_path,0,"windows");
 log_status("fallback.windows.unexpected_return",win);
 /* Even Windows returned: allow parent firmware/boot manager recovery handling.
  * No additional attempts, no reset loop, and no NVRAM writes. */
 return EFI_ERROR(win)?win:EFI_ABORTED;
}
EFI_STATUS EFIAPI EfiMain(EFI_HANDLE image,SYSTEM_TABLE *st){
 if(!st||!st->BootServices)return EFI_INVALID_PARAMETER;
 bs=st->BootServices;image_handle=image;device_handle=0;
 LOADED_IMAGE *loaded=0;EFI_STATUS r=bs->HandleProtocol(image,&loaded_guid,(void**)&loaded);
 if(EFI_ERROR(r)||!loaded||!loaded->DeviceHandle)return EFI_ERROR(r)?r:EFI_INVALID_PARAMETER;
 device_handle=loaded->DeviceHandle;set_log_path(st);
 return run_guard();
}
