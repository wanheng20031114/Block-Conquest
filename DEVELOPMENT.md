# 积木战争开发约定

本仓库的唯一产品是积木战争，Godot 4.6.3，主分支 `main`。其余玩法属于 [Block-RTS](https://github.com/wanheng20031114/Block-RTS)，不得重新挂回本项目 Session 或菜单。

## 项目边界

- `scenes/lobby.tscn` 为首页，`scenes/session.tscn` 只持有设置、转场与菜单反馈。
- `scripts/block_war/` 为战斗、行军、AI、气势、指挥官技能和地图逻辑；`scenes/block_war/` 为原生菜单、地图和战场。
- `data/block_war/maps/` 保存六图定义，`data/block_war/routes/` 保存烘焙路由。
- `assets/block_war/`、`assets/models/block_war/`、`assets/ui/block_war/` 与 `assets/audio/block_war/` 为产品资源。通用字体、音效池、相机和菜单动效以本仓库副本维护。
- `tools/war_geometry.py` 只提供建筑与植被的离线几何工具；民兵烘焙输入位于 `assets/models/block_war/militia_parts/`，无需 RTS 的单位目录。

节点优先直接编辑 .tscn；使用原生 Control、Container、Tween、AnimationPlayer 和 Resource。保持已有战斗手感，不将菜单的长动效应用到战斗 HUD。

## 地图制作

1. `python tools/build_block_war_maps.py --definitions-only`
2. Godot 无头运行 `tools/bake_block_war_shores.gd`
3. Godot 无头运行 `tools/export_war_shore_support.gd`
4. `python tools/build_block_war_maps.py`（可加 `--map`）
5. Godot 无头运行 `tools/bake_block_war_routes.gd`

Python 美术制作依赖 numpy、trimesh、shapely；音效制作额外依赖 scipy。这些都不是运行游戏的依赖。缓存 .local/war_shore_support.json 可由上述第三步重建。

## 验证和发布

先运行 `python tools/validate_product.py` 检查独立产品边界和静态资源引用，再进行 Godot 导入及实际场景回归。无头命令须指定本项目内的 --log-file；测试应使用独立临时设置文件，避免覆盖玩家偏好。

重点回归：lobby_ui_test.gd、settings_test.gd、user_data_migration_test.gd、menu_motion_test.gd、block_war_menu_flow_test.gd、block_war_maps_test.gd、block_war_map_select_test.gd、block_war_test.gd 与改动涉及的技能/气势测试。原生渲染可使用 tools/run_godot_private_desktop.py，退出时会关闭自身进程树。

使用 tools/build_windows.ps1 导出独立 Windows 程序。测试、文档、源音频、离线工具和模型烘焙输入不进入成品。不要使用 Block-RTS 的网络内容指纹或发布检查器验证本产品。

按 AGENTS.md 在 main 上开发，以中文提交并推送。保留用户修改；任务结束前停止并命令核实所有验证进程，切勿关闭用户编辑器。
