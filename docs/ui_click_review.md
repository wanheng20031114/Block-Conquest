# UI 点击音效：2026-09-30

普通按钮、分类切换、选人和下拉选项使用 `assets/audio/ui/soft_click.wav`。当前版本是一声更紧凑的轻敲：强化接触瞬间，缩短软尾音，保持较弱的低频主体和受控高频。开始／确认、返回、滑条、建筑选择、派兵、技能与 BGM 的素材没有更换。

## 触发时机与听感

`UIFeedback` 在原生 `button_down` 时播放，跟随按压动画。按钮业务仍使用原有的 `pressed`；普通按钮在松开时确认，按住后移出不会执行操作。松开和键盘重复事件不会重复发声，下拉菜单的 `item_selected` 保留选项确认音。

此前将声音从松开提前到按下，只消除了输入层的等待。旧 WAV 虽然很早出现非零采样，声音能量仍分布得较散；这不足以证明听起来利落。本次重做瞬态包络与频谱，把更多能量集中在最初几毫秒，缩短主体衰减。没有通过整体加大音量替代音色处理。

| 素材指标 | 旧版 | 当前 |
| --- | --- | --- |
| 长度 | 48 ms | 28 ms |
| 前 3 ms 能量占比 | 36.05% | 66.76% |
| 累计 50% 能量位置 | 4.813 ms | 1.792 ms |
| 累计 90% 能量位置 | 11.979 ms | 5.500 ms |
| 累计 99% 能量位置 | 22.750 ms | 11.750 ms |
| 50 ms RMS | −21.26 dBFS | −21.94 dBFS |
| 4 倍过采样真峰值 | −4.50 dBTP | −3.00 dBTP |
| 6 kHz 以上功率占比 | 0.13% | 2.26% |

播放器维持 −8 dB，默认 Master 维持 50%。当前起音更集中但总能量略低，减少连续点击的疲劳感。波形首尾归零，保留很短的边界淡入／淡出，避免裁切爆点；没有混响、扫频或回声。

## 原生音频链路检查

在当前设备及用户安装的 Godot 4.6.3 上，默认 WASAPI 输出周期报告为 10 ms。16 次静音采样中，从播放请求到首次观察到主总线含声混音为 6.9–13.9 ms；该值包含主线程轮询粒度，且不包含声卡、扬声器或耳机延迟，不能当成端到端测量。

临时把请求输出延迟设为 5 ms，WASAPI 返回 `0x88890028`，回退到 1056 帧、约 22 ms 的旧接口缓冲；回退后的 `get_output_latency()` 还报告 0。因此没有把这个设置写入项目。Master 的 HardLimiter 约 2 ms 前瞻保留，其 120 ms release 是恢复时间，并非额外起音等待。

## 制作、验证与试听

`tools/build_ui_click.py` 固定随机种子构建项目原创声音：450–4500 Hz 接触噪声、70 μs 攻击、5.2 ms 衰减，混入 3.4 ms 衰减的弱主体，最后 6 kHz 低通。48 kHz 单声道 PCM16 导入，不压缩、不归一化、不自动裁边、不循环。短点击使用 50 ms 能量和真峰值检查，不套用音乐平台的整体 LUFS 目标。

Godot 4.6.3 原生混音和鼠标／键盘的 21 项检查通过：按下即请求播放，按住时已有混音输出，松开确认且不重响，移出取消、禁用、静音、连点及有限尾音均正常。构建可重复，音频清单中的其他条目保持一致。

试听来自 Godot 实际混音，应用记录到的默认 Master 50%，没有额外归一化。试听和声学指标供判断音色；最终手感仍需在实际点击时确认。

- [前后对比：先三声旧版，停顿后三声新版](audio/ui_click/comparison.wav)
- [新版：三次间隔点击，再六次快速点击](audio/ui_click/preview.wav)
- [测量记录](audio/ui_click/measurements.json)

运行 `python tools/build_ui_click.py` 重建素材；重新导入后，使用 Godot 的 `--headless --audio-driver Dummy --path . --script res://tests/ui_click_capture.gd -- res://.local/ui-click-capture` 参数进行原生检查。

参考：[Godot 音频同步](https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html)、[输出延迟设置](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-audio-driver-output-latency)、[原生音频采样](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html)。最初材质设计参考 [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) 的短接触结构和[微软声音指南](https://learn.microsoft.com/en-us/windows/apps/develop/ui/sound) 的明确操作反馈，成品不包含这些第三方采样。
