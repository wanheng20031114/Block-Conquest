# UI 点击音效：2026-09-28

普通按钮、分类切换、选人和下拉选项改用新制作的 `assets/audio/ui/soft_click.wav`。手感是一次迅速收住的轻敲；开始／确认、返回、滑条、建筑选择、派兵、技能与 BGM 没有更换。

## 参考与制作

- [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)：官方提供 100 个 CC0 界面声音。分析了项目已有的 `click_001` 和 `click_002` 的短接触结构作为设计参考，未复制其音频。
- [微软 Sound 指南](https://learn.microsoft.com/en-us/windows/apps/develop/ui/sound)：Invoke 对应明确点击或按键操作；同类操作保持相同语义。延续项目已有的点击触发，没有增加悬停声音。
- [Firaxis《文明 VII》音频访谈](https://www.asoundeffect.com/civilization-vii-game-audio/)：重复耐受性与信号强度需要结合使用频率设计；高频触发音保持短促、减少复杂音调，以较低频率的主体配合克制的高频细节。

本次原创设计由 `tools/build_ui_click.py` 生成。一次带限的接触噪声配合很弱的低频共振，快速衰减，削去尖锐高频；没有旋律、混响、扫频、饱和或延迟。固定随机种子保证成品可重复构建。Godot 按 PCM16 导入，关闭压缩、自动归一化、裁边和循环。

## 响度与验证

| 项目 | 结果 |
| --- | --- |
| 素材长度 | 48 ms |
| 素材起音（峰值的 2% 阈值） | 0.208 ms，不代表系统输入到扬声器延迟 |
| 累计 99% 声音能量位置 | 22.75 ms |
| 素材 50 ms RMS | -21.26 dBFS；原点击为 -18.57 dBFS |
| 素材 4 倍过采样真峰值 | -4.50 dBTP |
| 播放器／默认总音量 | -8 dB／50%，均保持原值 |
| 默认游戏混音的 50 ms RMS／真峰值 | -35.26 dBFS／-18.52 dBTP |

短点击使用 50 ms 能量和真峰值检查，没有套用音乐平台的整体 LUFS 目标。仅替换普通 UI 点击，原有 44 个战役音效文件及清单内容均保持一致。

Godot 4.6.3 无头模式、Dummy 音频输出完成原生混音采样，全程没有扬声器外放或系统输入。`tests/ui_click_capture.gd` 的 11 项检查通过，包括真实资源导入、UI 总线路由、9 次独立点击、同帧 200 个请求只响一次、静音和有限尾音。现有 `tests/block_war_audio_feedback_test.gd` 的 39 项触发检查通过。另检查了确定性构建、波形首尾归零、短起音、峰值和未修改素材的哈希。

试听是 Godot 实际输出：先 3 次间隔点击，再 6 次快速点击，已乘以记录到的默认 Master 50%，没有另外放大或归一化。主观听感仍以玩家试听为准。

[试听](audio/ui_click/preview.wav) · [测量记录](audio/ui_click/measurements.json)

```powershell
python tools/build_ui_click.py
# 在编辑器导入新音源后，用 Dummy 输出进行原生检查：
& 'C:/Program Files/Godot/Godot_console.exe' --headless --audio-driver Dummy --path . --script res://tests/ui_click_capture.gd -- res://.local/ui-click-capture
```
