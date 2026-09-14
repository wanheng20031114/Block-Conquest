# 柔和卡通界面素材

用于积木争霸的奶油纸卡、鼠尾草绿操作牌、浅木收纳架与细边框。UI 的文字、图标和交互均由 Godot 原生节点绘制；素材不包含烘焙文字。

## 原创图像

2026-09-14 按本项目需求使用图像生成工具制作两张原生透明 RGBA 素材表：

- `source/controls.png`：细横栏、标准按钮、主要按钮、紧凑按钮、选中与未选中页签、收纳架。生成文件 ID：`exec-6ceaa04f-82eb-4c05-93fb-ec1bd0cb1fe3`。
- `source/panels.png`：竖向纸卡、横向面板、透明内芯的视口木框。生成文件 ID：`exec-8d1ca680-af43-409e-9ee5-59df8eceb267`。

`tools/build_medieval_theme.py` 仅执行固定坐标裁切和等比例缩放，保留源 Alpha，不从 RGB 推断透明度。原始素材通过 `source/.gdignore` 排除出运行包；游戏引用 `textures/` 下的分件和 `styles/` 下的原生九宫格资源。大面板、长按钮、小按钮与页签分别使用对应素材和固定边角，不非均匀缩放整张图。

## 字体与参考

标题使用 ZCOOL KuaiLe（站酷快乐体），遵循随附 [SIL Open Font License 1.1](fonts/OFL.txt)。字体来自本地 GodotGameUI 项目，其版权与授权以 OFL 文件为准；Windows 发布包同时携带 `FONT_LICENSE.txt`。

正文使用系统 Microsoft YaHei UI / Microsoft YaHei / Noto Sans CJK SC，不复制或分发这些系统字体。

GodotGameUI 提供了卡通标题和悬停、入场动画的参考。本项目重新实现共享 Tween 行为和纸页转场，场景节点保存在 `.tscn` 中。

原生接口参考：[StyleBoxTexture](https://docs.godotengine.org/en/4.6/classes/class_styleboxtexture.html)、[Tween](https://docs.godotengine.org/en/4.6/classes/class_tween.html)。
