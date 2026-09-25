# 积木战争背景音乐

## 战斗 BGM1 · 夺桥·稳步推进 A

- 文件：`battle_bgm_01.mp3`，用户于 2026-09-25 确认为正式素材。
- 来源：[积木战争 V3-01｜夺桥·稳步推进 A](https://suno.com/song/45487986-8611-439b-b0e0-f1e5f8eef7f6)。
- 生成平台：Suno v6，账号 `wanheng20031114`；官网显示 Pro 计划，通过官方 MP3 下载入口取得。
- 完整提示词及参数：[V3 记录](../../../../docs/audio/block_war_battle_music_v3.json)。126 BPM 是提示目标，未实测节拍。
- 原样保存官方 MP3，48 kHz、双声道、179.6 秒、4,324,123 字节。未重编码、裁剪或响度归一化；增益在 Godot 中处理。
- SHA-256：`7a31151126bb3080cbecbe207225e325c8ed6b1e90664656ab2de8f1f8039293`。

## 战斗 BGM2 · 轻装·轻律回环 A

- 文件：`battle_bgm_02.mp3`，用户于 2026-09-25 确认加入正式音乐库。
- 来源：[积木战争 V4-02｜轻装·轻律回环 A](https://suno.com/song/8436ce13-1d31-477d-91a8-c55840718ea8)。
- 生成平台、账号与下载方式同上；完整提示词及参数见 [V4 记录](../../../../docs/audio/block_war_battle_music_v4.json)。128 BPM 是提示目标，未实测节拍。
- 原样保存官方 MP3，48 kHz、双声道、180 秒、4,571,696 字节；未重编码、裁剪或响度归一化。
- SHA-256：`9dfd282ac24d77297152c09563a13ecf1acc8d65a6bee2fe562879f1644c15c2`。
- FFmpeg 整段平均电平 −16.9 dBFS、采样峰值 −2.9 dBFS；与 BGM1 共用现有播放增益。

上述文件是用户 Suno 账号生成并选定的音乐资产，使用权以该账号适用的 Suno 条款为准；不属于本目录上级音效库的 CC0 素材。逐文件来源与运行参数见 [music_manifest.json](music_manifest.json)。

## 播放与混音

`scenes/block_war/audio.tscn` 中直接放置 `Music: AudioStreamPlayer`，`autoplay = true`，使用 [battle_music_pool.tres](battle_music_pool.tres) 原生 `AudioStreamRandomizer` 资源。资源包含两首等权重曲目，`PLAYBACK_RANDOM` 在每次开局/重开时随机选一首，允许连续对局选中同一首；音高和音量随机变化均关闭。

两首导入的 `AudioStreamMP3.loop = true`、`loop_offset = 0`。所选曲目整局循环，曲尾不会触发重新选曲；随机资源按场景独立实例化。选曲与循环都由原生资源完成，没有 `finished` 信号重播或脚本轮询。

路由为 `Music → BGM → Master`。BGM 不经过 Combat 压缩器；播放器固定 −4 dB，独立音乐音量默认 50%（约 −6.02 dB），最后接受总音量及总静音。音乐关闭或音量为零时，BGM 总线完全静音，音效仍可播放。曲目在静音期间保持播放位置，恢复音乐不会重放前奏。

音乐只随积木战争场景启动；暂停及设置中继续，退出或重开时与原生音效播放实例一起停止并释放。设置通过现有 ConfigFile 保存；旧配置缺少音乐字段时使用默认值。

已验证原生播放器越过曲尾后自动回到开头。保留完整歌曲，未制作无缝拼接剪辑；循环开头包含原曲前奏。FFmpeg 整段平均电平约 −17.5 dBFS、采样峰值 −2.7 dBFS，数字检查不替代实际试听。
