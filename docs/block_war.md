# 积木战争模式

入口：大厅 → **积木战争**。也可以运行 `Godot --path . -- --block-war`，或直接打开 `scenes/block_war/block_war.tscn`。

这是独立的单人据点争夺模式，对手由电脑控制。双方各有一座 60 人住宅，在「裂谷交汇」的 13 座建筑之间扩张。两条溪谷和四座石桥将战场分成三片区域。所有人口、建筑与行军规则只作用于此模式。

## 操作

- 从己方住宅、炮塔或铁匠铺的本体或人口数字牌按住鼠标左键，拖到另一建筑本体或数字牌并松开：向己方增援，向中立或敌方进攻。同一目标可以连续派兵。
- 左侧圆环选择派出 25%、50%、75%、100% 的驻军；主键盘或小键盘的 1、2、3、4 分别对应这四档。拖动途中也能切换，滚轮每格增减 25%；底部和鼠标旁实时显示派出人数，松手采用最后选择的比例。
- 鼠标移到屏幕边缘或按住中键拖动来移动视角；未拖兵时滚轮缩放，空格聚焦选中的建筑。
- Q/W/E/R 施放技能。需要目标的技能在选中合法建筑时直接施放，否则等待点击目标；右键取消瞄准。
- Esc 暂停/继续；F1 打开/关闭玩法说明。暂停时产兵、行军、技能冷却和持续时间均停止。

## 建筑与攻防

| 建筑 | 功能 | 升级 |
| --- | --- | --- |
| 住宅 | 归属一方时每秒 +1 民兵；中立住宅不产兵 | 自动产兵上限从 200 增至 300/400，产速保持每秒 1 人 |
| 炮塔 | 自动拦截射程内的敌方行军部队，不产兵 | 一级射程 11、每 1.5 秒消灭 1 人；后续等级提升射程、射速与伤害 |
| 铁匠铺 | 每级为本方全军提供 +10% 攻击和守备，可叠加 | 最高三级，归属改变时加成立即转移 |

选中己方建筑后，底部直接显示升级按钮、目标等级和驻军消耗；不足时显示还差多少人，三级显示已满级。升级分别消耗 30、60 名驻军，最高三级；各级额外提供 0%、10%、20% 建筑守备。旁边的「改建」展开类型选择，消耗 30 名驻军并重置为一级。升级/改建不会破坏已发出的队伍。

已占领的炮塔自动拦截射程内敌方行军部队；一级至三级射程分别为 11、12、13 米，开火间隔为 1.5、1.2、0.9 秒，每发分别消灭 1、2、3 人。没有目标时保持待击，实际开火后才装填。中立炮塔不主动开火，炮塔也不会轰击建筑内的驻军。

民兵保持竖直长矛，从建筑朝向路径的一侧逐排出发，展开六列编队，转弯时收窄，到达目标周界时收拢结算。住宅、炮塔和铁匠铺均可从任意方向进出，无需绕到正门。地形路径绕开沟壑、树干和沿途建筑主体。不同阵营的部队在路上直接穿透；只有炮塔能够拦截路上的敌军。

进入己方建筑的民兵加入驻军。进入敌方或中立建筑的民兵按攻防倍率消耗守军；没有加成时一人换一人，需有一名幸存者才能占领。占领使建筑降低一级，最低为一级。增援可超过住宅自动产兵上限，超过后仅停止自动增长，不丢弃援军。

电脑遵守相同产兵、派兵和路径规则，优先扩张和集结。胜负要求某方没有建筑且没有仍在行军或等待出门的民兵，因此最后一支援军仍能夺回据点。双方都没有产兵住宅和可派遣人口时显示平局，可重开或返回大厅。

## 四项技能

