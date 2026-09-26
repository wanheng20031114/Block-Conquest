# UI 与技能音效审查

**最新：** [2026-09-27 全部响度校准与 Godot 原生混音试听](block_war_audio_loudness.md)。以下保留音色设计与上一轮试听的历史记录；最终播放层次和验收数据以最新校准为准。

2026-09-26 按用户反馈优先处理 UI 交互和技能，并补齐炮弹实际命中。该轮修改 17 类声音、25 个 WAV，保留其余 19 个积木战争 WAV 的哈希。

## 2026-09-27：交互收简

- 派兵线从按下到拖动均保持安静，经过建筑、调整派兵比例、取消拖动也不响；成功松手只响一次 0.16 秒的干木块接触声。使用 Kenney 的 CC0 木材音源，没有取用 Minecraft 原音频。
- 单独点选建筑时播放 0.08 秒的轻 `ta`。己方建筑在松手确认点选时响，避免按下后转为派兵拖动时提前出声。
- 技能拖起改为更轻的 0.09 秒单次轻敲。
- 菜单点击使用 arc-nice 的原始 0.115 秒 WAV，字节一致，不裁剪或叠层，播放器沿用 -8 dB。

本轮修改 6 个战场交互 WAV，保留其余 38 个战场 WAV；另加入 1 个原样复用的菜单 WAV。来源、哈希与原项目参数见 [完整记录](../assets/audio/CREDITS.md)。本轮四项试听带入事件或播放器增益，不带入用户可调的 Master 音量。两个变体在试听中间隔播放，游戏里每次操作只选择其中一个。

9 月 27 日验证：音效触发 35 项、原生输入 25 项、原生混音 68 项，共 128 项通过。新增检查覆盖按下派兵起点静音、跨建筑拉线与调比例静音、有效松手只响一次、单独点选的轻敲、取消后的释放不派兵，以及菜单使用 arc-nice 原文件与原播放器增益。

## 兔子技能改版后的触发时机

E 现在向地面半径 6 米内所有阵营的露天部队吹哨，施法声在地面落点当帧播放，各部队返回各自原始来源。R 松手时在所选己方建筑播放待命提示，只给予 15 秒一次性增益；下次有效派兵才开始掘地，0.25—1.2 秒后在实际出口播放出洞声。取消或无效派兵不会消耗待命，也不触发出口声；待命过期不播放出洞声。出洞仍每 0.16 秒最多一排 6 人，不为每名士兵重复播放整段技能音效。下方历史验收数量与旧版试听只说明当时版本，不作为此流程的验证结论。

## 设计依据与问题

