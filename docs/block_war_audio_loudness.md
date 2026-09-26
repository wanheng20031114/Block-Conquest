# 积木战争响度校准 · 2026-09-27

本轮审查当前战役的 26 类音效、继承的炮台发射、共享菜单播放器与两首背景音乐。保留全部 47 个音效源文件和两首 MP3 的原始字节，仅调整播放增益、比例反馈限频与战役空间播放器的增益上限。源文件与 `cd82051` 逐个校验一致，授权沿用 [音频来源记录](../assets/audio/CREDITS.md)。

## 玩家听到的变化

建筑轻敲、技能拖起、松手派兵和 arc-nice 菜单点击维持已认可的响度。派兵拉线依然全程安静，成功松手才播放一次。交战、炮台发射、炮弹命中、增援和施工维持原来的实际输出。

高频滑条反馈更轻，取消与条件不足提示不再压过确认声；暂停和继续接近同一层次。脚步比交战更靠后。占领、失守与胜负提示仍在前景，但收低突然跃出的钟声。八个技能分别校准：补强征召、封条和兔洞，适度减轻战鼓和持续口哨，其余三个技能略提高清晰度。

背景音乐播放器由 -4 dB 调为 -6 dB。两首整曲的原始综合响度实测 -15.1 / -15.2 LUFS，已经接近，因此不分别归一化、不重新编码。用户的总音量、音乐音量、静音和播放开关保持独立，默认仍为总音量 50%、音乐 50%。

## 空间增益问题

旧的战役 3D 播放器继承 `max_db = 0`。Godot 会先把 `volume_db` 与距离模型相加，再按 `max_db` 截断，最后施加 `max_distance` 的线性衰减。这导致事件表中的 +1 / +2 dB 实际被截成 0 dB，并未提高声音。

现在仅在战役场景的 Combat 播放器上把 `max_db` 设为 +3 dB，允许本轮明确配置的增益生效。施工两项由名义 +1 改为 0，以维持原本实际响度；Foley 使用负增益，不需要提高上限。共用总线、原模式场景、压缩器与 -1 dB 主限幅器均维持原值。

## 调整表与完整试听

“增益变化”比较的是修复前后**实际进入空间处理的增益**，不是直接相减旧表中已被截断的正数。原生压缩器会收敛响亮瞬态，因此最后一列的 50 ms 峰值窗口变化通常比技能增益变化小。

所有试听由 Godot 实际混音输出导出，已带入总音量 50%、空间衰减、总线音量和原有动态处理；没有逐条放大或归一化。空间声源位于 `(8,0,0)`，监听点为 `(0,6,0)`。每个播放器依次包括全部变体，中间相隔 0.28 秒，游戏每次仅选一个变体。

| 声音 | 增益变化 | 原生 50 ms 最大 RMS 变化 | 试听 |
| --- | ---: | ---: | --- |
| 比例／滑条 | -8 dB，最多每 100 ms 一次 | -8.0 dB | [全部变体](audio/block_war/loudness/ratio.wav) |
| 条件不足 | -7 dB | -7.0 dB | [试听](audio/block_war/loudness/denied.wav) |
| 取消／返回 | -6 dB | -6.0 dB | [试听](audio/block_war/loudness/cancel.wav) |
| 继续 | -3 dB | -3.0 dB | [试听](audio/block_war/loudness/resume.wav) |
| 行军脚步 | -3 dB | -3.0 dB | [全部变体](audio/block_war/loudness/march.wav) |
| 占领 | -5 dB | -5.0 dB | [全部变体](audio/block_war/loudness/capture.wav) |
| 失守 | -5 dB | -5.0 dB | [试听](audio/block_war/loudness/lost.wav) |
| 胜利 | -4 dB | -4.0 dB | [试听](audio/block_war/loudness/victory.wav) |
| 失败 | -4 dB | -4.0 dB | [试听](audio/block_war/loudness/defeat.wav) |
| 松鼠 Q · 征召军令 | +2 dB | +0.9 dB | [试听](audio/block_war/loudness/skill_command.wav) |
| 松鼠 W · 疾行战鼓 | -1 dB | -0.4 dB | [试听](audio/block_war/loudness/skill_drum.wav) |
| 松鼠 E · 防护罩 | +1 dB | +0.4 dB | [试听](audio/block_war/loudness/skill_shield.wav) |
| 松鼠 R · 火攻 | +1 dB | +0.3 dB | [全部变体](audio/block_war/loudness/skill_breach.wav) |
| 兔子 Q · 蹦蹦小径 | +1 dB | +0.4 dB | [试听](audio/block_war/loudness/rabbit_dash.wav) |
| 兔子 W · 封条急件 | +2 dB | +1.2 dB | [全部变体](audio/block_war/loudness/rabbit_seal.wav) |
| 兔子 E · 归巢口哨 | -2 dB | -2.0 dB | [试听](audio/block_war/loudness/rabbit_recall.wav) |
| 兔子 R · 兔洞快递 | +3 dB | +2.2 dB | [全部变体](audio/block_war/loudness/rabbit_burrow.wav) |

