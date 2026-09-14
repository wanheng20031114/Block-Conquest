# 单人肉鸽第一层实施记录

本文件同时记录并行实现的稳定接口。完整玩法按用户已批准的第一层方案。

## 模块所有权

- 状态与存档：`scripts/rogue/rogue_run_state.gd`、`rogue_session.gd`、`rogue_catalog.gd`、`data/rogue/`，以及 Session 挂载；状态测试。
- 战斗：`scripts/rogue/rogue_battle*.gd`、`scenes/rogue/battle*`、两张地图、实体定义覆盖；战斗测试。
- 编队与招募界面：`scripts/rogue/rogue_army*.gd`、`scenes/rogue/army*`，可复用条目场景和界面测试。
- 主实现：大厅入口、肉鸽主地图/开局/节点界面、美术、集成、打包和提交。

## 跨模块契约

`Session.rogue` 指向 `/root/Session/Rogue`，类型 RogueSession。它有 `state: RogueRunState`，`error_message: String`，`changed` 信号。

状态使用 `state.data: Dictionary`。稳定字段：`version, seed, phase, floor, strategy, pack, level, xp, gold, bread, ap, current_node, nodes, edges, roster, tickets, relics, active_node, battle_kind, emergency, pending_choices, last_result`。

- phase: `map`、`node`、`battle`、`siege_briefing`、`reward`、`intermission`、`game_over`。
- nodes: `{id:int, x:int, z:int, kind:String, completed:bool, ...节点固定内容}`。kind: `road, battle, emergency, shop, event, camp`。edges: `[[a,b], ...]`，直接使用4c坐标。
- roster: `{uid:int, kind:String, deployed:bool, layouts:{outpost:[x,z,yaw_radians], siege:[x,z,yaw_radians]}}`。outpost为出生点(-43,0,0)的局部坐标，范围[-12,12]；siege为地图中心坐标，范围[-12,12]，避开中央基地占地。新招募默认待命。
- tickets: `{uid:int, candidates:Array[String]}`；relics: `{relic_id:count}`。
- battle_kind为 `outpost` 或 `siege`；pending_choices为收藏品ID数组；last_result为可显示的中文结算摘要。

RogueSession 方法（Error返回OK或具体错误；UI从error_message读取说明）：

```
start_new(strategy:String, pack:String, run_seed:int=0) -> Error # 保存并进入肉鸽主场景
load_run() -> Error # 恢复并进入肉鸽主场景
save_checkpoint() -> Error
enter_node(id:int) -> Error # 扣AP、进入内容；战斗节点自动launch_battle
leave_node() -> Error # 完成节点、检查围剿、保存；不切场景
launch_battle() -> Error # 当前outpost或强制siege
resolve_battle(won:bool) -> void # 一次性结算并切回主场景；普通胜利自动完成节点保存；紧急待选择藏品
purchase(offer_index:int) -> Error
resolve_event(option:int) -> Error # 结算后保持结果页，等待leave_node
choose_camp(option:int) -> Error # 0行动/1面包/2藏品；等待leave_node
choose_relic(id:String) -> Error # 完成待选；紧急奖励自动leave_node，营地由UI退出
recruit(ticket_uid:int, kind:String, batches:int) -> Error
set_deployed(uid:int, value:bool) -> Error
set_layout(uid:int, encounter:String, layout:Array) -> Error
```

RogueRunState 查询：`population()->int`、`population_cap()->int`、`xp_required()->int`、`adjacent(id:int)->bool`、`node(id:int)->Dictionary`、`active_node()->Dictionary`、`deployed_units()->Array`、`unit_definition(kind:String)->UnitDefinition`（按战略藏品复制定义）。持久化/生成逻辑和数值集中本模块。

RogueCatalog 提供：`STRATEGIES`（id->name/description）、`PACKS`（id->name/units字典）、`RECRUIT`（kind->{bread,count}）、`RELICS`（id->{name,description,price}）、`NODE_NAMES`。战略ID `ranged,melee,range`；套餐ID `steady,ranged,mobile`；收藏品ID `melee_attack,ranged_attack,health,melee_armor,ranged_armor,range,speed,population`。数据常量可从可编辑资源载入。

军队界面 `scenes/rogue/army_panel.tscn` 根Control，脚本RogueArmyPanel，`open_panel(tab:String="formation", encounter:String="outpost")`、`closed`信号。内部通过Session.rogue调用接口，关闭时隐藏。formation标签支持两张战场切换，recruit标签显示券及三个候选和批量。

主场景路径 `res://scenes/rogue/rogue_map.tscn`，战斗场景路径 `res://scenes/rogue/battle.tscn`。所有模块避免覆写别人拥有的文件；更改接口先沟通。

## 实施状态

正在实现。未完成验证或平衡验收。