- Iain McGregor，[*How the Brain Decides What to Listen To*](https://www.asoundeffect.com/sound-design-listening/)：声音的起始提示和时机决定玩家如何理解操作；少量适当元素即可建立清楚的反馈。此次将高频 UI 操作和较长的确认提示分开，不再让多数操作都是木头、锁扣与石块的重叠敲击。
- Iain McGregor，[*Beyond chimes and whooshes: Extending the sound of magic*](https://www.asoundeffect.com/sounds-of-magic/)：魔法声音应从所属世界的物体、动作和生命周期出发。本轮让封条对应纸张、召回对应口哨、兔洞对应地面翻动，防护罩对应通透魔法尾音，火攻对应起火与燃烧。
- Godot [Audio streams](https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html)、[Importing audio samples](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html)：短促、重复声音使用 WAV；非空间菜单声和空间技能声分别由原生播放器承担；菜单变体使用 `AudioStreamRandomizer`，限制复音数。

旧版兔子四技能借用了战鼓、改建、征召、脚步事件。兔洞甚至可能被正在播放的行军声限频吞掉。炮弹落点缺少音频请求；大厅、选地图、设置菜单没有对应反馈；技能拖起和无效落点取消也缺失。以上触发点已接入对应事件，不增加技能逻辑前摇。

## 全部变更与试听

以下每个播放器包含该事件的**全部最终变体**，变体之间留 0.28 秒间隔。单个变体不加前导空白，不叠加背景音乐。9 月 27 日更新的四项试听包含各自的播放器增益，其余保留源文件音量；游戏播放还受总音量和空间距离控制。

| 事件 | 修改与触发 | 完整变体试听 |
| --- | --- | --- |
| 建筑选择 | 0.08 秒的轻木敲，低存在感 | [播放](audio/block_war/select.wav) |
| 菜单选择／点击 | arc-nice 原点击音，沿用 -8 dB 播放增益 | [播放](audio/block_war/ui_click.wav) |
| 技能拖起 | 0.09 秒单次轻敲；派兵拉线保持安静 | [播放](audio/block_war/drag.wav) |
| 比例／滑条 | 短菜单音；滑条最多每 0.1 秒响一次，程序恢复设置不响 | [播放](audio/block_war/ratio.wav) |
| 派兵／确认 | 0.16 秒单次干木块接触；成功松手才响，开始游戏和重开也使用 | [播放](audio/block_war/order.wav) |
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
| 兔子 E | 独立口哨音，在地面施法落点当帧触发 | [播放](audio/block_war/rabbit_recall.wav) |
| 兔子 R | 来源建筑获得待命时提示；有效派兵掘地完成后，在实际出口播放土石翻动与柔和落地声；独立于脚步限频 | [播放](audio/block_war/rabbit_burrow.wav) |
| 炮弹命中 | 柔和受击加少量装备碰撞，在实际碰撞位置触发，有并发上限 | [播放](audio/block_war/projectile_hit.wav) |

保留原有行军、交战、炮台发射、施工起止、占领、失守、增援和胜负提示。此次不将普通悬停变成连续响声，也不在整段技能持续时间中反复播放施法提示。

## 来源与授权

实际使用 Kenney RPG Audio、rubberduck 80 CC0 RPG SFX、William Hector 的 CC0 素材，以及 David McKee / ViRiX、dklon 的 CC BY 3.0 素材。均根据原始发布页核实商业使用、修改和再分发许可。作者、发布页、许可全文、原件与成品哈希、修改说明见 [完整署名与授权](../assets/audio/CREDITS.md) 和 [来源清单](../assets/audio/sources.json)。

## 验证与复现

历史验证结果（早于兔子 E/R 改版）：原生混音 68 项、音效触发 28 项、输入回归 25 项、兔子技能集成 92 项，共 213 项通过。技能测试显式补满测试双方的技力，避免依赖当前 30 点的开局设定；实战初始技力不变。1280×720 私有桌面截图确认帮助页署名未超出面板。

原生混音检查所有 26 类事件的实际 Master 输出、44 个导入变体、暂停、静音、频率限制和退出释放。输入专项通过真实 Godot 输入验证技能拖起、松手、右键取消、无效落点、帮助页、地图选择、设置滑条与跨场景确认；核对兔洞出口位置与炮弹命中时机。音色是否符合个人喜好应以这里的直接试听与游戏体验判断，数值检查不代替听感。

资源审查逐个校验战场音效的 48 kHz 单声道 PCM16、非静音、首尾归零、真峰值、起音、原始音源哈希和许可；arc-nice 点击单独校验原件哈希与 44.1 kHz 格式。新声音的起音检查使用相对峰值 2% 阈值，要求 25 毫秒以内；这只是音频文件的起音，不是声卡端到端延迟。指标和试听时间表保存在 [review.json](audio/block_war/review.json)。

```powershell
python tools/build_war_audio.py
python tools/build_war_audio_review.py --events select drag order ui_click --playback-gain
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --script tests/block_war_audio_feedback_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --script tests/block_war_audio_mix_test.gd
```

所有验证使用 Dummy 音频输出或私有 Windows 桌面，不激活窗口、不发送系统输入、不通过用户扬声器自动播放。
