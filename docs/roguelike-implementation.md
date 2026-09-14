# 单人肉鸽第一层实施记录

更新：2026-09-14。单人第一层已实现，并完成源码流程、渲染、战斗、存档及 Windows 导出产物验证。当前可以从大厅开始远征、探索节点、编队招募、完成前哨站与围剿，再保存到层间休整。第二层和多人肉鸽未开放，平衡仍处于首轮调试阶段。

验证结果与复现方式见 [肉鸽验证记录](roguelike-validation.md)。新版景观、完整作战底栏和可生产守军的验证见 [森林与守军更新记录](../report/rogue-forest-refresh.md)；[首轮战斗基线](../report/rogue-battle-baseline.md) 保留旧地图、固定敌军版本的数据。

## 已实现的玩法

- 开局先选三种战略之一，再选三套 18 人口的初军之一；初始等级 1、人口上限 20、金币 20、面包 3、行动力 12、招募券 1。初军全部出战，新招募单位进入不限人口的待命区。
- 森林地图使用 arc-nice 的固定 `4c` 拓扑：34 个节点、37 条双向道路，无角色小人。地图节点使用 3D 模型，金币、吐司、鞋子改用统一手绘卡通 PNG 图标，以原生 TextureRect 等比显示；收藏品位于下栏。鼠标选择节点预览，中键平移，滚轮缩放。
- 每图有 6 个普通作战、2 个紧急作战、2 个商店、4 个不期而遇、3 个营地，其余 17 个为道路（包含起点）。起点两步内保证普通作战、三步内保证营地，紧急作战不与起点直接相邻；距离按真实道路计算。
- 每走一条相邻道路消耗 1 行动力，允许回走。完成节点再次进入仅通行，不重开商店、战斗或奖励。地图内容清空不刷新、不直接触发层间休整；继续移动耗尽行动力后迎接围剿。
- 普通作战胜利获得 20 金币、2 面包、1 招募券、50 经验；紧急胜利为 30 金币、3 面包、1 招募券、80 经验，并额外收藏品三选一。升级所需经验为 `100 + (等级 - 1) × 50`，每次升级获得 1 面包和 5 人口上限。
- 商店货架固定为 3 件随机收藏品、2 张招募券和 1 份面包；售罄不能重买，离店不能再购物。营地提供恢复 3 行动力（上限 12）、2 面包或收藏品三选一。四种事件覆盖消耗行动力换补给、资源交换与招兵、收藏品选择、固定种子风险收益。
- 行动力为 0 时先完成当前节点的全部结算，再保存强制围剿状态并显示警报与简报。围剿胜利恢复至 12 行动力并进入 `intermission`；不会创建第二层地图，也不给经验、金币或其他可反复刷取的奖励。
- 任意战斗失败结束本局，不扣除军队名册中的单位，也不覆盖最近检查点；玩家可读档重试。战斗损伤不带出战场。

## 战斗、军队与数值资源

前哨站是难度 1 的专用横向地图，西侧部署，敌方固定 5 座箭塔、3 座兵营；普通初始有 16 名守军，紧急初始有 20 名，并对敌方生命/基础攻击应用 `+25% / +15%`。存活兵营会生产援军，敌军总数不再固定。`RogueOutpostAI` 继承普通 PvE 的 `SkirmishBot`，复用视野与短期记忆、目标优先级、编队命令和命令去重，独立管理守点、受击支援、搜索及新兵集结。初始驻军不使用禁止追击的 HOLD 命令。目标是同时清空敌方建筑与当前全部敌军，生产部队也计入胜利条件。

当前生产参数为：首次 50 秒，三个兵营依次错开 6 秒，此后各每 45 秒生产一名剑士、长矛兵或弓箭手；同时存活上限 28。普通箭塔 320 生命、兵营 440 生命。摧毁兵营立即停止该营生产，满员时跳过该次生产，不积压补刷；开场、暂停和结算后不生产。新增敌兵通过原生招募出口定位，享受紧急属性覆盖。这些是可编辑的首轮参数，不代表平衡已定稿。

