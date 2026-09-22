# 积木战争模式

入口：大厅 → **积木战争**。也可以运行 `Godot --path . -- --block-war`，或直接打开 `scenes/block_war/block_war.tscn`。

这是独立的单人据点争夺模式，对手由电脑控制。双方各有一座 60 人住宅，在「裂谷交汇」的 13 座建筑之间扩张。两条溪谷和四座石桥将战场分成三片区域。所有人口、建筑与行军规则只作用于此模式。

## 操作

- 从己方建筑按住鼠标左键拖到另一建筑并松开：向己方增援，向中立或敌方进攻。
- 左侧圆环选择派出 25%、50%、75%、100% 的驻军；数字键 1、2、3、4 分别对应这四档。
- 鼠标移到屏幕边缘或按住中键拖动来移动视角，滚轮缩放，空格聚焦选中的建筑。
- Q/W/E/R 施放技能。需要目标的技能在选中合法建筑时直接施放，否则等待点击目标；右键取消瞄准。
- Esc 暂停/继续；F1 打开/关闭玩法说明。暂停时产兵、行军、技能冷却和持续时间均停止。

## 建筑与攻防

| 建筑 | 功能 | 升级 |
| --- | --- | --- |
| 住宅 | 归属一方时每秒 +1 民兵；中立住宅不产兵 | 自动产兵上限从 200 增至 300/400，产速保持每秒 1 人 |
| 炮塔 | 自动拦截射程内的敌方行军部队，不产兵 | 一级射程 11、每 1.5 秒消灭 1 人；后续等级提升射程、射速与伤害 |
| 铁匠铺 | 每级为本方全军提供 +10% 攻击和守备，可叠加 | 最高三级，归属改变时加成立即转移 |

升级分别消耗 30、60 名驻军，最高三级；各级额外提供 0%、10%、20% 建筑守备。改建为其他类型消耗 30 名驻军并重置为一级。升级/改建不会破坏已发出的队伍。

民兵保持竖直长矛，逐排从门口出发，展开六列编队，转弯时收窄，到达时收拢入门。地形路径绕开沟壑、树干和建筑主体。不同阵营的部队在路上直接穿透；只有炮塔能够拦截路上的敌军。

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

建筑、地面和景观已完整重建。单位与建筑相对大小继续参考用户提供的《蘑菇战争 2》实机图，《皇室战争》只用于造型、配色与材质参考，不采用夸张比例。住宅改为蓝瓦白石据点，炮塔改为低矮石堡与独立炮身，铁匠铺采用青蓝瓦、高烟囱和可见炉膛。右侧旗帜继续标示阵营。详见 [环境方向](art/block_war_environment_direction.md)。

橡树、桦树、松树、垂柳四种树木与灌木、岩石、蕨、草、芦苇和两种花共十一套模型重新制作，通过根盘、分枝、树皮起伏、立体叶片和成组花草丰富自然林地。减少拥挤的装饰树林，保留全部 46 个导航树障碍；小植物采用分区 MultiMesh，模型离线生成原生 LOD。四座新石桥保留原有 6.4 米有效通行宽度，石岸限制在不可行走河床内。

地面采用自然草色与砂土过渡，取消明显草坪格。溪水、分层岩岸与林缘一起构成自然战场；原生程序化天空提供环境照明，配合暖日光、冷阴影和接触阴影。模式关闭角度软阴影与 SSIL，避免无 TAA 时的颗粒干扰。

本轮保留既有建筑本体 0.82、民兵 0.62 的模型缩放，不再放大建筑或士兵。六列编队的列距/行距为 0.56/0.90 米，导航净空为 2.1 米，并对全部路线进行完整模型落脚验证。

静态节点在 `.tscn` 中编辑。行军通过原生 MultiMesh 批量渲染，每名民兵独立结算；建筑旗帜、炉火、水流和 UI 的运动使用原生动画、shader 与 Tween。UI 动效参考同级 `GodotGameUI` 项目的渐显、缩放和交错播放方式，并复用本项目 `UIMotion`。

模式沿用项目的 4× MSAA，并临时关闭 TAA，避免人口标牌更新与细长矛运动的历史重影；离开模式时恢复之前的 TAA 设置。

建筑人口底牌由四个对称圆瓣与中央几何填充组成白色四瓣花，带轻微轮廓与阴影。人口、兵力条、派兵档位和冷却统一使用随项目打包的 Inter 600 等宽数字；四位以上人口会等比扩展花形，保留原字号。

原生能力参考：[AStar3D](https://docs.godotengine.org/en/stable/classes/class_astar3d.html)、[MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)、[Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)、[GPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html)。

## 验证

在仓库根目录执行：

```text
Godot --headless --path . --script res://tests/block_war_test.gd
Godot --headless --path . --script res://tests/block_war_input_test.gd
Godot --headless --path . --script res://tests/block_war_marches_test.gd
Godot --headless --path . --script res://tests/block_war_campaign_test.gd
Godot --path . --script res://tests/block_war_visual_review.gd --resolution 1600x900 --position 80,70
Godot --path . --script res://tests/block_war_motion_review.gd --write-movie artifacts/block_war_motion.avi --fixed-fps 30
```

逻辑验证包含真实拖拽事件、大厅进入/返回、人口守恒、双方穿行、炮塔、技能、暂停、队列抢救、电脑合流和完整战局。路径审查遍历全部 156 条有向建筑路线，检查六列民兵完整旋转模型的落脚范围。视觉复现输出在被 Git 忽略的 `artifacts/block_war_*.png`。

建筑与头像构建入口位于 `tools/build_war_architecture.py`、`tools/build_war_architecture.gd`、`tools/build_war_militia.gd` 和 `tools/render_war_portraits.gd`。

景观可重现构建顺序：使用安装了 numpy、trimesh、shapely 的 Python 执行 `tools/build_war_nature.py`，再通过 Godot 执行 `tools/build_war_nature.gd`（原生网格/LOD）与 `tools/bake_war_map_details.gd`（桥岸网格），最后 Python 执行 `tools/dress_war_map.py`（确定性场景布置）。运行时直接加载保存的 `.tscn` / `.res`，不生成景观节点；`dress_war_map.py --plan` 可只查看布置数量。
