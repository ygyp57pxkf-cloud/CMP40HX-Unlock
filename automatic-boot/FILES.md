# 文件与来源清单

| 文件 | 作用/来源 |
|---|---|
| `Manage-TraceLoader.ps1` | 独立Trace入口Inspect/Apply/Disable，带备份、并发校验和写后回读 |
| `FirmwareVariables.ps1` | Windows原生固件变量接口，每次操作重新启用所需权限；不提供清空NVRAM操作 |
| `Prepare-LocalProfile.ps1` | 捕获本机ESP、现有启动项与保护文件摘要，渲染配置模板，结果只留本地 |
| `Collect-Evidence.ps1` | 只读采集Boot状态、EFI/Shell/Trace文件与时间、驱动稳定过程和本轮Windows诊断；不加载底层驱动，不写GPU |
| `Get-BootPayloads.ps1` | 下载/离线提取固定上游安装器、内嵌EFI和Shell，校验后本地准备 |
| `Get-TracePayload.ps1` | 固定RefindPlus DEBUG准备；不带可选驱动或清理工具 |
| `reference/startup.nsh` | 成功Shell链的通用标记版，部署前须对照已有标记；本机原脚本未被此文件覆盖 |
| `diagnostic-loader/config.template.conf` | 8秒文字菜单、Shell和Windows恢复两个入口，ESP占位符由本机生成 |
| `tests/*.ps1` | 13项启动/日志范围保护测试，9项新鲜度及最终硬件判断测试 |

固定来源：

- [原解锁工具3.1.2-win](https://github.com/PZH1gdmu/CMP40HX-Unlock/releases/tag/3.1.2-win)，MIT项目。ZIP SHA256：`BDC5A57385D63135D05B04134C616AE05EABDC675409E8FB1162269899D60EAC`。
- 安装器SHA256：`74B1265260F266F34853192A640E0D3547F147E0FBCF5280783E6D4F59D71F79`。成功路径的内嵌EFI位于偏移3396544，长度586260字节，提取后必须再校验；不执行安装器来完成提取。
- 成功原EFI SHA256：`F0D7CA1EABAB01C4410459C078B84CF3B150DA5AFECCBD73965E03D9C2AE7230`。同发布包外置EFI为`EE251566F46CBD395987629CE614DA2536E1A61FE95ABE1697F6E095A142E5FE`，两者不能混为一谈；新外置版没有在这条成功链中验证。
- [EDK2 Shell 26H1](https://github.com/pbatard/UEFI-Shell/releases/tag/26H1)，基于edk2-stable202602，BSD-2-Clause-Patent。Shell SHA256：`4EA080DDD576117CD04F5C02D16712EA5D9249C0752214D8E4055E460D7B11E0`。
- [RefindPlus v0.14.2.AE](https://github.com/RefindPlusRepo/RefindPlus/releases/tag/v0.14.2.AE)，2026-04-14，GPL-3.0-or-later。ZIP SHA256：`D60E6157FA1D7BDB7E14FFAFA77B2CD8F99C5DED8B08B1732D6B5F4913D4EE89`；DEBUG EFI：`6E829EC28E06304DBB2D7A1235CE276E71C181D6EE433588C089F70AE6F43F5D`。

本机实际原startup.nsh SHA256为 `BC808503D9CD4999B7B6E4DD4D4F0E578E625FB97373A0050D158B9A1263E73A`。公开reference版本更换了机器标记名，哈希自然不同，不可把它当成本机ESP原始字节副本。

RefindPlus许可证/INFO和EDK2许可证随本目录保留。上游fork已有文件继续保留其许可证。新目录不重新发布微软引导、驱动、显卡固件或私有原始备份；准备脚本让维护者从固定上游取得同一组文件。生成的二进制、机器profile、运行日志被忽略，不应提交到公开fork。
