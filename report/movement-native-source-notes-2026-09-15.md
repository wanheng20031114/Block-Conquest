# 400 人沙盒交战：原生移动源码核对

2026-09-15。范围是用户确认的沙盒模式、约 400 个盾卫、火枪手等步兵。本笔记只核对项目、Godot 官方 4.6 文档及 `4.6.3-stable` 源码；没有运行新性能测试，没有修改运行时参数。历史 600 骑兵数据仅用于识别已经尝试过的方案，不能代替这次负载的基线。

## 已经存在的优化与真正调用范围

| 项目位置 | 当前行为 | 对本次调查的影响 |
|---|---|---|
| `project.godot:51–53` | 30 Hz、Jolt、物理插值 | 保留真实模拟频率进行测量 |
| `scenes/unit.tscn:36–39` | `CharacterBody3D`、`collision_mask=3`、`motion_mode=1` | 只碰地形和建筑；已经使用浮动模式，不运行 grounded 的贴地流程 |
| `scripts/battle_unit.gd:213–215,531–540` | 只转动 `ModelPivot`，角色根节点朝向归零 | 已经避免为人物视觉转身旋转碰撞体，不能再把这条作为新增收益 |
| `scripts/battle_unit.gd:226–230` | 单个直立胶囊，半径和高度来自单位配置 | 不是多个动画部件参与角色碰撞 |
| `scripts/battle_unit.gd:484–487` | 极低安全速度直接返回 | 静止单位已经跳过 `move_and_slide()` |
| `scripts/battle_unit.gd:491–505` | 空地证书开关默认关闭；正常走原生角色移动 | 不应把当前慢帧归因于每步正在扫描该证书网格 |
| `scripts/battle_unit.gd:511–523` | 实际位移更新观察速度和脚步，并同步发射音效信号 | `_apply_velocity` 包含碰撞调用之外的工作，应单独测原生子区间 |

浮动模式将接触视为墙面；默认 `max_slides=6`、`safe_margin=0.001`。这些是没有被当前场景覆盖的原生默认值。[CharacterBody3D 4.6 文档](https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html)

