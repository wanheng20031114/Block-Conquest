# 中世纪音效来源与修改说明

原模式运行库由 81 份保留原样的 CC0 音源和项目自制数字合成层构成，生成 22 类、56 个 WAV 变体。积木战争当前为 26 类、44 个专用 WAV，使用 CC0 与 CC BY 3.0 素材；2026-09-26 的新增来源和署名见本文末节。以下三组原有 CC0 素材下载于 2026-09-08；没有使用 Sonniss 或付费素材。

积木战争的 Suno 背景音乐独立记录在 [block_war/music/CREDITS.md](block_war/music/CREDITS.md)，不属于此处的 CC0 音效库。

| 音源包 | 作者 | 许可 | 原始发布页 |
| --- | --- | --- | --- |
| Impact Sounds 1.0 | Kenney | CC0 1.0 Universal | https://kenney.nl/assets/impact-sounds |
| Interface Sounds 1.0 | Kenney | CC0 1.0 Universal | https://kenney.nl/assets/interface-sounds |
| Fantasy Weapons and Apparel SFX Library | Vehicle / Jan Schupke | CC0 1.0 Universal | https://opengameart.org/content/fantasy-weapons-and-apparel-sfx-library |

许可根据作者发布页及下载包内原始说明核实。CC0 允许商业使用、修改及再分发，无署名要求；这里保留作者信息以明确来源。完整 CC0 法律文本保存在 `licenses/CC0-1.0.txt`，作者原始包内说明保存在各 `sources` 子目录的 `License.txt` 或 `readme.txt`。上表链接指向作者发布原页；`sources.json` 保留核验日期和下载地址。[CC0 原始许可页面](https://creativecommons.org/publicdomain/zero/1.0/)亦可直接查阅。

`sources.json` 记录各包的下载 URL、原始压缩包 SHA-256、文件字节数，以及所有保留音源的 SHA-256。`audio_manifest.json` 逐个记录成品使用的原始文件、处理操作与最终哈希。未使用的下载音频已经移除，`sources/.gdignore` 使原始音源只用于离线建库，不被 Godot 重复导入或作为运行资源加载。

处理包括：单声道混合、48 kHz 多相重采样、裁除静音、少量变速移调、高低通均衡、分层剪辑、首尾淡化、按活动区 RMS 调整增益与柔和控制瞬态峰值。剑击末级采用 4 阶 4.8 kHz 低通，控制多个金属击打叠加时的高频密度。上述处理由 `tools/build_audio.py` 确定性执行。

合成层为本项目自制：挥剑空气声、弦线振动、低频冲击主体、炮声压力爆发、爆炸低频尾声、灰尘噪声和金币短共振。它们不是下载录音，不标称为实录或第三方开源素材。马蹄音是木/石脚步拟音组合，未使用或声称使用真实马匹录音；死亡声为装备和身体跌落拟音，不含人声。胜负提示是短敲击/落地提示，不含旋律或 BGM。

2026-09-15 新增两种独立火枪音效：火药爆响、中低频压力主体和短尾音由本项目离线合成，少量枪机接触层复用已保留的 Kenney `impactMetal_light_001/002.ogg`。这两种音效不是实枪录音；没有新增第三方下载素材，原有 54 个成品保持不变。

此前旧版单文件合成音效属于项目自制；完成引用切换后已从运行资源目录移除，包括旧背景音乐和风声。新生成器不再生成这些旧资源。历史版本仍可通过 Git 查看。

2026-09-22 新增积木战争专用拟音库，位于 `block_war/`：21 类事件、36 个 48 kHz 单声道 PCM16 WAV，共约 2.04 MiB。仅复用上述已保留的 CC0 音源，没有新增下载或合成振荡器/噪声层。包含木质选择、皮革拖选、派兵比例、命令确认、拒绝、取消、暂停/继续、草地皮靴行军、刀剑木盾交战、占领/失守、增援、升级、改建、四种技能以及胜败。

`tools/build_war_audio.py` 使用 FFmpeg 解码，NumPy/SciPy 完成确定性的去直流、裁切、变速移调、均衡、时序分层、柔和瞬态控制和首尾淡化；真峰值上限为 -3 dBFS。战鼓由低音木材与软物接触录音拟音，护盾使用锁扣/金属/石块组合，冲击技能使用刮擦和层叠碎石，胜败使用升降移调的实录铃声与装备动静。`block_war/audio_manifest.json` 逐个列出原始录音、处理描述、音量测量和 SHA-256。成品不循环，播放继续经过项目原生 Master 限幅器、Combat 压缩器和现有音量/静音设置。

## 2026-09-26：UI 与技能音效更新

上节记录的是此前版本。此次替换 8 类 UI、松鼠 4 技能，新增兔子 4 个独立技能事件及炮弹命中事件，共变更 17 类、25 个成品 WAV。其余 19 个积木战争 WAV（含行军、交战、增援、施工、占领、胜负）保持原文件哈希。

| 原始发布标题 | 作者 | 许可 | 发布页 |
| --- | --- | --- | --- |
| RPG Audio 1.0 | Kenney | CC0 1.0 | <https://kenney.nl/assets/rpg-audio> |
| 80 CC0 RPG SFX | rubberduck | CC0 1.0 | <https://opengameart.org/content/80-cc0-rpg-sfx> |
| UI Sound effects pack | David McKee (ViRiX) | CC BY 3.0 | <https://opengameart.org/content/ui-sound-effects-pack> |
| UI and Item sounds Sample 1 | David McKee (ViRiX Dreamcore) | CC BY 3.0 | <https://opengameart.org/content/ui-and-item-sounds-sample-1> |
| UI and Item sound effect Jingles Sample 2 | David McKee (ViRiX Dreamcore) | CC BY 3.0 | <https://opengameart.org/content/ui-and-item-sound-effect-jingles-sample-2> |
| Magic SFX Sample | David McKee (ViRiX Dreamcore) | CC BY 3.0 | <https://opengameart.org/content/magic-sfx-sample> |
| Whistles | dklon | CC BY 3.0 | <https://opengameart.org/content/whistles> |
| Horde War Drums loop | William Hector | CC0 1.0 | <https://opengameart.org/content/horde-war-drums-loop> |

Some of the sounds in this project were created by David McKee (ViRiX / ViRiX Dreamcore), <https://soundcloud.com/virix>. Whistle sound by **dklon**. These works are used under [Creative Commons Attribution 3.0 Unported](https://creativecommons.org/licenses/by/3.0/); the full legal text is included in [licenses/CC-BY-3.0.txt](licenses/CC-BY-3.0.txt). CC0 sources use [Creative Commons Zero 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

**修改说明：**原始下载文件原样保留在 `sources/`，仅选择实际使用的文件，不保留整包无关素材。运行音频转换为 48 kHz 单声道 PCM16；裁去弱起音和过长静音，裁切时长并淡出，部分变体只改变 2.5% 播放速率。UI 直接采用原素材的音色；防护罩、风场、封条、兔洞和命中采用至多两个素材层。新版本只以线性增益控制活动区音量与真峰值，不对这些新音效使用旧版 tanh 饱和或大幅变调。短 UI 真峰值不高于 -7 dBFS，技能不高于 -3 dBFS。素材包并非全部宣称为实地录音，魔法、界面提示和鼓段包括作者设计的成品音效或音乐片段。

`sources.json` 记录下载地址、日期、压缩包 SHA-256、原文件 SHA-256 和许可；`block_war/audio_manifest.json` 将每个成品对应到实际使用的源文件和发布页。具体剪辑由 `tools/build_war_audio.py` 复现。上述署名不表示作者为本游戏背书。

运行时 F1 帮助页保留 ViRiX 与 dklon 署名及许可链接文字。Windows 导出明确包含本文件、许可全文和来源清单；只用于离线制作的原始音源不重复导入游戏包。

## 2026-09-27：收简交互与复用 arc-nice 点击

建筑选择、技能拖起、派兵确认改为 Kenney Impact Sounds 的单次木材接触，分别为 0.08、0.09、0.16 秒；没有旋律、纸张层或额外叠层，播放器增益分别为 -6、-8、-3 dB。拉动派兵线、经过其他建筑和拖动中调整比例均不请求声音，成功松手才响一次确认。其余 38 个积木战争 WAV 保持原文件哈希。

菜单选择直接复用用户指定的 arc-nice 项目 `resources/audio/ui/ui_click.wav`，原件与运行副本 `ui/arc_nice_click.wav` 字节一致，保留 44.1 kHz 单声道 PCM16、0.115 秒与 -8 dB 播放器增益。来源项目提交及哈希见 [arc-nice 来源记录](sources/arc_nice_ui/SOURCE.md)。本素材按用户指示作为其项目资产复用，记录为 `LicenseRef-User-Project`，不将其标注为 CC0 或 CC BY；上述第三方素材许可不适用于这一文件。