进入时有原生相机动画、NPC 目标说明，以及可跳过开场和持续目标面板。底部恢复完整 RTS 主面板：小地图、选中单位模型与生命/属性、部队头像和翻页、1–9 编组及作战指令。难度是独立的 `1–5` 整数字段，与楼层和紧急变体分开保存；首版所有节点和两张战场均为难度 1，紧急作战不改变该值。

围剿使用中央大本营与四边入口的独立地图。当前资源中基地生命为 **1800**，双甲 3、基础攻击 24，坚守 150 秒；7 波敌军同时存活不超过 24。基地摧毁立即失败；士兵全灭仍能继续坚守，计时到点与基地毁灭同一步发生时失败优先。战斗只提供军队指挥、暂停与退出，没有建造、招募或经济经营。

每张招募券固定给出 3 个不同兵种，其中至少一个每批只需 1 面包。使用一张券选择一个兵种，一次招募 1–3 批；候选、价格和批量均显示在面板。所有单位保留稳定 `uid`，人口按原 `UnitDefinition.supply` 计算；4 门重型火炮即占满 20 人口。

招募券获得后立即弹出两轮三选一卡牌，不再存入库存或编队页。第一轮选择兵种，第二轮选择1、2、3批；资源不足呈灰色并保留深色文字。可返回重选固定候选，也可明确弃置。战后先显示金币、面包、经验、招募券与升级奖励，领取后进入招募，全部选择完成才结算节点。编队的出战/待命名册按兵种合并，支持框选、多选、整组移动旋转及双击转移，顶部统一显示人口。最新交互与验证见[更新记录](../report/rogue-recruitment.md)。

前哨站与围剿分别保存位置和朝向。初军前哨站默认前排近战、中排弓兵、后排攻城/支援，围剿默认环绕基地四侧；读档不会重新排列玩家阵位。布阵验证单位占地不越界、不重叠、不侵入基地及导航通道。

三种战略与 8 种收藏品只作用于复制出的单位定义，不改原竞技模式的 `BalanceCatalog`。同类百分比线性叠加；攻击百分比仅乘基础攻击，不乘类别附伤。远程步兵射程目前明确作用于弓箭手；全军近战护甲包括攻城器。

- `data/rogue/first_floor.tres`：独立 `difficulty=1`、开局、成长、奖励、战略、初军、招募、收藏品、商店、营地、事件和路线模板。雾中木箱的 `risk_chance=0.5` 也由资源提供，读取该参数不改变原节点随机流。
- `data/rogue/battles/outpost.tres`、`siege.tres`：专用战场、前哨站兵营生产与 AI 参数、基地与围剿波次；共用默认字段由 `RogueBattleDefinition` 提供。
- `scripts/rogue/rogue_outpost_ai.gd`：普通 PvE AI 的关卡适配，只替换前哨站经济和军队分工，不修改竞技模式。
- `scripts/rogue/rogue_run_state.gd`：纯状态与规则；`rogue_session.gd`：跨场景生命周期和磁盘检查点。
- `scripts/rogue/rogue_map.gd`、`rogue_army*.gd`、`rogue_battle*.gd`：地图节点、军队面板、独立战斗表现；主要 UI 和节点结构直接保存在 `.tscn` 中。

## 场景与美术资源

景观资源由 `scenes/rogue/forest_exploration.tscn`、`forest_outpost.tscn`、`forest_siege.tscn` 保存，可同时实例化到实际地图和节点预览。24 个原生模型包括四种树木、蕨草、花、蘑菇、苔石、倒木、帐篷及营地物资；地面以每米网格保存草土过渡、绕行路和车辙，并叠加生成的手绘纹理。小植被使用原生 MultiMesh。探索树冠按实际相机投影避开节点环及连线；战场导航保留每米源面及宽体单位通道。资源清单和再生成方法见 [景观说明](../assets/models/environment/rogue_forest/README.md)。

