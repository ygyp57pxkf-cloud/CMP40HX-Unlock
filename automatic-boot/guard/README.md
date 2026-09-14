# Guard v1.0-rc1：Shell报错后延迟重试，失败直接启动Windows

用于[2026-09-14的Shell StartImage Device Error](../INCIDENT-20260914.md)：原RefindPlus接到Shell错误后停在菜单，Windows即使在BootOrder第二也无法接管。Guard放在RefindPlus和原Shell之间处理返回错误，保留原成功的初始化链和30秒脚本。

规则固定为：首次启动原Shell；若返回（包括异常的EFI_SUCCESS返回），等待30秒，再尝试一次；再次返回则直接启动同一ESP的微软 `EFI\Microsoft\Boot\bootmgfw.efi`。等待服务本身出错时跳过第二次Shell，直接尝试Windows。正常Shell/Windows链转移控制后不会返回Guard，因此不会多等或重复执行。

这是返回错误处理与恢复补丁，不是已证明根治Shell控制台初始化故障。没有NVRAM写入、显卡寄存器写入、PnP重置、无限重试、复位循环或额外驱动。真正固件硬锁死/子程序不返回，以及微软Windows loader自身失败时，不能保证自动进入系统；首次试验仍需现场恢复。

## 已验证与尚未验证

- 13种主机端UEFI服务模拟场景通过：正常转移、第一次设备错误后成功、两次失败进Windows、LoadImage/协议/等待/内存/路径错误、Windows也失败、日志写入失败等。
- 静态核验UEFI结构偏移及x64 ABI；二进制为PE32+ x64 EFI_APPLICATION，无Windows DLL导入，含重定位目录。
- 本机于2026-09-14 18:46完成独立文件与RefindPlus配置部署、ESP读回，原Shell/算力EFI/微软恢复文件未变。新的Guard实际启动/真实失败回退尚未验收，不能将模拟测试称为固件实机通过。
- 本机部署/恢复工具另外通过7项文件替换保护检查，Windows只读审计回归通过。该部署工具有本机保护信息，仍保留本地，不作为公共一键安装器。

## 构建

使用[官方Zig0.14.1](https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip)，ZIP SHA256在manifest.json。解压后管理员权限不是构建所需条件：

```powershell
.\Build.ps1 -ZigPath C:\Tools\zig-x86_64-windows-0.14.1\zig.exe
```

输出bin/guard-tests.exe和bin/guard_x64.efi。Build会先执行故障注入，再构建并检查EFI格式。安装/升级必须核对实际输出哈希，不能用构建成功代替实机启动验收。

## 安装到已有RefindPlus链

仅在已经具备SETUP.md中的Shell/原EFI/微软恢复路径时使用：

1. 备份现有RefindPlus config.conf，保持独立Windows恢复菜单；确认系统ESP和载荷来源。
2. 新建系统ESP的 `EFI\40HX-Guard`，复制guard_x64.efi。
3. 将RefindPlus默认项的loader改为 `\EFI\40HX-Guard\guard_x64.efi`，不再直接指向Shell；保留同一实际ESP volume GUID。将菜单名和default_selection同步为 `40HX guarded automatic unlock`。
4. Guard内部固定向原Shell传入 `-startup -nointerrupt -noconsolein -exit -delay 0`，因此外层Guard菜单不需要Shell options。不修改原startup.nsh。
5. 回读配置与二进制，再进行现场普通自动启动。失败轮可能多出“Guard等30秒＋第二次Shell原脚本等30秒”。

示例（ESP_GUID必须替换为本机实际值）：

```text
timeout 8
textonly
scanfor manual
default_selection "40HX guarded automatic unlock"
menuentry "40HX guarded automatic unlock" {
    volume "ESP_GUID"
    loader \EFI\40HX-Guard\guard_x64.efi
}
menuentry "Windows recovery" {
    volume "ESP_GUID"
    loader \EFI\Microsoft\Boot\bootmgfw.efi
}
```

回滚只需恢复原config.conf；如果要普通Windows优先，按RECOVERY.md处理。不能通过删除微软文件或清空BCD取消本试验。

## 日志

Guard写 `EFI\40HX-Guard\guard-YYYYMMDD-HHMMSS.log`，每个阶段包含完整64位状态。RTC失败时追加到guard-last.log。标记包括shell.1.load/start.return、retry.wait30.begin/end、shell.2、fallback.windows及windows.load/start.return。每次写入后Flush/Close，调用子程序前不持有日志文件句柄；日志失败不会阻止尝试Windows。

Windows本机只读审计已增加收集该目录最近8个匹配日志。日志是阶段证据，必须结合本次Windows启动与SS0/SS1，不能把文件存在当作双解锁成功。

代码按仓库MIT许可证提供。uefi_min.h只声明本程序使用的UEFI标准ABI布局，不含Windows SDK、微软loader或显卡驱动二进制。
