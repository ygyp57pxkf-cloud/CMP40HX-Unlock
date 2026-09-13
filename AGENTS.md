# Fork维护边界

- 本fork在上游源码基础上维护automatic-boot方案；原README保存在UPSTREAM_README.md，原LICENSE继续适用。上游来源和基线见automatic-boot/UPSTREAM-TRACKING.md。
- 当前已确认2026-09-13自动Trace→Shell→connect→30秒→EFI→Windows双解锁，以及40HX虚拟1080p144Hz/NVENC主机端可用；连续启动和客户端144FPS验收未完成。
- 公开参数化工具经过测试和只读本机验证，未再次写入成功机器的固件；不能说公开版在所有机器完整实测。
- 不提交profile.local.json、ESP/BCD/NVRAM转储、原始系统日志、用户名/SID、配对信息、机器显示/音频ID或下载的二进制。只提交明确白名单源码、模板、脱敏案例、许可证。
- 不根据旧EFI日志断定GSP覆盖，不根据SMI Gen1重复重训；原Gen2操作入口保持唯一，采集只读。
- 用户未要求自动重启、刷固件或自动合并上游；更新检查仅在相关变化时通知。禁止子代理和superpowers技能，除非用户新授权。