## 跨模块契约

`Session.rogue` 指向 `/root/Session/Rogue`，类型 `RogueSession`。它有 `state: RogueRunState`、`error_message: String` 和 `changed` 信号。大厅打开开局页面时允许 `state == null`；未开始状态不会自动生成远征。

状态使用 `state.data: Dictionary`。稳定字段：`version, seed, phase, floor, strategy, pack, level, xp, gold, bread, ap, current_node, start_node, nodes, edges, roster, pending_recruits, recruit_kind, recruit_return_phase, settlement, relics, active_node, battle_kind, battle_difficulty, emergency, pending_choices, pending_siege, last_result, next_unit_uid, next_ticket_uid, rng_counter`。

- phase: `map`、`node`、`battle`、`settlement`、`recruit_unit`、`recruit_batch`、`siege_briefing`、`reward`、`intermission`、`game_over`。
- nodes: `{id:int, x:int, z:int, kind:String, difficulty:int, completed:bool, resolved:bool, content_seed:int, result_text:String, ...节点固定内容}`。kind: `road, battle, emergency, shop, event, camp`。edges: `[[a,b], ...]`，直接使用 4c 坐标。
- 商店 `offers` 为 `[{kind:"relic"/"ticket"/"bread", price:int, sold:bool, relic_id?:String, count?:int}]`；`relic_id` 只用于收藏品，`count` 用于面包。事件固定 `event_id` 和 `risk_success`；营地、紧急战斗固定 `relic_choices`。
- roster: `{uid:int, kind:String, deployed:bool, layouts:{outpost:[x,z,yaw_radians], siege:[x,z,yaw_radians]}}`。outpost 为出生点 `(-43,0,0)` 的局部坐标；siege 为地图中心坐标。两图中心坐标均在 `[-12,12]`，还需为单位半径留边。围剿基地禁区半宽为 x=5.65、z=5.15，再加单位半径。东向朝向为 `-PI/2`（单位零朝向为 -Z）。
- pending_recruits: `[{uid:int, candidates:Array[String]}]`，只能处理队首，并不是可留存的券库存；recruit_kind为第二轮已选兵种，recruit_return_phase记录招募完成后返回的阶段；relics: `{relic_id:count}`。
- settlement: `{battle_kind, emergency, rewards:{gold,bread,xp,tickets}, claimed, levels, bonus_bread, bonus_population}`。战斗结果只生成预览，领取命令才增加资源，随后强制处理招募及紧急藏品。
- battle_kind 为 `outpost` 或 `siege`；battle_difficulty 为进入战斗时写入的 `1–5` 整数，前哨取目标节点难度，围剿取本层配置，首版均为 1。pending_choices 为收藏品 ID 数组；last_result 为可显示的中文结算摘要。

RogueSession 方法（Error返回OK或具体错误；UI从error_message读取说明）：

```
start_new(strategy:String, pack:String, run_seed:int=0) -> Error # 保存并进入肉鸽主场景
load_run() -> Error # 恢复并进入肉鸽主场景
save_checkpoint() -> Error
has_checkpoint() -> bool
enter_node(id:int) -> Error # 扣AP、进入内容；战斗节点自动launch_battle
leave_node() -> Error # 完成节点、检查围剿、保存；不切场景
launch_battle() -> Error # 当前outpost或强制siege
resolve_battle(won:bool) -> void # 一次性结果，胜利切回地图显示settlement
confirm_settlement() -> Error # 一次性发奖励，进入自动招募；所有选择完成才保存节点
purchase(offer_index:int) -> Error
resolve_event(option:int) -> Error # 结算后保持结果页，等待leave_node
choose_camp(option:int) -> Error # 0行动/1面包/2藏品；等待leave_node
choose_relic(id:String) -> Error # 完成待选；紧急奖励自动leave_node，营地由UI退出
choose_recruit_unit(ticket_uid:int, kind:String) -> Error
back_to_recruit_units() -> Error # 固定候选，不消费
confirm_recruit_batches(ticket_uid:int, batches:int) -> Error
discard_recruit(ticket_uid:int) -> Error # 只能弃置当前队首
set_deployed(uid:int, value:bool) -> Error
set_layout(uid:int, encounter:String, layout:Array) -> Error
set_deployed_many(uids:Array, value:bool) -> Error
set_layouts(encounter:String, changes:Array) -> Error # [{uid,layout}]，验证整组最终阵位后一次保存
```

