# 柔和卡通 UI 规范

界面服务于积木军队与森林地图，采用奶油纸卡、浅木边缘和鼠尾草绿，保持轻快、清楚的卡通气质。中世纪感由军队、建筑和场景提供；界面不使用厚皮革、铆钉、金属包角、蜡封或仿古宋体装饰。

## 颜色、文字与版面

- 奶油白承载正文，低饱和绿标识主要操作，青灰用于次级区域；深灰绿保证文字可读。警告色只标识危险或不可逆操作。
- 标题使用 `ZCOOLKuaiLe-Regular.ttf`，正文沿用清楚的共享正文字体；不要在数值表或长说明中使用装饰字。
- 文字由原生 Label、Button、RichTextLabel 排版，不能烘焙到背景图。正文左对齐；单行按钮居中；长选项的标题、费用与结果分行对齐。
- 布局使用 Container、锚点与最小尺寸。先为文字和图标留下空间，再选择合适的背景资源；不得通过压扁字体、缩小整个面板或挤压素材修复溢出。

以下尺寸为 1600×900 设计视口中的逻辑像素，最终以实际字体和内容高度为准：

| 控件 | 建议尺寸 | 排版要求 |
|---|---|---|
| 大厅主入口 | 高 56–64，字 23–25 | 单行；上、下边距视觉一致 |
| 普通按钮、下拉框 | 高至少 44，字 18–20 | 左右各至少 12；文字不碰装饰边缘 |
| 紧凑图标、生产队列 | 高 32–40 | 使用专用小比例资源；详细信息放提示中 |
| 两行事件、招募选项 | 高至少 76 | 标题与资源费用有明确间隔，随内容增高 |
| 正文、面板标题 | 正文 18–20，标题 26–30 | 面板内边距通常 16–24；长内容滚动 |

## 交互状态与文字对比度

奶油色、浅绿底板上的文字始终使用深灰绿。悬停通过底板提亮与边框反馈，选中通过浅绿底板反馈；不能把浅底上的字改成白色。禁用状态降低底板饱和度并略淡化文字，费用和原因仍须能读清。编队错误提示用深红 `#8a3d35`，成功提示用深绿 `#385840`，配合说明文字表达状态。

- 同时定义普通、悬停、按下、按下并悬停、键盘焦点和禁用状态。Godot 的缺省主题是深底浅字，遗漏任一状态都会重新引入白字。
- `ItemList` 需覆盖 `font_hovered_color`、`font_hovered_selected_color` 以及 `hovered_selected`、`hovered_selected_focus` 底板；`Button` 需覆盖 `font_hover_pressed_color` 和 `font_focus_color`；页签需覆盖 `font_hovered_color`。局部 Theme 和场景内覆盖也按相同规则检查。
- 下拉菜单、提示、输入框占位字和只读字、文本选区都应成对设置前景与背景。不要用全控件浅色 `modulate` 代替语义字色。
- 项目验收目标：可操作正文及按钮文字至少 **4.5:1**，禁用文字至少 **3:1**。禁用 3:1 是项目额外要求，非 WCAG 的禁用控件要求。计算必须包含纹理、透明底板与按压动画调制，不能只比较两个设计色值。

