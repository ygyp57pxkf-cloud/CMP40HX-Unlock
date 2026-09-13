# CMP40HX-Unlock：自动双解锁与启动稳定性整改

本仓库 fork 自 [PZH1gdmu/CMP40HX-Unlock](https://github.com/PZH1gdmu/CMP40HX-Unlock)，保留上游源码与许可证，并补充实际完成的自动启动、日志判定、恢复及串流方案。

**2026-09-13 实机已确认自动启动完成算力解锁＋PCIe Gen2×16，且40HX绑定的1080p144Hz虚拟屏已被Sunshine/NVENC识别。** 连续冷启动/WOL与Moonlight端稳定144 FPS仍需继续验收。

- **[完整自动解锁方案入口](automatic-boot/README.md)**
- [完整操作步骤](automatic-boot/SETUP.md) · [文件与来源](automatic-boot/FILES.md)
- [问题、失败与成功记录](automatic-boot/CASE-STUDY.md) · [无法启动如何恢复](automatic-boot/RECOVERY.md)
- [Sunshine自启、40HX虚拟1080p144Hz串流](automatic-boot/STREAMING.md)
- [每周上游更新跟进](automatic-boot/UPSTREAM-TRACKING.md)
- [上游原始说明](UPSTREAM_README.md)

新工具使用独立启动目录与原生EFI入口，保留微软恢复；新采集器只读，不加载底层驱动、不执行PnP或Gen2。机器配置由本地导出，公开仓库不带私人启动变量、日志或配对信息。上游GUI/安装器exe未重编，不能把旧exe中的提示当作已内置本fork整改。