| 快捷键 | 技能 | 效果 | 冷却 |
| --- | --- | --- | --- |
| Q | 征召军令 | 己方住宅立刻增加 30 名民兵 | 35 秒 |
| W | 疾行战鼓 | 全部己方行军速度提高 70%，持续 8 秒，包括持续时间内新发出的部队 | 28 秒 |
| E | 磐石壁垒 | 指定己方建筑受到的驻军伤害减半，持续 10 秒 | 45 秒 |
| R | 天降冲击 | 指定敌方/中立建筑受到 35 点基础驻军伤害，受守备减免；不能直接占领 | 60 秒 |

四项冷却独立，错误目标不消耗技能。壁垒在建筑失守时结束。

## 美术与动画

参考用户提供的两张《蘑菇战争 2》截图组织战场 UI：顶部细兵力条、左侧圆形派兵档位、底部四技能、左右阵营头像。头像由模式实际民兵模型原生渲染。人口花牌与 UI 保持独立于环境美术方向。

建筑、地面和景观已完整重建。单位与建筑相对大小继续参考用户提供的《蘑菇战争 2》实机图，《皇室战争》只用于造型、配色与材质参考，不采用夸张比例。住宅和铁匠铺采用阵营色瓦顶（橙金、青绿，中立砂灰），占领后立即换色；墙体、木门与旧铜保持自然材质。三类建筑均具有一至三级的独立网格，升级、占领降级和改建会立即更新外观：

| 类型 | 一级 | 二级 | 三级 |
| --- | --- | --- | --- |
| 住宅 | 木框矮屋 | 石砌住宅与单侧圆角翼楼 | 双圆角翼楼小堡 |
| 炮塔 | 低石台与轻炮 | 环形城垛与中炮 | 扶壁、护甲与重炮 |
| 铁匠铺 | 低木棚、短烟囱、炉体与铁砧 | 高石烟囱、加固梁架与木吊架 | 宽铁烟罩、双金属烟管与双工位 |

铁匠铺保留开放操作区、粗烟囱和可见工具，从高处也能与封闭住宅区分。详细模型与实机预览见 [环境方向](art/block_war_environment_direction.md)。

橡树、桦树、松树、垂柳四种树木与灌木、岩石、蕨、草、芦苇和两种花共十一套模型重新制作，通过根盘、分枝、树皮起伏、立体叶片和成组花草丰富自然林地。减少拥挤的装饰树林，保留全部 46 个导航树障碍；小植物采用分区 MultiMesh，模型离线生成原生 LOD。四座新石桥保留原有 6.4 米有效通行宽度，石岸限制在不可行走河床内。

地面采用低饱和草色与暖灰砂土过渡，取消明显草坪格。灰青溪水、暖灰桥石、分层岩岸与林缘一起构成自然战场。主场景和模型预览共用原生天空环境资源，以柔暖日光、天空补光和接触阴影统一明暗，降低高光与炉火溢光。模式关闭角度软阴影与 SSIL，避免无 TAA 时的颗粒干扰。

本轮保留既有建筑本体 0.82、民兵 0.62 的模型缩放，不再放大建筑或士兵。六列编队的列距/行距为 0.56/0.90 米，导航净空为 2.1 米，并对全部路线进行完整模型落脚验证。

静态节点在 `.tscn` 中编辑。行军通过原生 MultiMesh 批量渲染，每名民兵独立结算；建筑旗帜、炉火、水流和 UI 的运动使用原生动画、shader 与 Tween。UI 动效参考同级 `GodotGameUI` 项目的渐显、缩放和交错播放方式，并复用本项目 `UIMotion`。

模式沿用项目的 4× MSAA，并临时关闭 TAA，避免人口标牌更新与细长矛运动的历史重影；离开模式时恢复之前的 TAA 设置。

建筑人口底牌由四个对称圆瓣与中央几何填充组成白色四瓣花，带轻微轮廓与阴影。人口、兵力条、派兵档位和冷却统一使用随项目打包的 Inter 600 等宽数字；四位以上人口会等比扩展花形，保留原字号。

