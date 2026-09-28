# 角色技能释放音效：2026-09-28

熊和青蛙原来并非完全没有调用声音，而是八个技能复用了施工、战鼓、护盾、封条及炮弹命中音。它们缺少自己的辨识度，且同一事件的全局间隔、单实例限制可能吞掉另一个阵营紧接着释放的声音。本次为八个技能分别制作并接入独立音效。

沿用此前 [《文明 VII》音频团队的重复耐受性与信号强度经验](https://www.asoundeffect.com/civilization-vii-game-audio/)：简短、材料有意义、不要靠堆叠音调和长尾音表现技能。每个新声音最多两种材料；全程静音制作与验证，没有扬声器播放或操作用户桌面。下面是设计意图和客观测量，主观听感留给玩家通过逐项试听判断。

## 新声音

| 角色／技能 | 设计 | 时长 | 默认混音 50 ms RMS | 真峰值 | 试听 |
| --- | --- | --- | --- | --- | --- |
| 熊 Q 工具箱 | 单次木锤轻敲、短扣合，表达立即完工 | 0.32 s | -29.93 dBFS | -17.88 dBTP | [试听](audio/commanders/bear_toolbox.wav) |
| 熊 W 重重跺脚 | 沉稳的落地声、短碎石尾声 | 0.52 s | -29.13 dBFS | -15.44 dBTP | [试听](audio/commanders/bear_stomp.wav) |
| 熊 E 链式防守 | 链条迅速收紧、接头扣住 | 0.40 s | -28.40 dBFS | -12.51 dBTP | [试听](audio/commanders/bear_link.wav) |
| 熊 R 不落堡垒 | 厚木盾接触、很短的低铃共振 | 0.72 s | -28.66 dBFS | -16.89 dBTP | [试听](audio/commanders/bear_ward.wav) |
| 青蛙 Q 弱化雾气 | 一口轻雾散开，带少量湿润质感 | 0.44 s | -29.39 dBFS | -13.82 dBTP | [试听](audio/commanders/frog_mist.wav) |
| 青蛙 W 浮力薄隔 | 圆润的湿泡声、轻托起的布料气流 | 0.46 s | -27.15 dBFS | -12.71 dBTP | [试听](audio/commanders/frog_float.wav) |
| 青蛙 E 隐身 | 很轻的擦过声，迅速消散 | 0.32 s | -30.90 dBFS | -15.26 dBTP | [试听](audio/commanders/frog_cloak.wav) |
| 青蛙 R 致命打击 | 切过与短钝击同时出现，贴合瞬间切痕 | 0.38 s | -27.37 dBFS | -17.58 dBTP | [试听](audio/commanders/frog_strike.wav) |

这些是 CC0 音源剪辑，具体来源及修改说明见 [音效署名](../assets/audio/CREDITS.md)。没有把第三方成品声或拟音冒称原创录音。隐身和雾气只在释放处响一次，没有持续跟随部队的声音。熊法术球的实际命中仍使用既有命中音；大招释放使用新的堡垒音。

## 触发与音量

- 玩家和 AI 从同一条成功施法路径立即播放；拖起、取消、无效目标、空目标和冷却拒绝不播放技能成功声。
- 四个角色的 16 个技能事件取消跨阵营的毫秒间隔，共享每类最多 6 声的限制；仍使用既有 24 个 Combat 原生声道、优先级和距离衰减。法术由各阵营的游戏冷却限制，密集行军及交战仍维持原限流。
- 大招优先级高于普通技能；不会被普通交战声占满池子而轻易挤掉。新素材不循环，不更改 BGM、音量默认值或总线处理。
- 八个新 PCM 起音均为 0.46～1.06 ms（峰值 2% 阈值）；这是素材起音，不代表系统从输入到扬声器的延迟。4 ms 能量窗口裁去了布料和湿泡素材的弱起音。
- 试听为 Godot 4.6.3 原生输出：听者 `(0,6,0)`，释放处 `(8,0,0)`；已含空间衰减、Combat 压缩和默认 Master 50%。每个文件重复两次，中间间隔 0.45 秒，没有为试听另作归一化。原生混音为 44.1 kHz，音源为 48 kHz。

## 验证

`tests/block_war_commander_audio_test.gd`：123 项通过，包括四个角色的真实按住／松开施法、取消、冷却拒绝、声音空间位置、熊和青蛙各四个 AI 决策，以及同类技能六次同时释放和过量请求上限。

`tests/block_war_audio_mix_test.gd`：88 项通过，包含 52 个战役变体的导入和真实输出、38 个原生声音节点、距离衰减、增益、静音、暂停与释放。同步修正了一个仍引用已迁出产品的旧 `select` 事件的过时检查，改为验证现存共享炮台事件。

现有 `tests/block_war_audio_feedback_test.gd` 的 39 项检查同样通过，覆盖兔洞后续开口、炮弹命中、取消与菜单切换；上述三组共 250 项通过。

`tests/block_war_commander_audio_capture.gd` + `tools/review_commander_audio.py`：15 段原生采样，没有缓冲丢帧。正常 BGM 和交战混音中八个新技能均触发；默认混音真峰值 -11.97 dBTP。总音量 100% 的六个堡垒同时释放与交战叠加，真峰值 -2.68 dBTP，没有触及 Master 限幅阈值。屏幕边缘 43 米处的隐身释放为 -34.08 dBFS（50 ms RMS），随距离自然减弱。

逐个哈希核对原有 44 个战役 WAV、已批准的点击、两首 BGM 和总线配置均未改变。完整记录：[measurements.json](audio/commanders/measurements.json)。无头环境报告的系统证书读取限制不影响本地音频资源和检查结果。

```powershell
python tools/build_war_audio.py --new-commanders
# Godot 完成新音源导入后，使用 Dummy 音频驱动：
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --script res://tests/block_war_commander_audio_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --script res://tests/block_war_commander_audio_capture.gd -- --output=res://.local/commander-audio/native
python tools/review_commander_audio.py .local/commander-audio/native
```
