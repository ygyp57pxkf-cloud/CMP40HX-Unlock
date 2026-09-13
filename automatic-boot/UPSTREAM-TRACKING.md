# 上游更新维护

本fork基于 `PZH1gdmu/CMP40HX-Unlock` 主分支提交 `876825bd1405f47fed2ea3b542ea748bf0257d4a`。解锁载荷取固定Release `3.1.2-win`，Shell为`26H1`，RefindPlus为`v0.14.2.AE`；源码主分支版本标签与Release并不相同，更新时分别比较。

用户已设定每周一10:00（Asia/Hong_Kong）在原Codex任务检查上游解锁项目、RefindPlus和本fork。仅当发现与自动EFI/Shell、Code43、GSP/SS0、Gen2、启动兼容性相关的修复/回归/安全问题或需要验证的变化时通知；无变化不发送例行消息。该提醒依赖Codex自动任务实际可运行，不是GitHub服务端已部署的自动升级器。

每次检查先读本文件和CASE-STUDY，比较Releases、相关Issues/PR与上次记录。通知附来源、适用条件、与本机现状的区别和最小验证建议。不要自动同步覆盖fork整改，不自动安装驱动、替换EFI、刷固件或重启。

更新需保留Windows恢复及当前工作文件，固定新版本来源和哈希，在独立目录准备后再决定测试。新版声称解决相关问题时，重新验证旧延时/参数是否必要；不因“最新版本”直接替换已成功载荷。
