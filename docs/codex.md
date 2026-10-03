# 图鉴

主菜单「图鉴」收录六位已实装指挥官、二十四项技能和战场指南。所有条目直接开放，查阅不会更改出战角色、地图、设置或战斗状态。

## 界面与操作

- 采用奶油色纸面、鼠尾草绿目录、蜂蜜色选中态与原有像素角色立绘。
- 「英雄图鉴」「战场指南」切换分类；目录支持鼠标、方向键与关键词筛选，英雄技能名也可用于检索。
- 英雄页选择技能查看效果、目标、技力与冷却。演示直接运行独立的小型实机场景，可暂停、继续或重播。
- 己方位于左侧，敌方位于右侧；增产仅展示己方住宅，行军技能先出兵再施放，削弱技能作用于敌军或敌方据点。链式防守与恐慌按实际规则补充支援或避难建筑。
- 切到指南或空搜索结果时停止演示；返回主菜单后焦点回到图鉴入口。
- 入场沿用原生菜单过渡完成后的分段动效；连续切换内容会中断上一段动效，避免缩放与透明度累积。

## 场景与数据

- `scenes/codex/codex.tscn`：原生 Container、ItemList、ScrollContainer 与预置详情节点。
- `scenes/codex/skill_demo.tscn`：独立 `SubViewport` 和播放状态栏，实机画面填满预览区，正交镜头随区域纵横比适配；暂停或隐藏时停止渲染与模拟。
- `scenes/codex/demo_world.tscn`：预搭地面、灯光、固定相机和真实建筑，复用正式战场的行军与技能特效场景。
- `scripts/codex/codex_catalog.gd`：正式、简洁的说明文字；技能名称、数值和图标引用 `war_skill_rules.gd`，住宅与工期引用 `war_building.gd`。
- `scripts/codex/skill_demo.gd`：切换与重播完整演示场景，不将旧技能的部队、粒子或计时带入新演示。
- `scripts/codex/demo_world.gd`：继承实际战斗控制器，复用派兵、人口、施法和伤害结算；仅隔离会话入口、网络、输入、胜负与正式 HUD。

美术全部复用项目现有资源，未增加外部图像依赖。预留角色未实装前不列入名录。
目录图标与机制插画统一使用图鉴专属 `codex_icons.tres`，内嵌原 SVG 矢量源并使用原生 DPITexture 的 4 倍基础分辨率和自动 DPI 重绘；目录用线性采样保持曲线边缘清晰，英雄像素立绘继续使用最近邻采样。战斗界面的原图及导入设置不变，导出后无需读取外部 SVG 源文件。

## 原生能力参考

- [ItemList](https://docs.godotengine.org/en/stable/classes/class_itemlist.html)：图标列表、选择、滚动与键盘导航。
- [DPITexture](https://docs.godotengine.org/en/stable/classes/class_dpitexture.html)：内嵌矢量源、基础分辨率与窗口缩放时自动重绘。
- [ScrollContainer](https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html)：长篇指南的原生滚动。
- [SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html)：隔离三维世界、禁用输入与控制渲染更新。
- [SubViewportContainer](https://docs.godotengine.org/en/stable/classes/class_subviewportcontainer.html)：将实机场景嵌入图鉴布局。
- [Button](https://docs.godotengine.org/en/stable/classes/class_button.html)：技能与分类的原生选择状态。

## 验证

`tests/codex_test.gd` 覆盖菜单往返、六位英雄及二十四项技能、规则数据一致性、检索空态、全部指南、暂停重播、快速切换与只读状态，并输出原生渲染截图。`tests/codex_native_demo_test.gd` 验证真实施法、对应的部队或建筑变化、镜头构图、960×540 小窗口及演示隔离。可通过 `tools/run_godot_private_desktop.py` 在独立桌面运行，测试结束自动释放进程树。

正式导出必须启用 `internationalization/locale/include_text_server_data`，随包携带 `icudt_godot.dat`；模板准备工具会从官方模板包提取匹配的数据。编辑器内置 ICU 数据，仅用编辑器运行 PCK 无法发现缺失数据导致的中文断行退化。`tools/build_windows.ps1` 额外用实际发行 EXE 执行 `tests/export_text_layout_test.gd`，检查 720p、900p、1440p 下全部指南和技能的原生排版行宽。测试副本只增加检查入口，产品包不含检查脚本。详情见 [1.3.3 根因与发行验证](reviews/2026-09-30-export-text-1.3.3.md)。

1.3.4 将十二个目录图标从战斗用小尺寸导入图切换到图鉴专属 DPITexture，避免放大 32×40／64×64 纹理造成模糊和锯齿。上述发行 EXE 检查同时覆盖图标类型、基础分辨率及指南／像素立绘的采样区别；三个窗口尺寸的原生 GPU 验证共 990 项通过。

## 技能命中表现

青蛙大招以交错叶刃命中建筑，伴随碎瓦、土灰和卷尘显示降级；狐狸炸弹和猪的落地冲击补充接触层次与碎屑，熊的震地补充短促冲击波。保留原有技能的结算时点、伤害、范围和阵营规则。

建筑爆炸减员使用真实士兵模型呈现抛飞、肢体摆动、翻滚落地和快速淡出。有阵营的建筑固定展示八个代表性伤亡实例，防止通过百分比技能与抛飞人数反推隐藏驻军；人口公开的中立建筑按损失展示，最多十八个。复用预搭 `MultiMeshInstance3D`，不会生成额外行军或再次扣兵。联机发送受限的视觉事件；客户端仅播放同样的效果，不参与结算。狐狸的抛飞等待炸弹画面在 0.18 秒时接触建筑；伤害结算仍保持原规则。

`tests/block_war_blast_casualties_test.gd` 验证真实施法结果、视觉生命周期、狐狸命中同步、无额外伤害、客户端重放与非法视觉数据拒绝。

本次原生演示验证 416 项通过，菜单交互验证 1,563 项通过。[实机预览](art/codex_live/skills_preview.mp4) 依次展示松鼠征召、行军加速与青蛙致命打击，由 `tests/codex_capture.gd` 按 24 fps 录制，共 24 秒。
