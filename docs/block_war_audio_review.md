# UI 与技能音效审查 · 2026-09-26

本轮按用户反馈优先处理 UI 交互和技能。交战音效不重做；补齐炮弹实际命中这一缺失触发点。共修改 17 类声音、25 个 WAV，保留其余 19 个积木战争 WAV 的哈希。

## 设计依据与问题

- Iain McGregor，[*How the Brain Decides What to Listen To*](https://www.asoundeffect.com/sound-design-listening/)：声音的起始提示和时机决定玩家如何理解操作；少量适当元素即可建立清楚的反馈。此次将高频 UI 操作和较长的确认提示分开，不再让多数操作都是木头、锁扣与石块的重叠敲击。
- Iain McGregor，[*Beyond chimes and whooshes: Extending the sound of magic*](https://www.asoundeffect.com/sounds-of-magic/)：魔法声音应从所属世界的物体、动作和生命周期出发。本轮让封条对应纸张、召回对应口哨、兔洞对应地面翻动，防护罩对应通透魔法尾音，火攻对应起火与燃烧。
- Godot [Audio streams](https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html)、[Importing audio samples](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html)：短促、重复声音使用 WAV；非空间菜单声和空间技能声分别由原生播放器承担；菜单变体使用 `AudioStreamRandomizer`，限制复音数。

旧版兔子四技能借用了战鼓、改建、征召、脚步事件。兔洞甚至可能被正在播放的行军声限频吞掉。炮弹落点缺少音频请求；大厅、选地图、设置菜单没有对应反馈；技能拖起和无效落点取消也缺失。以上触发点已接入对应事件，不增加技能逻辑前摇。

## 全部变更与试听

以下每个播放器包含该事件的**全部最终变体**，变体之间留 0.28 秒间隔。单个变体不加前导空白，不叠加背景音乐，不为试听额外提亮或增大音量。游戏播放时仍受总音量、事件增益和空间距离控制。

| 事件 | 修改与触发 | 完整变体试听 |
| --- | --- | --- |
| 选择 | 用短菜单提示替换木头加金属锁扣；用于建筑、地图、指挥官与普通菜单按钮 | [播放](audio/block_war/select.wav) |
| 拖起／拖选 | 纸张翻动；技能按下时立即反馈 | [播放](audio/block_war/drag.wav) |
| 比例／滑条 | 短菜单音；滑条最多每 0.1 秒响一次，程序恢复设置不响 | [播放](audio/block_war/ratio.wav) |
| 派兵／确认 | 保留完整短音尾的菜单确认；开始游戏和重开也使用 | [播放](audio/block_war/order.wav) |
| 无法操作 | 明确的下行提示，替换两下低木敲击 | [播放](audio/block_war/denied.wav) |
| 取消／返回 | 更短、更轻的返回提示；包括右键取消与无效技能落点 | [播放](audio/block_war/cancel.wav) |
| 暂停 | 翻开书册的短纸张声 | [播放](audio/block_war/pause.wav) |
| 继续 | 合上书册的短收束声 | [播放](audio/block_war/resume.wav) |
| 松鼠 Q | 现成暖色道具提示音，替换重敲与脚步拼层 | [播放](audio/block_war/skill_command.wav) |
| 松鼠 W | 现成战鼓片段，替换木块降调模拟的鼓卷 | [播放](audio/block_war/skill_drum.wav) |
| 松鼠 E | 清亮起音和魔法尾音，替换石块与金属装甲锁合 | [播放](audio/block_war/skill_shield.wav) |
| 松鼠 R | 即时起火、风压与燃烧尾音，替换延后出现的碎石冲击 | [播放](audio/block_war/skill_breach.wav) |
| 兔子 Q | 风声加短纸张扑动，使用独立事件 | [播放](audio/block_war/rabbit_dash.wav) |
| 兔子 W | 纸张落下与纸页短响，使用独立事件 | [播放](audio/block_war/rabbit_seal.wav) |
| 兔子 E | 独立口哨音，施法当帧触发 | [播放](audio/block_war/rabbit_recall.wav) |
| 兔子 R | 土石翻动与柔和落地声，位于实际出口；独立于脚步限频 | [播放](audio/block_war/rabbit_burrow.wav) |
| 炮弹命中 | 柔和受击加少量装备碰撞，在实际碰撞位置触发，有并发上限 | [播放](audio/block_war/projectile_hit.wav) |

保留原有行军、交战、炮台发射、施工起止、占领、失守、增援和胜负提示。此次不将普通悬停变成连续响声，也不在整段技能持续时间中反复播放施法提示。

## 来源与授权

实际使用 Kenney RPG Audio、rubberduck 80 CC0 RPG SFX、William Hector 的 CC0 素材，以及 David McKee / ViRiX、dklon 的 CC BY 3.0 素材。均根据原始发布页核实商业使用、修改和再分发许可。作者、发布页、许可全文、原件与成品哈希、修改说明见 [完整署名与授权](../assets/audio/CREDITS.md) 和 [来源清单](../assets/audio/sources.json)。

## 验证与复现

本轮验证结果：原生混音 68 项、音效触发 28 项、输入回归 25 项、兔子技能集成 92 项，共 213 项通过。技能测试显式补满测试双方的技力，避免依赖当前 30 点的开局设定；实战初始技力不变。1280×720 私有桌面截图确认帮助页署名未超出面板。

原生混音检查所有 26 类事件的实际 Master 输出、44 个导入变体、暂停、静音、频率限制和退出释放。输入专项通过真实 Godot 输入验证技能拖起、松手、右键取消、无效落点、帮助页、地图选择、设置滑条与跨场景确认；核对兔洞出口位置与炮弹命中时机。音色是否符合个人喜好应以这里的直接试听与游戏体验判断，数值检查不代替听感。

资源审查逐个校验 48 kHz 单声道 PCM16、非静音、首尾归零、真峰值、起音、原始音源哈希和许可。新声音的起音检查使用相对峰值 2% 阈值，要求 25 毫秒以内；这只是音频文件的起音，不是声卡端到端延迟。指标和试听时间表保存在 [review.json](audio/block_war/review.json)。

```powershell
python tools/build_war_audio.py
python tools/build_war_audio_review.py
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --script tests/block_war_audio_feedback_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --script tests/block_war_audio_mix_test.gd
```

所有验证使用 Dummy 音频输出或私有 Windows 桌面，不激活窗口、不发送系统输入、不通过用户扬声器自动播放。