Jolt 的角色查询按发起方 mask 筛选目标 layer。因此单位间拥堵主要由项目的 RVO 决策处理，不能将密集队伍中的 `_apply_velocity` 耗时直接解释成角色之间做了两两接触求解。[4.6.3 移动查询过滤器](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/spaces/jolt_motion_filter_3d.cpp#L69)

## 原生调用链及应测阶段

`_apply_velocity → CharacterBody3D.move_and_slide → 浮动滑动循环 → PhysicsBody3D.move_and_collide → JoltPhysicsServer3D.body_test_motion → JoltPhysicsDirectSpaceState3D.body_test_motion`。

角色层的 `max_slides` 是上限；没有碰撞时第一轮即结束。每次成功碰撞会记录结果、计算余下运动，可能再次查询。把 6 改成 2 不会让空地移动少做三分之二的工作。[角色浮动移动源码](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/physics/character_body_3d.cpp#L399)

`PhysicsBody3D` 同时负责提交最终变换，所以只测 PhysicsServer 查询不能涵盖完整角色移动成本。[角色变换提交](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/physics/physics_body_3d.cpp#L109)、[Jolt 服务入口](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/jolt_physics_server_3d.cpp)

Jolt 每次查询先刷新待加入对象，然后做重叠恢复、运动扫掠、必要时提取接触结果。恢复最多按配置迭代，未命中即提前退出；扫掠先查 AABB 候选，实际命中才做距离细化；恢复或扫掠命中会触发接触提取。这几个阶段的占比不能从 GDScript 分析器直接读出。[Jolt 查询实现](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/spaces/jolt_physics_direct_space_state_3d.cpp#L861)

第一轮在现有构建里应记录以下数据，避免先编译改造整个引擎：

- `_apply_velocity` 总量、原生 `move_and_slide()` 子量、调用次数，统一按模拟步统计；另外记录每显示帧实际执行的模拟步数。
- 原生调用后 `get_slide_collision_count()` 为 0、1、2、3+ 的次数及对应累计耗时。它是返回碰撞结果的数量，并不是精确查询迭代数；最后一次无碰撞查询不会产生结果。
- 若只有少数墙边调用昂贵，对这些调用采样碰撞对象、法线、深度、输入速度和实际位移。避免每单位每步分配完整碰撞对象数组或输出日志。
- 只有原生部分仍占关键预算时，才用采样分析器或隔离引擎计时分别量 `flush_pending_objects`、恢复、扫掠、接触提取、变换提交。各阶段应记录调用/迭代/候选数量与时间，而不是只记录一个入口总数。

`flush_pending_objects` 处理新加入物体的批量提交；没有待处理对象时立即退出。因此它可能解释批量生成时的短峰，源码不支持把它先验认定为持续战斗的主耗时。[待加入对象提交](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/spaces/jolt_space_3d.cpp#L459)

## 三个候选及准入条件

| 顺序 | 隔离变量 | 什么时候值得测 | 必须守住的行为 |
|---|---|---|---|
| 1 | `motion_queries/use_enhanced_internal_edge_removal` 从 true 到 false | 原生查询占比确实高，且本负载碰撞对象主要是单个凸形状 | 全地图石块、拼合形状接缝、墙面滑动不得出现卡住、错误法线或异常速度 |
| 2 | `max_slides` 从 6 到 3，再考虑 2 | 3+ 碰撞调用贡献了明显耗时；若几乎全为 0/1，跳过该实验 | 凹角、沿墙斜行、窄门、较快单位多次接触不得提前停住或改变到达效果 |
| 3 | Jolt `motion_queries/recovery_iterations` 从 4 到 2 | 引擎侧测到恢复多轮确为热点 | 建造挤压、传送落点、旋转建筑边缘、出生重叠的恢复效果必须保留 |

第一项属于待验证候选，不是已经证明可以关闭：原生“增强内部边缘消除”用于缓解同一碰撞体内部的边缘接触，适用于三角网格，也适用于同一 body 的多个形状；它不是只对三角网格生效。[Jolt 边缘处理说明](https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html#ghost-collisions)

上述 Jolt 查询开关默认值分别为 true、恢复 4 次、恢复比例 0.4。`simulation/velocity_steps`、`simulation/position_steps` 属于另一组模拟参数，不能拿它们替代角色查询参数进行归因。第三项影响整个项目内的角色移动查询，应排在前两项之后。[4.6.3 参数注册](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/jolt_physics/jolt_project_settings.cpp#L58)

不把 `safe_margin` 调零作为优化候选：它定义贴近障碍时的恢复行为，不是关闭查询的开关。也不把“全部换成 Node3D”“去掉地形 mask”“直接改位置”作为本轮默认方案；这些动作需要新的碰撞语义，当前没有必要性证据。

## StaticMotionGrid 历史结果究竟证明了什么

当前实现使用 0.5 米占用格和前缀和，单位缓存其所在 2 米中心区域的安全或拒绝结果；新建、移动、改变碰撞形状等事件使版本失效。它已有 O(1) 矩形查询和跨步复用，并不是等待此次实现的缺失功能。证书成立仍会更新角色位置、物理对象和观察速度，仍保留原生单位间避让。位置提交和这些外围工作没有被消除。[当前实现](../scripts/navigation/static_motion_grid.gd)、[当前调用](../scripts/battle_unit.gd)

9 月 13 日的 `motion-cavalry` 记录：持续阶段 5.08 FPS / P95 236.61 ms，近景 4.90 FPS；同阶段 `clock-cavalry`、复测分别 9.25、8.55 FPS。最后一个采样点累计 fast=609,533、native=193,987，即约 75.9% 走直接积分。该场没有观察到其他验证进程，但仍有用户自己的正常编辑器/游戏。此前更早的两场 static-motion 有其他验证重叠，未纳入正式性能比较。[历史说明](battle-600-optimization-2026-09-13.md)、[历史原始数据](battle-600-optimization-2026-09-13.json)、[更早样本限制](battle-600-bottleneck-research-2026-09-13.md)

本次重新比较 `.local/battle-600-optimization-20260913/render-clock/source` 与 `fast-motion/source`：除场景开关外，`battle_unit.gd` 的追击类型化读取、测试采样字段也有差异。因此它证明的是**该历史构建没有整体收益**，并没有严格隔离“证书本身”的效应；不能把 FPS 差值直接当成该缓存的净成本。

从代码推断，快速命中率也不等于节约时间比例：它优先省掉空地上的便宜查询，墙边昂贵查询仍保留；证书检查、角色变换提交、RVO 和动画仍然存在。这些是合理解释候选，尚无逐分支计时证明哪项主导。若这次 400 步兵拆测显示原生移动确为关键，再做同源码、只改开关的 A/B 并单列 fast/native/证书耗时；不直接开启现有开关后宣称完成优化。

## 本笔记的边界

本笔记没有测得新的 FPS 提升，也没有更改生产行为。源码链接固定为官方 `4.6.3-stable` 标签；本机实际二进制的提交标识应在新的实验记录中独立保存，不能用同版本标签替代运行时身份。实际取舍以本轮 400 人沙盒的计时、未插桩 A/B 和必要的墙角回归为准。

## 补充：命令行 profiling 与编辑器分析器不是完整等价环境

在具有 `DEBUG_ENABLED` 的构建中，`--debug` 选择 `local://` 调试器；`--profiling` 在调试器有效时启用名为 `scripts` 的 profiler。其开关调用各脚本语言的 `profiling_start()`，所以确实启动与编辑器相同的 GDScript 函数计时基础设施；不是只打印已有 Performance 计数。[命令行开关](https://github.com/godotengine/godot/blob/4.6.3-stable/main/main.cpp#L3789)、[本地调试器](https://github.com/godotengine/godot/blob/4.6.3-stable/core/debugger/local_debugger.cpp#L48)

但输出链路及测量范围不同：

| 路径 | 启用内容与输出 |
|---|---|
| `--debug --profiling` | 本地 scripts profiler；约每秒读取当时的最近一帧脚本数据、排序并输出 stdout，退出时输出累计数据。这个“每秒输出”不是把一秒内所有帧求平均。 |
| 编辑器“分析器”开始按钮 | 通过远程调试连接启用 `servers` profiler；其中同时启用脚本计时，每帧整理服务器分项和脚本结果、序列化发送，编辑器接收并更新历史/图表。 |
| 编辑器“可视分析器” | 独立的 `visual` profiler；启用渲染服务器 CPU/GPU 分项采集，不等于上面的脚本开关。 |

编辑器开始普通分析时还传入 `debugger/profile_native_calls`，默认 false，决定是否单列从脚本发起的原生函数调用。本地 scripts profiler 不设置这个选项，独立进程的 GDScript 初始值同样为 false。关闭该选项不代表原生调用耗时从调用者墙钟计时里消失；打开后则增加原生调用的计时和记录工作。[编辑器发送配置](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/debugger/script_editor_debugger.cpp#L1352)、[服务器分析器](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/debugger/servers_debugger.cpp#L197)、[默认配置](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/settings/editor_settings.cpp#L1114)、[GDScript 原生调用计时](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/gdscript/gdscript_vm.cpp#L2053)

本次只读检查本机 `editor_settings-4.6.tres`，未发现上述原生调用开关及每帧函数上限的已保存覆盖；这不证明正在运行的编辑器没有未保存状态。正式 Release 构建的 GDScript profiling 实现被 `DEBUG_ENABLED` 条件编译保护，不能通过给 Release EXE 添加上述开关就宣称得到同等脚本剖析。[GDScript 开关实现](https://github.com/godotengine/godot/blob/4.6.3-stable/modules/gdscript/gdscript.cpp#L2220)

因此，本地 debug+profiling 对照可评估 GDScript 计时与本地输出的组合影响，不能直接量化截图中远程服务器采集、传输和编辑器界面的全部开销。Release 未复现截图尖峰也不足以证明 profiler 就是根因；还需对齐交战阶段、地图位置、队形、持续时间和实际开启的分析器，再作单变量比较。