背景音乐各降低 2 dB：[曲目一片段](audio/block_war/loudness/music_01.wav)、[曲目二片段](audio/block_war/loudness/music_02.wav)。其余未改动事件的同条件试听也保存在该目录，包括建筑选择、技能拖起、松手确认、暂停、交战、增援、施工、炮弹命中、炮台发射与菜单点击。

## 实测与验证

Godot 4.6.3、原生立体声混音、Dummy 音频驱动。前后各 57 段捕获：全部 44 个战役变体、两个炮台发射变体、四个菜单播放器、两项远距离比较、两段音乐、两段繁忙战场与一段极端叠加场景。捕获缓冲无丢帧。场景使用实际事件入口、限频和并发上限；它们是脚本构造的混音场景，并非真人游玩录音。

| 场景 | 综合响度，修改前 → 后 | 真峰值，修改前 → 后 |
| --- | --- | --- |
| 繁忙战场，曲目一 | -23.7 → -25.2 LUFS | -7.11 → -10.67 dBTP |
| 繁忙战场，曲目二 | -23.7 → -25.3 LUFS | -7.24 → -9.93 dBTP |
| 总音量与音乐均 100%，技能并发及 500 次接触请求 | -15.7 → -17.1 LUFS | -0.87 → -3.42 dBTP |

表中普通场景已应用默认 Master 50%；压力场景使用 100%。全音量压力场景保留了八个技能的实际触发，输出样本峰值和 4 倍过采样真峰值均低于 0 dBFS；本轮场景没有依靠持续触发主限幅来控制响度。两段 [战场混音一](audio/block_war/loudness/battle_01.wav)、[战场混音二](audio/block_war/loudness/battle_02.wav) 可直接试听。[压力场景试听](audio/block_war/loudness/maximum_stress.wav) 单独回落到 50% Master，避免试听音量突然跳高。

短声音以 50 ms / 400 ms 滑动 RMS、真峰值、起止及原生输出校验；长混音另用 FFmpeg EBU R128 / BS.1770 测量。没有把每个短点击拉到同一 LUFS。这里的数值不等于扬声器声压，也不替代玩家的实际听感。完整前后数据、每个变体的时间表和条件见 [report.json](audio/block_war/loudness/report.json)。

通过：响度与资产校验 98 项、原生音频 72 项、触发与菜单 35 项、音乐 24 项，共 229 项。原生音频测试新增压缩器之前的 +3 dB 增益回归，确保以后不会再被空间播放器截断；菜单与战场同类操作的增益也逐项对照。音乐测试修正了直接跳转底层 MP3 游标时的线程竞争，用 `AudioServer.lock/unlock` 保护测试中的跳转，不改变运行时播放逻辑。静音、暂停、设置、跨场景释放与整曲循环均已覆盖。

## 依据

- Firaxis 音频团队，[Designing Sound for the Centuries in Civilization VII](https://www.asoundeffect.com/civilization-vii-game-audio/)：UI 的重复耐受性与信号强度取决于频率、重要性、时长及音色；持续战斗必须在真实操作中混音；监听位置和衰减会直接改变层次。本项目采用该原则安排层级，保留已有的组脚步与并发限制，没有照搬其庞大的总线结构。
- [Game Audio Explained — Mixing and Balancing](https://www.asoundeffect.com/gameaudioexplained/)：先分组校准，再把效果、音乐等放入实际游戏语境中调整。
- Godot [Audio buses](https://docs.godotengine.org/en/stable/tutorials/audio/audio_buses.html)、[AudioStreamPlayer3D](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html)、[AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html)：原生分组、空间增益、输出留余量与无损采样。
- Godot [3D 播放器实现](https://github.com/godotengine/godot/blob/4.6-stable/scene/3d/audio_stream_player_3d.cpp)：核实 `volume_db`、`max_db`、线性距离衰减的实际顺序。Wwise 帮助站此次返回 403，因此未把未读取的页面作为结论依据。

## 复现

```powershell
$audit = Join-Path $env:TEMP 'block-war-loudness-review'
New-Item -ItemType Directory -Path $audit -Force | Out-Null
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --log-file "$audit/capture.log" --script tests/block_war_loudness_capture.gd -- "--output=$audit/final"
# before 是修改前同一捕获脚本的输出目录；历史数值已经保存于 report.json。
python tools/review_war_loudness.py --before "$audit/before" --after "$audit/final" --reference cd82051
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --log-file "$audit/mix.log" --script tests/block_war_audio_mix_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --log-file "$audit/feedback.log" --script tests/block_war_audio_feedback_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --log-file "$audit/music.log" --script tests/block_war_music_test.gd
```

本轮没有激活窗口、发送系统输入或通过用户扬声器播放声音。试听文件不会自动播放；临时浮点捕获和日志在完成后清理。
