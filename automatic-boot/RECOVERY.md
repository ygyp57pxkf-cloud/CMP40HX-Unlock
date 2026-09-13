# 无法启动与停用试验

首次改引导须可到现场恢复。新管理器正常出现菜单时选择 **Windows recovery**；如果前置EFI无响应且约5分钟仍卡住，确认不是Windows更新后长按电源关机，再开机从主板菜单选择 **Windows Boot Manager**。不要误选旧 `40HX Unlock` 直启。

这只绕过本次。要让以后默认普通Windows，在管理员PowerShell运行已部署的管理工具：

```powershell
& 'C:\ProgramData\40HX-Automation\TraceLoader\Manage-TraceLoader.ps1' -Action Disable
```

工具核验自己的Trace变量，把Windows第一并从BootOrder排除Trace，保留文件和变量供后续检查，不删除其他启动项，不重启。公开工具的新部署需同目录FirmwareVariables.ps1及profile.local.json；原固定本机部署副本为自包含脚本，两者不要混放覆盖。

若需要连Gen2自动操作一起关闭，先导出当前任务XML和原Run项，再只停用自己核验过的40HX任务/Run值。不要按模糊名称删除别的启动项，不强杀正在禁用/启用GPU的安装器。本机已有 `Recover-Windows.ps1 -Action Recover` 和桌面恢复快捷方式，该文件含私有机器保护信息，保留在本机和此前私有交付中，不作为跨机器通用恢复工具发布。

备份默认位于 `C:\ProgramData\40HX-Automation\TraceLoader`，包含BCD.before和variables.before.json。正常能进Windows时，不应为了取消试验而导入整个旧BCD、运行bootrec/bcdboot、清空NVRAM或重刷系统。若Windows启动项缺失但微软文件仍在，可使用固件支持的Boot From File直接选系统ESP的 `EFI\Microsoft\Boot\bootmgfw.efi`。

恢复普通Windows后算力锁定是预期：算力EFI没有运行。恢复成功与双解锁成功是两个不同验收目标。重新启用前读取当前状态，不删除状态文件反复Apply；不自动恢复过时的BootOrder或已删除GUID。
