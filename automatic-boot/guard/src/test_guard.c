#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#define GUARD_TEST
#include "guard.c"
static jmp_buf transfer;
static BOOT_SERVICES mock_bs;
static SYSTEM_TABLE mock_st;
static LOADED_IMAGE self_image,children[8];
static U8 disk_path[46];
static int loads,starts,unloads,waits,allocations,shell_starts,windows_starts;
static int load_fail_at,protocol_fail_at,allocate_fail,transfer_shell_at,wait_fail,windows_returns;
static EFI_STATUS shell_status;
static int kinds[8],event_count;
static char events[100][100];
static SIMPLE_FS test_fs;
static FILE_PROTOCOL root_file,log_file;
static RUNTIME_SERVICES test_rt;
static int logging_enabled,open_handles,writes,flushes,write_failure;
static void check(int condition,const char *message){if(!condition){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static int same16(const CHAR16*a,const CHAR16*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
static void test_log(const char *name,EFI_STATUS s){(void)s;if(event_count<100){snprintf(events[event_count++],100,"%s",name);}}
static int has(const char *event){for(int i=0;i<event_count;i++)if(!strcmp(events[i],event))return 1;return 0;}
static EFI_STATUS EFIAPI mock_allocate(U32 kind,UINTN size,void **p){check(kind==2,"allocate LoaderData only");if(allocate_fail)return EFI_OUT_OF_RESOURCES;*p=malloc((size_t)size);allocations++;return *p?0:EFI_OUT_OF_RESOURCES;}
static EFI_STATUS EFIAPI mock_free(void*p){free(p);allocations--;return 0;}
static EFI_STATUS EFIAPI mock_close(FILE_PROTOCOL*f){(void)f;open_handles--;return 0;}
static EFI_STATUS EFIAPI mock_position(FILE_PROTOCOL*f,U64 pos){(void)f;check(pos==~0ULL,"logs append instead of truncating");return 0;}
static EFI_STATUS EFIAPI mock_write(FILE_PROTOCOL*f,UINTN*n,void*p){(void)f;char *s=p;check(*n>20&&s[*n-2]=='\r'&&s[*n-1]=='\n',"status log has complete line framing");writes++;return write_failure?EFI_DEVICE_ERROR:0;}
static EFI_STATUS EFIAPI mock_flush(FILE_PROTOCOL*f){(void)f;flushes++;return 0;}
static EFI_STATUS EFIAPI mock_open(FILE_PROTOCOL*f,FILE_PROTOCOL**out,CHAR16*path,U64 mode,U64 attrs){(void)f;check(same16(path,L"\\EFI\\40HX-Guard\\guard-20260914-190203.log"),"unique UTC-independent firmware timestamp filename");check(mode==0x8000000000000003ULL&&!attrs,"only read/write/create log mode");*out=&log_file;open_handles++;return 0;}
static EFI_STATUS EFIAPI mock_volume(void*fs,FILE_PROTOCOL**out){(void)fs;*out=&root_file;open_handles++;return 0;}
static EFI_STATUS EFIAPI mock_time(EFI_TIME*t,void*c){(void)c;memset(t,0,sizeof(*t));t->Year=2026;t->Month=9;t->Day=14;t->Hour=19;t->Minute=2;t->Second=3;return 0;}
static EFI_STATUS EFIAPI mock_protocol(EFI_HANDLE h,EFI_GUID*g,void**p){
 if(!memcmp(g,&loaded_guid,sizeof(*g))){
  if(h==(EFI_HANDLE)1){*p=&self_image;return 0;}
  int n=(int)(UINTN)h-100;if(n==protocol_fail_at)return EFI_DEVICE_ERROR;
  if(n>0&&n<8){*p=&children[n];return 0;}
 }
 if(h==(EFI_HANDLE)2&&!memcmp(g,&path_guid,sizeof(*g))){*p=disk_path;return 0;}
 if(logging_enabled&&h==(EFI_HANDLE)2&&!memcmp(g,&fs_guid,sizeof(*g))){*p=&test_fs;return 0;}
 /* Filesystem/logging unavailable: forwarding must still work. */
 return EFI_UNSUPPORTED;
}
static EFI_STATUS EFIAPI mock_load(U8 policy,EFI_HANDLE parent,DEVICE_PATH*dp,void*source,UINTN size,EFI_HANDLE*child){
 check(policy==0&&parent==(EFI_HANDLE)1&&!source&&!size,"same-ESP file LoadImage semantics");
 check(!memcmp(dp,disk_path,42),"partition addressing preserved");
 DEVICE_PATH *file=(DEVICE_PATH*)((U8*)dp+42);check(file->Type==4&&file->SubType==4,"file device path node");
 CHAR16 *name=(CHAR16*)((U8*)file+4);loads++;check(loads<8,"no runaway attempts");
 kinds[loads]=same16(name,windows_path)?2:1;
 check(kinds[loads]==2||same16(name,shell_path),"only reviewed Shell and Windows paths");
 DEVICE_PATH *end=(DEVICE_PATH*)((U8*)file+file->Length);check(end->Type==0x7f&&end->SubType==0xff&&end->Length==4,"valid final path node");
 if(loads==load_fail_at)return EFI_DEVICE_ERROR;
 *child=(EFI_HANDLE)(UINTN)(100+loads);return 0;
}
static EFI_STATUS EFIAPI mock_start(EFI_HANDLE child,UINTN *size,CHAR16 **data){
 int n=(int)(UINTN)child-100;check(!size&&!data,"no unmanaged ExitData allocation");check(allocations==0,"temporary path freed before child runs");check(!open_handles,"log files closed before transfer");starts++;
 if(kinds[n]==1){
  shell_starts++;check(same16(children[n].LoadOptions,shell_options),"known-good options preserved");check(children[n].LoadOptionsSize==sizeof(shell_options),"UTF16 option terminator counted");
  if(shell_starts==transfer_shell_at)longjmp(transfer,1);
  return shell_status;
 }
 windows_starts++;check(children[n].LoadOptions==0&&children[n].LoadOptionsSize==0,"Windows has no Shell options");
 if(!windows_returns)longjmp(transfer,2);return EFI_DEVICE_ERROR;
}
static EFI_STATUS EFIAPI mock_unload(EFI_HANDLE h){check((UINTN)h>100,"only child images unloaded");unloads++;return 0;}
static EFI_STATUS EFIAPI mock_wait(UINTN us){check(us==30000000ULL,"retry delay is exactly 30 seconds");waits++;return wait_fail?EFI_DEVICE_ERROR:0;}
static void reset(void){
 memset(&mock_bs,0,sizeof(mock_bs));memset(&mock_st,0,sizeof(mock_st));memset(&self_image,0,sizeof(self_image));memset(children,0,sizeof(children));memset(disk_path,0,sizeof(disk_path));
 disk_path[0]=4;disk_path[1]=1;disk_path[2]=42;disk_path[42]=0x7f;disk_path[43]=0xff;disk_path[44]=4;
 mock_bs.HandleProtocol=mock_protocol;mock_bs.AllocatePool=mock_allocate;mock_bs.FreePool=mock_free;mock_bs.LoadImage=mock_load;mock_bs.StartImage=mock_start;mock_bs.UnloadImage=mock_unload;mock_bs.Stall=mock_wait;
 mock_st.BootServices=&mock_bs;self_image.DeviceHandle=(EFI_HANDLE)2;
 loads=starts=unloads=waits=allocations=shell_starts=windows_starts=event_count=0;
 load_fail_at=protocol_fail_at=allocate_fail=transfer_shell_at=wait_fail=windows_returns=0;shell_status=EFI_DEVICE_ERROR;
 logging_enabled=open_handles=writes=flushes=write_failure=0;
 memset(&test_fs,0,sizeof(test_fs));memset(&root_file,0,sizeof(root_file));memset(&log_file,0,sizeof(log_file));memset(&test_rt,0,sizeof(test_rt));
 test_fs.OpenVolume=mock_volume;root_file.Open=mock_open;root_file.Close=mock_close;log_file.Close=mock_close;log_file.SetPosition=mock_position;log_file.Write=mock_write;log_file.Flush=mock_flush;test_rt.GetTime=mock_time;
}
static int run(EFI_STATUS *returned){int where=setjmp(transfer);if(!where)*returned=EfiMain((EFI_HANDLE)1,&mock_st);return where;}
int main(void){EFI_STATUS r=0;int outcome;
 reset();transfer_shell_at=1;outcome=run(&r);check(outcome==1&&loads==1&&!waits&&!windows_starts,"normal transfer has no retry or fallback");puts("PASS normal Shell/Windows transfer");
 reset();transfer_shell_at=2;outcome=run(&r);check(outcome==1&&loads==2&&waits==1&&unloads==1,"one DeviceError gets one delayed retry");puts("PASS DeviceError then successful retry");
 reset();outcome=run(&r);check(outcome==2&&loads==3&&shell_starts==2&&waits==1&&windows_starts==1&&unloads==2,"two errors go directly to Windows");check(has("fallback.windows.begin"),"fallback logged");puts("PASS two Shell failures directly chainload Windows");
 reset();load_fail_at=1;transfer_shell_at=1;outcome=run(&r);check(outcome==1&&loads==2&&waits==1&&!unloads,"LoadImage failure follows bounded retry");puts("PASS file loading failure");
 reset();protocol_fail_at=1;transfer_shell_at=1;outcome=run(&r);check(outcome==1&&loads==2&&unloads==1&&waits==1,"protocol failure cleans child and retries");puts("PASS child protocol failure");
 reset();shell_status=EFI_SUCCESS;outcome=run(&r);check(outcome==2&&shell_starts==2&&windows_starts==1,"unexpected Shell success return is not OS boot");puts("PASS unexpected EFI_SUCCESS return");
 reset();wait_fail=1;outcome=run(&r);check(outcome==2&&shell_starts==1&&windows_starts==1&&waits==1,"failed stall skips second Shell and enters Windows");puts("PASS stalled delay reports failure and falls back");
 reset();windows_returns=1;outcome=run(&r);check(outcome==0&&r==EFI_DEVICE_ERROR&&loads==3&&unloads==3&&waits==1,"Windows error returns with no retry/reset loop");puts("PASS Windows failure remains bounded");
 reset();allocate_fail=1;outcome=run(&r);check(outcome==0&&r==EFI_OUT_OF_RESOURCES&&!loads&&!starts&&waits==1,"allocation errors do not dereference invalid memory");puts("PASS out-of-memory boundaries");
 reset();disk_path[2]=2;outcome=run(&r);check(outcome==0&&r==EFI_INVALID_PARAMETER&&!loads&&!allocations,"malformed device path refused");puts("PASS malformed device path");
 reset();disk_path[43]=1;outcome=run(&r);check(outcome==0&&r==EFI_UNSUPPORTED&&!loads,"multi-instance device path refused");puts("PASS unsupported multi-instance path");
 reset();logging_enabled=1;mock_st.RuntimeServices=&test_rt;outcome=run(&r);check(outcome==2&&writes>10&&writes==flushes&&!open_handles,"each status appended, flushed and closed");puts("PASS persistent logging and timestamp path");
 reset();logging_enabled=write_failure=1;mock_st.RuntimeServices=&test_rt;outcome=run(&r);check(outcome==2&&!open_handles,"failed log writes never prevent Windows recovery");puts("PASS filesystem logging errors do not block recovery");
 check(!allocations,"no outstanding mock allocations");puts("All 13 fault-injection scenarios passed. Real firmware boot remains untested.");return 0;
}