`RogueRunState.start_new(strategy, pack, run_seed)` 只初始化纯状态，不保存、不切场景，供测试使用。查询包括 `population()->int`、`population_cap()->int`、`xp_required()->int`、`adjacent(id:int)->bool`、`node(id:int)->Dictionary`、`active_node()->Dictionary`、`deployed_units()->Array`、`unit_definition(kind:String)->UnitDefinition`、`formation_error(encounter:String)->String`。快照接口为 `export_checkpoint()`、`import_checkpoint(snapshot)`、`checkpoint_error()`。

`RogueCatalog` 提供 `STRATEGIES`（id→name/description）、`PACKS`（id→name/units）、`RECRUIT`（kind→bread/count）、`RELICS`（id→name/description/price/amount）、`EVENTS` 和 `NODE_NAMES`，从可编辑资源载入。战略 ID 为 `ranged,melee,range`；套餐 ID 为 `steady,ranged,mobile`；收藏品 ID 为 `melee_attack,ranged_attack,health,melee_armor,ranged_armor,range,speed,population`。

军队界面 `scenes/rogue/army_panel.tscn` 根Control，脚本RogueArmyPanel，`open_panel(tab:String="formation", encounter:String="outpost")`、`closed`信号，旧tab参数保留但固定显示编队。出战与待命按兵种堆叠，模型阵地支持原生拾取、框选、整组移动旋转与双击转移。`recruit_overlay.tscn`独立负责两轮三选一卡牌，`victory_rewards.tscn`显示不可变结算快照，两者只发信号给地图，由Session执行规则和持久化。卡牌使用独立tween，避免全局按钮动画重复缩放。

主场景路径为 `res://scenes/rogue/rogue_map.tscn`，战斗场景为 `res://scenes/rogue/battle.tscn`。

## 检查点与状态边界

单槽路径为 `RogueSession.SAVE_PATH = "user://rogue_run.json"`；`save_path` 可注入独立测试路径。存档封装为 `{format:1, snapshot:String, sha256:String}`，内部是版本 2 的纯 JSON 状态。版本1的券库存迁移为顺序强制招募队列，候选和随机状态保留。先写临时文件、刷新、回读校验，再原子替换旧文件；校验失败或写入失败明确报告，不会从存档实例化脚本或加载任意资源。JSON 数字在验证后恢复文档约定的整数字段。

保存时机：新局、退出节点、围剿胜利确认，以及地图/强制围剿简报/层间休整中的军队修改。来自安全检查点的开局或旧券队列，选择兵种、返回、招募和弃置均更新检查点。节点内的商店/事件招募和战后结算只改内存，待节点全部处理后保存；活动战斗和`game_over`不覆盖检查点。普通胜利等待领取及招募，紧急胜利还等待收藏品；营地领取后保留结果页直到离开。Session对每次命令保存前拷贝状态，保存失败回滚内存，且不发changed；整组布阵也原子成功或回滚。

AP 归零并不打断商店、事件、营地或战斗奖励；节点出口先把 `pending_siege=true` 与 `phase=siege_briefing` 写入检查点。读档必须恢复此状态。围剿胜利保存 `floor=2, phase=intermission, ap=12`，不生成下一层。重复战斗结算、重复领奖、重复消费已售罄商品均被状态层拒绝。

支持本项目版本1到版本2迁移，尚无多存档槽或跨设备同步。地图模板和商品等数据有明确校验；后续改变这些配置时仍需考虑版本升级或使用新局进行平衡测试。
