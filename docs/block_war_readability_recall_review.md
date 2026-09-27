# 快捷键、劝返队形与满星光晕修复

2026-09-28，Godot 4.6.3，Windows / Vulkan Forward+。

## 修改

- Q/W/E/R、说明框内的 `[Q]` 等按键共用 Inter 字体。原 MSDF 渲染会在部分字母笔画交叠处出现裂纹。关闭该字体的 MSDF，保留原字体、字重与字号，使用原生栅格渲染。官方文档明确指出 MSDF 不正确处理重叠字形，且小字号缺少字体微调：[FontFile](https://docs.godotengine.org/en/4.6/classes/class_fontfile.html#class-fontfile-property-multichannel-signed-distance-field)。
- 兔子 E 沿原有的安全曲线反向行进，保留六列和前后排间距。选区外的部队继续原命令；范围内各阵营分别返回自己的最初来源。只改变行进方向，保留实际士兵对象、炮弹锁定和身上状态。返程预览、加减速区域和 AI 预判使用相同的行进方向。
- 地道出兵保留完整地面路线；露天部队被劝返后经过原桥梁回家，不会把地道出口当成返程终点。等待出洞的部队仍不受 E 影响。
- 增强满星原有白色光晕的渐变与亮边，保留缓慢呼吸。未满和空星不发光；不改变气势分数和加成规则。

## 验证

以下 10 组测试共 5796 项检查通过：

| 脚本 | 检查数 |
| --- | ---: |
| `block_war_recall_formation_test.gd` | 4410 |
| `block_war_rabbit_test.gd` | 192 |
| `block_war_rabbit_integration_test.gd` | 100 |
| `block_war_marches_test.gd` | 29 |
| `block_war_haste_test.gd` | 43 |
| `block_war_bear_test.gd` | 131 |
| `block_war_frog_test.gd` | 109 |
| `block_war_morale_hud_test.gd` | 647 |
| `block_war_departure_test.gd` | 91 |
| `block_war_ai_test.gd` | 44 |

队形测试在六张地图记录真实出征位置，再逐帧反向比对召回后的每位士兵，覆盖完整队伍、选区截断、地道返程与人口回收。已有兔子测试同时覆盖近门召回、来源失守、重复召回和未出发人口。

`block_war_skill_readability_visual.gd` 在从未切至前台的独立桌面完成原生 GPU 捕获；检查 1600×900、1280×720、960×540 的 Q/W/E/R、四张说明框、冷却、技力不足与就绪脉冲，以及满星、半星和空星的呼吸周期。全程 Dummy 音频，无系统键鼠输入。

- [快捷键与说明框截图](art/block_war_readability/shortcuts.png)
- [36 人保持阵型过桥返程，24 FPS](art/block_war_readability/recall.mp4)
- [满星光晕，真实尺寸与正常呼吸速度](art/block_war_readability/morale.mp4)