原生能力参考：[AStar3D](https://docs.godotengine.org/en/stable/classes/class_astar3d.html)、[MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)、[Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)、[GPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html)。

## 音效

模式使用 21 类专用事件、36 个 WAV 变体，涵盖选择、拖选、派兵比例、命令、取消与拒绝、行军脚步、交战、增援、占领与失守、升级改建、四种技能、暂停继续和胜败；炮塔沿用已有炮声。脚步按附近可见队伍抽样，战斗按事件限频，避免数百士兵同时触发声浪。声音使用原生固定声道池与距离衰减，遵守现有总音量、静音和暂停设置。

素材复用项目已有 CC0 录音，由 `tools/build_war_audio.py` 离线剪辑混合；来源和处理见 [音效说明](../assets/audio/CREDITS.md) 与 `assets/audio/block_war/audio_manifest.json`。

## 验证

2026-09-22：派兵输入专项 171 项、原输入回归 20 项、玩法 39 项、行军 27 项、战局 27 项和音频混音 58 项通过。路线专项 12 项遍历全部 156 对建筑，对六列完整模型进行 494340 次采样，无落河、撞树或穿墙。另使用 Vulkan 原生窗口检查地图、路径和比例提示画面；此轮截图和日志保存在系统 TEMP。

同日三级模型与升级修复：新增等级模型专项 522 项、炮塔专项 126 项、真实升级输入 50 项全部通过，并复核派兵输入 171 项、玩法 39 项、行军 27 项与战局 27 项。路线专项将九套模型的墙体合并检查，156 条路线、494340 次完整编队采样仍无落河或穿墙。Vulkan 实机确认九套模型、直接升级按钮、驻军不足提示及炮塔实际开火；70 个 GLB/RES 文件重建哈希一致。临时截图、日志在系统 TEMP，最终模型总览保存在 `docs/art/block_war_building_levels.png`。

在仓库根目录执行：

```text
Godot --headless --path . --script res://tests/block_war_test.gd
Godot --headless --path . --script res://tests/block_war_input_test.gd
Godot --headless --path . --script res://tests/block_war_dispatch_input_test.gd
Godot --headless --path . --script res://tests/block_war_upgrade_input_test.gd
Godot --headless --path . --script res://tests/block_war_tower_test.gd
Godot --headless --path . --script res://tests/block_war_building_levels_test.gd
Godot --headless --path . --script res://tests/block_war_routes_test.gd
Godot --headless --audio-driver Dummy --path . --script res://tests/block_war_audio_mix_test.gd
Godot --headless --path . --script res://tests/block_war_marches_test.gd
Godot --headless --path . --script res://tests/block_war_campaign_test.gd
Godot --path . --script res://tests/block_war_visual_review.gd --resolution 1600x900 --position 80,70
Godot --path . --script res://tests/block_war_architecture_visual.gd --resolution 1600x900 --position 80,70
Godot --path . --script res://tests/block_war_motion_review.gd --write-movie artifacts/block_war_motion.avi --fixed-fps 30
```

逻辑验证包含真实拖拽事件、大厅进入/返回、人口守恒、双方穿行、炮塔、技能、暂停、队列抢救、电脑合流和完整战局。路径审查遍历全部 156 条有向建筑路线，检查六列民兵完整旋转模型的落脚范围。视觉复现输出在被 Git 忽略的 `artifacts/block_war_*.png`。

建筑与头像构建入口位于 `tools/build_war_architecture.py`、`tools/build_war_architecture.gd`、`tools/build_war_militia.gd` 和 `tools/render_war_portraits.gd`。

景观可重现构建顺序：使用安装了 numpy、trimesh、shapely 的 Python 执行 `tools/build_war_nature.py`，再通过 Godot 执行 `tools/build_war_nature.gd`（原生网格/LOD）与 `tools/bake_war_map_details.gd`（桥岸网格），最后 Python 执行 `tools/dress_war_map.py`（确定性场景布置）。运行时直接加载保存的 `.tscn` / `.res`，不生成景观节点；`dress_war_map.py --plan` 可只查看布置数量。
