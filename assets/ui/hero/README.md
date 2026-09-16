# 英雄界面资源

`theme.tres` 与 `styles/` 是独立的原生主题，不影响 RTS 和其他模式的菜单。

`healing_potion.png`、`windwalk_potion.png` 直接使用 `Documents/arc-nice/resources/texture/consumables/` 的同名 32×32 像素原图。用户明确要求药品采用这套像素素材，不采用高光玻璃瓶、写实宝石质感的生图风格。

药剂在背包格子、快捷栏、拖拽与详情中均使用最近邻过滤，保持像素边缘清晰。`backpack.png`、`health_heart.png`、`speed_boot.png` 沿用已有图标与线性过滤。所有图标等比居中，不拉伸变形；详情切换至真实火枪时恢复线性过滤。

火枪缩略图不是静态图片：`hero_interface.tscn` 的 `WeaponIconViewport` 使用实际 `repeating_musket.tscn`，只渲染一次，并由装备栏、HUD 与详情共用。

`glass.gdshader` 只在背包面板区域采样屏幕背景。一个原生 `BackBufferCopy` 由背包父节点的可见性控制，HUD 无屏幕采样或额外战场渲染。

界面可直接编辑 `scenes/hero/hero_interface.tscn`、`inventory_slot.tscn`。如需重建布局与样式，执行 `python tools/build_hero_interface.py`（入口调用 `hero_ui_layout.py` 和 `build_hero_theme.py`）。
