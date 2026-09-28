# 战地手册

主菜单「战地手册 · 图鉴」收录四位已实装指挥官、十六项技能和十一篇战场指南。所有条目直接开放，查阅不会更改出战角色、地图、设置或战斗状态。

## 界面与操作

- 采用奶油色纸面、鼠尾草绿目录、蜂蜜色选中态与原有像素角色立绘。
- 「英雄图鉴」「战场指南」切换分类；目录支持鼠标、方向键与关键词筛选，英雄技能名也可用于检索。
- 英雄页选择技能查看效果、目标、技力与冷却。技能示意可暂停、继续或重播，时间与距离比例经过简化。
- 切到指南或空搜索结果时停止演示；返回主菜单后焦点回到图鉴入口。
- 入场沿用原生菜单过渡完成后的分段动效；连续切换内容会中断上一段动效，避免缩放与透明度累积。

## 场景与数据

- `scenes/codex/codex.tscn`：原生 Container、ItemList、ScrollContainer 与预置详情节点。
- `scenes/codex/skill_demo.tscn`：预置据点、士兵图标、范围与轨迹；AnimationPlayer 驱动循环，隐藏时暂停。
- `scripts/codex/codex_catalog.gd`：正式、简洁的说明文字；技能名称、数值和图标引用 `war_skill_rules.gd`，住宅与工期引用 `war_building.gd`。
- `scripts/codex/skill_demo.gd`：仅呈现效果示意，不实例化真实对局或运行战斗逻辑。

美术全部复用项目现有资源，未增加外部图像依赖。预留角色未实装前不列入名录。
机制插画使用 `codex_icons.tres` 内嵌的原 SVG 矢量源与 Godot 4.6 原生 DPITexture，在大尺寸与缩放窗口中保持清晰；导出后无需读取外部 SVG 源文件。

## 原生能力参考

- [ItemList](https://docs.godotengine.org/en/stable/classes/class_itemlist.html)：图标列表、选择、滚动与键盘导航。
- [ScrollContainer](https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html)：长篇指南的原生滚动。
- [AnimationPlayer](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html)：演示时间轴、暂停、定位与循环。
- [Button](https://docs.godotengine.org/en/stable/classes/class_button.html)：技能与分类的原生选择状态。

## 验证

`tests/codex_test.gd` 覆盖菜单往返、四位英雄及十六项技能、规则数据一致性、检索空态、全部指南、暂停重播、快速切换与只读状态，并输出原生渲染截图。可通过 `tools/run_godot_private_desktop.py` 在独立桌面运行，测试结束自动释放进程树。
