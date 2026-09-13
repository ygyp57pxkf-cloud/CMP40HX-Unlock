# 从准备到自动运行

本方案面向已经能用原EFI解锁、但自动调度不稳定的40HX。尚未安装原解锁工具的机器应先阅读上游BIOS/驱动说明，建立普通Windows恢复路径。不要把ASUS这一台成功样本当作其他型号的兼容性保证。

## 1. 前提与备份

- 确认Windows以UEFI方式安装；确认Secure Boot状态、BitLocker保护及恢复条件。脚本会拒绝活动Secure Boot或BitLocker保护，不会替你关闭它们。
- 按主板实际菜单核对Above4G、CSM、Fast Boot、CPU直连插槽；有些主板缺少Above4G/ReBAR选项也能成功，不能因为菜单缺项就宣称不可解。Windows分配到了4GB以上地址也不能证明BIOS开关状态。
- 保存当前BootOrder/BootNext、Windows loader路径和原始EFI/Shell文件。微软 `EFI\Microsoft\Boot\bootmgfw.efi` 与独立的微软 `EFI\Boot\bootx64.efi` 应保留为恢复；不要把诊断工具放到微软路径。
- 首次改引导时需要现场恢复能力。WOL不能把卡在EFI的已通电电脑强制重启。

## 2. 准备固定版本文件

管理员PowerShell在本目录执行：

```powershell
.\Get-BootPayloads.ps1
.\Get-TracePayload.ps1
```

第一条校验上游3.1.2-win ZIP与安装器，从已确认偏移提取原内嵌EFI，取得EDK2 Shell 26H1；第二条取得RefindPlus v0.14.2.AE DEBUG。只准备本地文件，不安装，不运行exe。离线可用 `Get-BootPayloads.ps1 -ArchivePath <原ZIP> -ShellPath <已验证Shell>` 和 `Get-TracePayload.ps1 -ArchivePath <官方RefindPlusZIP>`。

为何不直接用发布包外置EFI：本机验证的内嵌EFI与该包外置文件不同，详见FILES.md。当前已成功机器保留原ESP文件，不需要重新提取或覆盖。

## 3. 先建立原Shell阶段

目标ESP布局如下；系统分区以实际GUID核对，不能假设总是某个盘符：

```text
EFI/Microsoft/Boot/bootmgfw.efi    微软Windows启动文件
EFI/Boot/bootx64.efi              独立微软恢复文件
EFI/40HX/40HXUNLK.EFI             原算力EFI
EFI/40HX-Auto/shellx64.efi         已校验的EDK2 Shell
EFI/40HX-Auto/startup.nsh          Shell脚本
EFI/40HX-Auto/40HX-AUTO.tag        新部署参考脚本的空标记文件
EFI/40HX-Auto/connect.enabled     启用connect步骤的空标记文件
```

`reference/startup.nsh` 是成功脚本的通用标记版：记录BootCurrent与PCI配置，connect -r，等待30秒，再调用原算力EFI；若EFI返回则调用微软Windows。已有成功脚本使用其他标记名时保持它和原标记文件一致，**不要为统一文件名覆盖已成功的脚本**。

已有 `40HX Auto Trial - SameEfiConnect` 的机器跳过此段。新机器需通过主板的Add Boot Option功能创建指向上述Shell的独立项，或在有bcfg命令的UEFI Shell中使用 `bcfg boot dump -v` 核对后，以 `bcfg boot add N fsX:\EFI\40HX-Auto\shellx64.efi "40HX Auto Trial - SameEfiConnect"` 添加。N应为当前列表末尾位置，fsX必须通过map核实为系统ESP；不是照抄0或fs0。建立阶段可手选验证一次，此次不计自动启动验收。主板不提供添加功能且不熟悉bcfg时先停在Windows恢复状态，不能盲改微软fallback。

## 4. 捕获本机配置并建立Trace默认入口

核对原始Boot变量编号，下面0002/0000/0001只是本机原配置示例：

```powershell
.\Prepare-LocalProfile.ps1 -ShellVariable Boot0002 -WindowsVariable Boot0000 -LegacyVariable Boot0001
.\Manage-TraceLoader.ps1 -Action Inspect
```

生成 `profile.local.json` 与 `diagnostic-loader/config.conf`。它们记录实际分区、原顺序和五个保护文件的哈希。捕获哈希仅用来防止意外变化，**不证明原载荷可信或能成功解锁**；须与FILES.md及普通Windows恢复实测一起核对。准备脚本不写ESP或NVRAM，只临时挂载读取。

确认前置链已建立、备份与恢复就绪后，新的安装可执行：

```powershell
.\Manage-TraceLoader.ps1 -Action Apply
```

它只在空闲Boot编号新建Trace，顺序为Trace → Windows →其余原项，文件放在 `EFI\40HX-Trace`。默认8秒进入Shell，Shell参数为 `-startup -nointerrupt -noconsolein -exit -delay 0`。这里delay0不取消startup.nsh里的30秒。工具保留状态、拒绝重复安装，且不会重启。

## 5. Windows只保留一个Gen2操作者

本机保留原用户Run项 `40HXGen2`，命令为经过核验的安装器路径加 `-gen2 -silent`。现有SYSTEM任务仅采集，不调用Gen2或PnP。不要同时增加“开机一条、登录一条、启动文件夹再一条”竞争写入。

本机SYSTEM审计原本在开机45秒/登录30秒运行，可能采到Gen2驱动重载中的瞬态。新 `Collect-Evidence.ps1` 最多等待指定稳定时间，以两次连续读到Code0/SMI成功记录驱动可用；它不重置GPU，SMI的Gen1也不会触发重训。持续失败要结合最后状态与日志调查。默认情况下Gen2依赖用户登录，无人登录的WOL场景单独验收。

## 6. 实际验收

完整关机再开机，首次自动验证不要手选启动项。进入Windows登录后，等Gen2流程结束，运行原40HXCheck保存诊断，再运行：

```powershell
.\Collect-Evidence.ps1 -WindowsDiagnosticPath "$env:LOCALAPPDATA\40HXUnlock\logs\diagnose.txt"
```

必须共同满足：Trace新日志显示TIMEOUT自动选Shell；Shell新日志connect成功、等待完整；本轮EFI final SS0=88888888/SS1=8；Windows本轮诊断同样满血；原始LNKSTA为Gen2×16；设备Code0；实际CUDA/应用工作正确。

随后记录连续普通重启、完整冷启动、WOL及实际负载。一次成功不是长期验收；驱动或EFI升级之后重新检查旧补丁是否仍必要。DEBUG日志会增长，新采集器限定复制数量/大小但不删除ESP日志；长期部署需检查空间并在保留故障证据后规划日志维护。
