# 猪猪技能音效验收（2026-09-30）

原来的猪猪有声音，但借用兔子冲刺、青蛙浮力、通用军令和熊跺脚。本次为四个技能制作五段独立拟音，统一接入现有 Godot 原生空间音频池、Combat 总线和音量设置。

| 技能／事件 | 声音设计 | 时长 | 原生混音最高 50ms RMS | 原生混音真峰值 |
| --- | --- | --- | --- | --- |
| Q 猪冲锋 | 短皮革蓄力，接三次加速蹄状木接触 | 0.48 秒 | −29.65 dBFS | −17.03 dBTP |
| W 猪会飞 | 两次轻羽扫动，后一次略微上扬；柔和起音 | 0.54 秒 | −28.72 dBFS | −14.48 dBTP |
| E 猪整队 | 三组成对接触逐渐收紧，最后合拢 | 0.43 秒 | −29.81 dBFS | −19.10 dBTP |
| R 下降 | 渐近的羽毛气流，音轨中没有预置撞击 | 0.65 秒 | −29.89 dBFS | −14.54 dBTP |
| R 落地 | 低沉软撞，35 毫秒后接少量碎石 | 0.62 秒 | −25.71 dBFS | −19.23 dBTP |

以上混音数据来自原生空间播放器、现有总线与默认主音量 50%，保留空间衰减；源素材为 48 kHz 单声道 PCM16，采集设备混音为 44.1 kHz 双声道。试听没有另外归一化或放大。

## 许可和复现

全部七个源采样均为 CC0 1.0，可商用、修改及再分发：

- [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds)：木质接触和柔软重击。
- [Vehicle / Jan Schupke — Fantasy Weapons and Apparel SFX Library](https://opengameart.org/content/fantasy-weapons-and-apparel-sfx-library)：皮革和羽毛动作。
- [rubberduck — 80 CC0 RPG SFX](https://opengameart.org/content/80-cc0-rpg-sfx)：碎石。

已重新下载三个作者原始包，并核对包 SHA-256 及七个源文件的逐字节一致性。[音源核验记录](../assets/audio/sources/PIG_SKILL_SOURCES.md)、[游戏内随包说明](../assets/audio/CREDITS.md)、[CC0 全文](../assets/audio/licenses/CC0-1.0.txt)和[处理配方与哈希清单](../assets/audio/block_war/audio_manifest.json)均已保留。这些是拟音，没有使用或宣称使用真实猪叫。

`python tools/build_war_audio.py --pig` 可单独重建五个声音。核对基线 `6bd22da` 后，原有 56 个战役 WAV、点击声、两首 BGM 和总线文件均保持字节一致。

## 触发与边界

- Q/W/E 只在有效施法成功时请求各自的空间声音。拖起预览、右键取消、无效目标、冷却拒绝、重复准备均不播放成功音。
- R 在施法时播放下降气流，实际伤害结算时请求独立落地音。0.649 秒时未触发；暂停冻结计时，恢复越过 0.650 秒边界后只触发一次。
- 主机和客户端共用猪猪的声音映射；重复输入、重复事务不会重复播放。下落途中及落地后重连快照恢复状态时，不补播历史音效。
- 飞行、悬浮和隐身队伍不产生地面脚步；恢复普通地面行军后脚步正常。

## 验证结果

- `tests/block_war_pig_audio_test.gd`：55 项通过。包含原生鼠标操作、暂停边界、脚步和经过序列化传输的双端声音行为。
- `tests/block_war_audio_mix_test.gd`：106 项通过。61 个战役 WAV 均加载，五个新事件进入真实混音，静音、暂停和销毁释放检查通过。
- `tests/block_war_pig_audio_capture.gd`：9 段原生实时采集，录音期间零丢帧。未录制的场景加载期间，两条采集缓冲各丢弃 33280 帧，在报告中单独记录，不计入录音。
- 实际 R 的模拟落地时刻为 0.650 秒，本次录音墙钟为 0.654 秒；释放和落地事件各一次。
- 默认战斗混音真峰值 −11.35 dBTP；主音量 100%、六次重击同时叠加并含战斗/BGM 的压力片段真峰值 −3.06 dBTP，未削波。远处冲锋的 50ms RMS 比近处降低 2.17 dB。
- 临时导出 PCK 中五份音效均为 48 kHz 单声道 PCM16、无循环，并包含音效说明和完整 CC0 许可。此检查只核实音频资源打包，不作为独立发布包交付。

完整数据见 [measurements.json](audio/pig/measurements.json)。本次验收为真实引擎采集、客观响度和行为检查，未进行人工听感验收；可用下面的原生音量录音检查音色。

## 试听

[按 Q、W、E、R 顺序试听](audio/pig/pig_skills_preview.wav)。R 片段来自实际对局时序，包含下降与落地。

单独片段：[猪冲锋](audio/pig/pig_charge.wav)、[猪会飞](audio/pig/pig_fly.wav)、[猪整队](audio/pig/pig_formation.wav)、[下降](audio/pig/pig_drop.wav)、[落地](audio/pig/pig_impact.wav)。

测量与试听可由 `python tools/review_pig_audio.py .local/pig-audio/capture --reference 6bd22da` 重建。

## 发布范围

本次更新本地项目及 Git 仓库，不重启东京中继。网络内容清单随本次提交从 Git 索引生成；当前中继严格比较内容哈希，因此发布此版客户端供公网联机前，需要同步同一版本的中继内容清单。
