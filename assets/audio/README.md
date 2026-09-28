# 积木战争音效与音乐

运行时事件由 `scripts/block_war/war_sound_bank.gd` 定义，含 44 个音效变体；`scripts/sound_bank.gd` 仅包含两段炮声。菜单点击使用 `ui/arc_nice_click.wav`，音乐位于 `block_war/music/`，由独立 BGM 总线控制。

成品、原始音源、剪辑说明和许可分别见 `block_war/audio_manifest.json`、`audio_manifest.json`、`sources.json`、`CREDITS.md` 与 `licenses/`。炮声从拆分前项目原样继承；原制作历史保留在 Git 中。音乐的来源和使用权见 `block_war/music/CREDITS.md`。

运行不需要 Python 或网络。重新剪辑战争音效可安装 `numpy scipy`，再执行 `python tools/build_war_audio.py`；素材审核工具为 `tools/build_war_audio_review.py` 和 `tools/review_war_loudness.py`。这些工具只用于离线制作。
