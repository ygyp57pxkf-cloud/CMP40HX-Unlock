# 失败、成功与仍待解释的细节

平台：ASUS CMP40HX/TU106，JGINYUE H311M-HD3/AMI5.12，驱动RainCandy616.56，Windows11。以下为同一机器的历史与本轮实测，不是所有40HX的共同结论。

| 时间/方式 | 关键证据 | 判断 |
|---|---|---|
| 09-08 原直启尝试 | EFI booter失败、SS0=0、Code43 | 文件重新复制或Windows设备重置没有证明可解决EFI前置失败 |
| 09-11 自动直启 | mbox0=91/HALT，最终SS0=0；无Shell新日志 | 不能声称30秒已运行后无效 |
| 09-11 23:23 手选Shell | connect成功、等待30秒、首次booter成功；Windows SS0=88888888，原始Gen2×16 | 同一原EFI/Shell文件具备成功条件，手选仅作为诊断 |
| 09-11 23:56 普通冷启动 | 默认仍Windows，Shell/EFI都是旧日志；仅Gen2 | 上次手选对下一次普通开机不具有持久效力 |
| 09-12 自动启动 | 00:08和09:28有新Shell/等待/EFI成功；另有一次旧直启失败 | 自动流程可以成功，但间歇性问题仍在 |
| 09-13 09:40/09:43 | Shell日志停在前日，原EFI新失败，Code43 | 在Windows前已经失败；不能直接归咎Windows驱动 |
| 09-13 10:24 参数对照 | Shell第一、Windows第二；本次无新Shell/EFI，Code0但算力锁定 | 安全回退有效；新增Shell参数没有取得脚本执行证据 |
| 09-13 12:10 Trace自动 | 日志明确Menu Timeout Expired 8s → Shell；connect=0；12:09:53至12:10:23等待30秒；EFI首次mbox0=0 | 新前置入口确实自动运行，启动链跑通 |
| 09-13 12:18 Windows诊断 | SS0=88888888、SS1=8、SS0_READOUT=0、LNKSTA=1102、Code0 | 本轮双解锁确认；GSP设备级1仍开启 |

## 具体问题及整改

1. **默认入口与临时选择混淆。** BootCurrent只说明最终启动项，未必能排除某应用先加载后退出。必须读回BootOrder/BootNext并结合本轮Trace/Shell日志；新Trace日志已确认TIMEOUT自动选择。
2. **Shell无日志时盲加延时。** 失败轮次根本没有脚本新证据；把等待加长无法解决未到达等待阶段的问题。独立DEBUG管理器提供更早的加载记录。为什么原主板有时跳过/早退Shell仍未取得确定返回码，成功绕过不等于已经证明内部根因。
3. **回退落到旧直启EFI。** 原顺序Shell→旧EFI→Windows可能让失败路径继续进入已知booter失败。调整成Trace→Windows→其余原项，保留恢复。
4. **Windows型启动项的OptionalData。** 复制bootmgr再直接改原始附加数据曾导致BCD重建旧映射。整改使用新的原生EFI load option并核对原始字节，避免反复增殖启动项。
5. **旧日志误判GSP覆盖。** 只有本轮EFI成功而同轮Windows读回锁定，才值得调查驱动接管；仍不能单凭两者差异证明GSP因果。本次GSP开启仍成功，不能把关GSP设为通用步骤。
6. **Gen2期间审计过早。** 12:11第一份审计Code0但SMI不可通信，稍后驱动可用，12:18原始寄存器已Gen2。新增只读等待和分阶段记录；没有重复PnP。原安装器当轮日志仍报句柄重开失败并安排重试，后续任务记录不足以证明最终Gen2由哪一子步骤完成，这项可观测性仍待改进。
7. **NVML与原始PCI报告冲突。** 本机SMI仍可显示Gen1，但40HXCheck原始LNKSTA=1102；不能仅凭SMI发起反复重训。按原始链路、负载与实际数据正确性共同验收。
8. **发行包内嵌/外置EFI不一致。** 固定真实成功文件并提供可复现提取，不能以同一版本标签推定二进制相同。
9. **底层驱动瞬态与检查副作用。** 原40HXCheck必要时临时拉起ThrottleStop/WinRing0然后清理；不能把它显示的运行状态当成已长期安装。本fork采集器不加载这些驱动，Windows SS0由指定诊断报告提供。

## 调查过但本轮未采用的方向

- [上游Issue33](https://github.com/PZH1gdmu/CMP40HX-Unlock/issues/33#issuecomment-5602401507)、[Issue44](https://github.com/PZH1gdmu/CMP40HX-Unlock/issues/44#issuecomment-5603670261)：存在手选EFI成功反馈，作为路径线索。
- [OnlyEFI社区分支](https://github.com/BardKing-CN/CMP40HX-Unlock-OnlyEFI/releases/tag/0.1.DEV)：有独立实现/反馈，未替换本机已成功载荷。
- [Cyridd原始研究](https://github.com/Cyridd/cmpunlocker/tree/9edb0f538d6d04f31426f4bfccc5d8499f854983)：解释算力/PCIe机制，不代表刷vBIOS能解决本机问题。此前读出的全零ROM窗口不是有效vBIOS备份。
- 未执行DDU、刷vBIOS、刷主板、关闭安全组件或更多驱动注入。保留工作配置，后续更新按单变量和可恢复方式验证。

尚待：重复启动稳定性、无人登录Gen2、DEBUG长期日志空间、上游Gen2恢复任务的准确结局、Moonlight实际144FPS串流。历史短CUDA/H2D通过只支持当轮可用，不能当长期满血性能验收。
