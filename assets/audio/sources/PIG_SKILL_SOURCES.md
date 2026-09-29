# 猪猪技能音源核验（2026-09-30）

五个运行时音效均为本项目对以下 CC0 原件的重新剪辑，没有新增音源许可，也没有真实动物叫声。三份原始压缩包重新从作者发布地址下载，SHA-256 与既有 `sources.json` 完全一致。七个采样文件逐字节与包内原件一致，原件未改动。

| 原始包 | 作者发布页 | 压缩包 SHA-256 |
| --- | --- | --- |
| Kenney Impact Sounds | https://kenney.nl/assets/impact-sounds | `029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8` |
| Vehicle / Jan Schupke — Fantasy Weapons and Apparel SFX Library | https://opengameart.org/content/fantasy-weapons-and-apparel-sfx-library | `81cc6317f21b68f8e7f2b23a5a0f5f33c301c39ee41347307eec02201be989e5` |
| rubberduck — 80 CC0 RPG SFX | https://opengameart.org/content/80-cc0-rpg-sfx | `1c2f06ff4e8563b5b8b745b23cf213c1474142a69bb82bd8f5e10d9b3f7a7bbd` |

| 已留存原件 | SHA-256 |
| --- | --- |
| `kenney_impact/footstep_wood_000.ogg` | `5f1c252942a220d658121bd9417448cd19649ded9fff2ff15f6e50899373ce8e` |
| `kenney_impact/footstep_wood_002.ogg` | `9ff095b05cee5eec40b081defe3f0eef7232bb16d4865ce03b9f6dbab875cfdd` |
| `kenney_impact/impactSoft_heavy_001.ogg` | `4d0096364ba9e46119d2ff6df493fdc101bd2e1efae061da5e5f77a53b3fdcb6` |
| `weapons_apparel/quiver-leather-squeeze-02.wav` | `208b1694418d86614e3f586a751058ebc2ab04e07025921aa4dead39bdcf0006` |
| `weapons_apparel/arrow-feathers-01.wav` | `15493cd9a472a426602ab46fa27b5f012aa0b678dbf07fae0c1f68967ce96f5c` |
| `weapons_apparel/arrow-feathers-02.wav` | `5e2974eade6ba7238642a5993114d46d10fd28912e044cacebff0b9e18c0b4e2` |
| `rubberduck_rpg/stones_01.ogg` | `d11ce95031c2c36ae2a00979620fa95a7a3f5c6d6f2ac86962ed292aa556be8d` |

许可：[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)，允许商业使用、修改和再分发。2026-09-30 重新读取三份作者发布页，均确认 CC0。Kenney 与 Vehicle 的包内许可原文继续保留在对应来源目录，完整 CC0 正文在 `../licenses/CC0-1.0.txt`。rubberduck 的作者页面明确标注 CC0。

处理配方：`tools/build_war_audio.py` 的 `make_pig()`；五个成品的来源、处理步骤与输出哈希：`../block_war/audio_manifest.json`。请以源代码和清单为准复现。

检索时也查阅了 [Vinrax 的 Pig SFX Pack](https://opengameart.org/content/pig-sfx-pack)。它按作者说明是橡胶猪玩具变速、CC BY 3.0；本项目未下载或使用该包，不将其列为本次采样来源。
