# 林间远征景观

三套景观均为独立、无脚本、无碰撞的原生场景，可用于作战、探索与节点预览：

- `scenes/rogue/forest_exploration.tscn`：100×72，遵循 34 节点、37 边的 4c 路网；西侧白桦溪谷、北侧松林、南侧阔叶林与露营角落。
- `scenes/rogue/forest_outpost.tscn`：112×64，西侧集结营地、中路车辙、上下绕行路和东侧哨站营地。
- `scenes/rogue/forest_siege.tscn`：80×80，中央营地、四个宽阔林间入口，四角树群与苔石地标。

白桦、松树、阔叶树、杨树、蕨、灌木、草、野花、蘑菇、树桩、倒木、根拱、苔石、围栏和帐篷均为真实顶点几何。每个模型保有独立 `.tscn`；草木簇用原生 `MultiMesh` 保存实例变换，减少绘制开销。

地面使用每米网格和顶点绘色。草土过渡、空地与双车辙都写在网格上；生成的手绘地面纹理以每 6 米重复的 UV 乘入顶点色，并启用线性 mipmap。`vertex_paint.tres` 和 `ground_paint.tres` 是可在编辑器中调整的共享原生材质。

战场实体碰撞仅放在 `battle_*_map.tscn/Environment/NaturalObstacles`，与导航烘焙来自同一坐标清单。导航源面保持 1m²，预留重型火炮 1.15m 半径；地图完整保留原有建筑、守军和入口 Marker3D。部署区及 AI 集结/搜索点避开高大装饰。

重新生成：先在 Godot 导入所引用的 PNG，再运行 `python tools/build_rogue_forest.py`。`tools/build_rogue_battles.py --maps-only` 是同一操作的兼容入口。该工具只写森林模型、地面、战场环境和导航，保留关卡参数、单位数值、战斗根场景及 HUD；地图关卡 Marker3D 会原样保留。

探索主场景集成时实例化 `forest_exploration.tscn`，移除旧 `Ground`、`Forest` 和 `Routes` 下的直条道路网格。保留 `Routes` 节点本身供现有地图显隐逻辑使用。

验证：`Godot_console.exe --path . --script res://tests/rogue_forest_test.gd` 会检查原生资源、GPU 草木实例数据、每米导航源面与入口可达性，自动退出并隐藏测试窗口。
