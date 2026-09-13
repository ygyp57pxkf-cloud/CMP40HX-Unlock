# Sunshine / 40HX虚拟1080p144Hz

2026-09-13本机主机端实测通过：Sunshine2026.516.143833，MikeTheTech VDD11.30.4.434，RainCandy616.56。VDD由Intel P630改绑40HX后，DXGI在40HX下出现1920×1080输出，Windows实际模式144Hz；Sunshine成功创建h264_nvenc与hevc_nvenc。Sunshine使用ensure_active，不通过ensure_only_display禁用其他屏幕。

此结果更新了此前“40HX可能无法NVENC”的旧记录：当前驱动/解锁/虚拟显示组合已实测编码器可用。但这不等于其他驱动版本也兼容，或已经验证网络端稳定144FPS；Sunshine启动时的编码器探测使用60fps，客户端实流另验。

## 本轮修正

- SunshineService由Manual设为Automatic并回读，当前Running。开机服务自启已配置，下次真实开机仍需验证驱动与虚拟屏初始化顺序。
- VDD `C:\VirtualDisplayDriver\vdd_settings.xml` 的 `gpu/friendlyname` 改成实际DXGI名称 `NVIDIA CMP 40HX (RainCandy Technology)`；最终只提供1920×1080@144Hz；只重载该VDD设备，不重置40HX。最初同时保留120/144时曾在后续枚举中回到120，Sunshine期间无新串流日志，具体外部触发者未确认。因此取消旧120模式，复核枚举列表仅144Hz、实际模式144Hz。
- Sunshine原配置指向40HX，但VDD原先绑定Intel，造成“找不到输出/编码器”。统一GPU后恢复。
- `dd_manual_resolution=1920x1080`、`dd_manual_refresh_rate=144`、`dd_configuration_option=ensure_active`，使用本机实际虚拟显示器device_id作为output_name。ensure_active保留其他显示器；原ensure_only_display会禁用它们。
- 备份后移出陈旧的display_device.state（800×600@120恢复记录），让Sunshine重新记录有效状态；未改sunshine_state.json中的配对/认证信息，也未更改端口、防火墙或管理界面访问范围。
- 配置重新写为UTF8无BOM，清理重复乱码locale键。

示例片段（不是可直接复制的完整本机配置）：

```ini
adapter_name = NVIDIA CMP 40HX (RainCandy Technology)
encoder = nvenc
output_name = <Sunshine列出的实际虚拟屏device_id>
dd_configuration_option = ensure_active
dd_resolution_option = manual
dd_manual_resolution = 1920x1080
dd_refresh_rate_option = manual
dd_manual_refresh_rate = 144
```

Moonlight选择1920×1080、144 FPS，优先HEVC，启用客户端支持的“优化游戏设置”以允许Sunshine应用手动分辨率。客户端显示器需支持目标刷新率；实际验收记录接收帧率、编码/解码延时、丢帧、网络抖动与持续负载。不要把桌面144Hz或NVENC创建成功直接当作144帧串流完成。

本机恢复文件保存在本地 `outputs/sunshine-20260913`：原Sunshine配置、VDD XML、旧显示恢复状态和显示模式快照。恢复须先停止Sunshine、恢复配置并只重载对应VDD，再启动服务；保持服务Auto。不要导入别人的显示GUID、音频设备ID、配对密钥或物理屏拓扑。

参考：[Sunshine官方配置](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)、[Virtual Display Driver官方项目](https://github.com/VirtualDrivers/Virtual-Display-Driver)。本轮没有更换Sunshine或VDD版本。
