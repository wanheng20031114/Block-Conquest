# 英雄界面资源

`theme.tres` 与 `styles/` 是独立的原生主题，不影响 RTS 和其他模式的菜单。

`healing_potion.png`、`windwalk_potion.png`、`health_heart.png`、`speed_boot.png` 为 2026-09-16 生图工具生成的原创透明立体图标。原始 2×2 图集有原生 RGBA；仅分格、按 Alpha 裁切、等比缩放并透明补边为 320×320。未提取参考游戏的图标，未按背景 RGB 推断透明度。对应旧像素药剂图已替换。

`backpack.png` 沿用已有透明背包图。所有图标使用 `TextureRect.KEEP_ASPECT_CENTERED`、线性过滤；不拉伸变形。

火枪缩略图不是静态图片：`hero_interface.tscn` 的 `WeaponIconViewport` 使用实际 `repeating_musket.tscn`，只渲染一次，并由装备栏、HUD 与详情共用。

`glass.gdshader` 只在背包面板区域采样屏幕背景。一个原生 `BackBufferCopy` 由背包父节点的可见性控制，HUD 无屏幕采样或额外战场渲染。

界面可直接编辑 `scenes/hero/hero_interface.tscn`、`inventory_slot.tscn`。如需重建布局与样式，执行 `python tools/build_hero_interface.py`（入口调用 `hero_ui_layout.py` 和 `build_hero_theme.py`）。
