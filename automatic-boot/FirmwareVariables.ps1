Add-Type @'
using System;
using System.Runtime.InteropServices;
public sealed class TraceVariable { public byte[] Bytes; public uint Attributes; }
public static class TraceFirmwareApi {
 const string Guid="{8BE4DF61-93CA-11D2-AA0D-00E098032B8C}";
 [StructLayout(LayoutKind.Sequential)] struct LUID {public uint Low;public int High;}
 [StructLayout(LayoutKind.Sequential)] struct TP {public uint Count;public LUID Luid;public uint Attributes;}
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr h,uint a,out IntPtr t);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool LookupPrivilegeValue(string s,string n,out LUID l);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr t,bool d,ref TP p,uint z,IntPtr o,IntPtr r);
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",EntryPoint="GetFirmwareEnvironmentVariableExW",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint Get(string n,string g,byte[] b,uint s,out uint a);
 [DllImport("kernel32.dll",EntryPoint="SetFirmwareEnvironmentVariableExW",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool Set(string n,string g,byte[] b,uint s,uint a);
 static void Enable() {
  IntPtr t;if(!OpenProcessToken(GetCurrentProcess(),0x28,out t))throw new System.ComponentModel.Win32Exception();
  try {LUID l;if(!LookupPrivilegeValue(null,"SeSystemEnvironmentPrivilege",out l))throw new System.ComponentModel.Win32Exception();
   TP p=new TP{Count=1,Luid=l,Attributes=2};if(!AdjustTokenPrivileges(t,false,ref p,0,IntPtr.Zero,IntPtr.Zero))throw new System.ComponentModel.Win32Exception();
   int e=Marshal.GetLastWin32Error();if(e!=0)throw new System.ComponentModel.Win32Exception(e);
  }finally{CloseHandle(t);}
 }
 public static TraceVariable Read(string name) {
  Enable();byte[] b=new byte[65536];uint a;uint n=Get(name,Guid,b,(uint)b.Length,out a);
  if(n==0){int e=Marshal.GetLastWin32Error();if(e==203)return null;throw new System.ComponentModel.Win32Exception(e);}
  Array.Resize(ref b,(int)n);return new TraceVariable{Bytes=b,Attributes=a};
 }
 public static void Write(string name,byte[] bytes,uint attributes) {
  if(bytes==null || bytes.Length==0 || !(name=="BootOrder" || System.Text.RegularExpressions.Regex.IsMatch(name,"^Boot[0-9A-F]{4}$")))throw new ArgumentException("Refusing firmware deletion or unrelated variable write");
  Enable();if(!Set(name,Guid,bytes,(uint)bytes.Length,attributes))throw new System.ComponentModel.Win32Exception();
 }
}
'@