原生状态名称见 [ItemList](https://docs.godotengine.org/en/4.6/classes/class_itemlist.html) 和 [Button](https://docs.godotengine.org/en/4.6/classes/class_button.html)；正文对比度依据见 [WCAG 对比度说明](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)。本轮实测范围和结果见 [交互配色验证](ui-contrast-validation.md)。

## 素材比例与九宫格

宽按钮、短按钮、方形槽位和大型纸卡应分别提供匹配比例的素材。不要把一张宽按钮原图同时塞进方形队列、窄标签和高面板。

背景使用原生 `StyleBoxTexture` 九宫格：角落保持轮廓和厚度，只让无图案的中心及必要边缘延展。根据原图设置 `texture_margin_*`，让切线穿过平直区域，避开圆角、笔触、折角与阴影。控件最小尺寸不得小于两侧切片边距之和；正文空间使用独立的 `content_margin_*`。Godot 对九宫格切片及 stretch/tile 模式的说明见 [StyleBoxTexture 官方文档](https://docs.godotengine.org/en/4.6/classes/class_styleboxtexture.html)。

- 图标、徽记、独立插画保持原始宽高比；使用 `TextureRect` 保持比例居中，不能非均匀缩放。
- 有明显纸纹或木纹的区域，选择匹配比例的素材或可无缝平铺的纹理；不要把细纹拉成长条，也不要平铺会显露重复接缝的画面。
- 不通过放大 `expand_margin_*` 隐藏布局问题；阴影不能侵占相邻按钮或文字的可交互区域。
- 透明素材保留原始 Alpha。组件裁切、透明补边、等比尺寸整理和切片是允许的确定性处理；不按背景颜色推断透明度。
- 在 1280×720、1600×900、1920×1080 下检查同一控件，确认圆角、纸边、图标和文字没有变形，悬停后也不越界。

共享资源保存在 `assets/ui/medieval/`。该历史目录名不代表要恢复沉重的金属或皮革风格；页面统一引用共享 Theme 与 StyleBox，避免局部重新写一套配色。

战斗底部主面板是明确的布局例外：保留原有小地图、选择信息、生产与指令按钮的全部尺寸和分组，不套用菜单按钮的最小高度。其原生紧凑按钮使用 `battle_controls.tres` 等独立 Theme，只有底板换用纸卡纹理。顶部较高信息牌使用无叶角的 `card`，超长 `strip` 仅用于低矮横栏，避免叶梗在竖向延展。

## 原生动效约定

交互组织参考本机 [GodotGameUI 的 TweenNode](C:/Users/wh/Documents/GodotGameUI/scripts/tween_node.gd) 与 [TweenManager](C:/Users/wh/Documents/GodotGameUI/scripts/tween_manager.gd) 中的进入、悬停和显示分类。借鉴动效思路，使用本项目 Godot 4.6 的原生 API 重新实现。

| 入口 | 行为 |
|---|---|
| `UIMotion.bind_buttons(root)` | 递归且只绑定一次；鼠标悬停在 120ms 内轻微提亮并等比放大至 1.02，按压缩至 0.98；可见的键盘焦点仅提亮并保留原生焦点提示，不改变尺寸；鼠标产生的隐藏焦点不提亮 |
| `metadata/ui_motion_hover_scale = 1.0` | 紧凑槽位保持悬停尺寸，仅保留明暗与按压反馈；在绑定前写入场景 |
| `UIMotion.reveal(panel, direction)` | 180ms 展开；透明度与 0.985→1.0 等比缩放；独立面板默认位移 12px |
| `UIMotion.dismiss(panel, direction)` | 120ms 收起并隐藏；默认位移 8px |
| `Session.change_scene(path)` | 奶油纸页在 200ms 内展开、250ms 内收起，中央小地图不放口号或古风文字 |

保持柔和 EaseOut，不增加明显抖动、耀光或超过 3% 的缩放。Container 子面板不修改布局偏移。新的 Tween 开始前停止同属性的旧 Tween；隐藏、禁用或离树时恢复原始外观，避免位置累加。遵循 [Tween 官方文档](https://docs.godotengine.org/en/4.6/classes/class_tween.html) 的节点绑定与单属性单 Tween 约定。

菜单打开和返回时用 `grab_focus(true)` 记住键盘操作位置，不强行显示已按按钮的焦点底板。动效用 `has_focus(true)` 区分可见焦点与鼠标隐藏焦点，不能把所有 `focus_entered` 都当作悬停；同一控件的焦点可见性改变时也须刷新，失焦须取消尚未释放的按压动效。Tab、方向键仍由引擎显示原生焦点。这一划分参考本机 [bot-jump 的 InputMode](C:/Users/wh/Documents/bot-jump/scripts/input_mode.gd) 与 [AnimatedButton](C:/Users/wh/Documents/bot-jump/scripts/animated_button.gd)，具体实现使用 [Godot 4.6 的隐藏焦点 API](https://docs.godotengine.org/en/4.6/classes/class_control.html#class-control-method-grab-focus)。

转场期间遮罩接管输入，重复切场返回 `ERR_BUSY`；错误不能留下无法关闭的遮罩。CanvasLayer 的绘制顺序不改变 `_input` 分发顺序，因此转场同时暂时停用场景内原先启用的 `_input` 回调，完成后恢复，不暂停模拟或网络。动效忽略战斗时间倍率并在暂停时继续运行。`SceneTree.scene_changed` 表示场景已加载，`Session.transition.completed` 才表示转场结束、界面可再次操作；自动化测试连续操作时应等待后者。

## 字体分发与验证记录

标题字体来自 ZCOOL KuaiLe。字体原件和 `OFL.txt` 保存在 `assets/ui/medieval/fonts/`；Windows 构建脚本将完整许可复制为 `windows/FONT_LICENSE.txt`，并纳入发布 ZIP。许可原文随包提供，不改写或截断。

本轮已执行的相关测试记录如下。流程测试验证业务与场景衔接，不代替最终多比例素材的视觉验收。

| 检查 | 通过数量 | 已覆盖内容 |
|---|---:|---|
| `ui_motion_test.gd` | 36/36 | 打断、禁用、隐藏/可见焦点切换、失焦取消按压、紧凑控件、锚点与 Container 布局、纸页覆盖、暂停、重复切场及场景输入阻断与恢复 |
| `ui_menu_return_test.gd`（GPU，含截图） | 89/89 | 四个入口的鼠标关闭与 Esc 返回共 8 条路径；按钮尺寸、亮度、原生绘制状态完全恢复；Tab/方向键与 Enter 激活；下拉框 Esc 仅关闭下拉 |
| `rogue_transition_test.gd` | 30/30 | 战斗、结果、检查点与围剿之间的实际场景切换 |
| `rogue_flow_test.gd`（headless） | 38/38 | 原生地图点击、节点、编队入口与完整探索流程 |
| `rogue_lobby_test.gd` | 77/77 | 大厅入口、图鉴目录与返回路径 |
| `rogue_army_ui_test.gd` | 31/31 | 名册、阵位与招募交互 |
| `rogue_release_probe.gd`（源码运行） | 13/13 | 发布探针的完整场景及检查点链路；不代表本轮最终导出包已验证 |
| `network_game_expiry_test.gd` | 19/19 | 联机连接过期、暂停释放与退出回归 |

每次共享素材调整完成后，补做三个分辨率下的页面截图检查；最终导出后确认 ZIP 内包含字体许可，并运行导出包探针。所有验证辅助进程结束后以命令核实，保留用户正常编辑器。

2026-09-14 返回状态修复：真实鼠标操作确认，多人、单人和图鉴原先返回后仍有 `self_modulate=1.10`，设置在隐藏焦点下也会残留提亮。修复后四个入口返回并移开鼠标均为原始 `scale=(1,1)`、`self_modulate=(1,1,1,1)`、`DRAW_NORMAL`，无可见焦点；仍可通过原生键盘导航激活。另修正多人昵称输入框吞掉首个 Esc 的返回问题，保留下拉菜单原生 Esc 行为。未改动玩家设置、大厅偏好与肉鸽存档。Windows 包已重新导出，资源目录检查 233/233 通过。
