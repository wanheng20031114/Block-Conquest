# 全面代码审查（2026-09-27）

审查基准：`main`，提交 `525c622`，并包含审查开始时工作区中的现有文件状态。已 fetch 并确认本地与 `origin/main` 一致。本轮仅新增审查报告，未修改运行时代码，也未暂存用户已有的修改、删除或未跟踪文件。

确认 **7 项功能缺陷：1 项 P1、6 项 P2**。以下均有代码路径和本地专项复现支持；不是根据代码风格、猜测或旧报告推断。

## 1. [P1] 炮塔的正常朝向会导致整份网络快照被拒绝

- 位置：`scripts/network/match_replication.gd:754–755`。
- 关联：`scripts/defensive_gun_visual.gd:13–17`；`MatchReplication.receive_snapshot()`。
- 触发：联机对局中，炮塔通过原生 `aim_at()` 转向自身正后方，并保持该朝向。
- 原因：`Node3D.rotation` 的分量以单精度存储，实际 yaw 为 `-3.14159274101257`；验证器却用双精度的 `-PI = -3.14159265358979` 作为严格下界。发送端已经使用 `wrapf()`，但赋回节点后的精度转换仍越界。
- 影响：包含这座炮塔的整份快照被判为 `invalid_schema`，可见该塔的客户端无法更新单位、经济和迷雾。炮塔若一直保持该方向，冻结会持续，直到其转向或不再出现在快照中。
- 复现证据：实例化真实 `cannon_tower`，构建并经 `NetworkProtocol.encode/decode` 往返快照；调用 `gun.aim_at(gun.to_global(Vector3(0, 0, 10)), 2.0)` 后，`before_valid=true` 变为 `after_valid=false`。
- 建议：为 yaw 校验加入明确的浮点精度容差，或在序列化与验证边界统一角度规范；补上正负 PI 边界的编解码回归。

本地证据：`.local/review-network-turret.gd`、`.local/review-network-turret.stdout`。

## 2. [P2] Bot 接管期间推进的命令序号没有同步给重连玩家

- 位置：`scripts/game.gd:1338–1342`。
- 关联：`scripts/match_commands.gd:14–16,30–31`；`scripts/skirmish_bot.gd:172–173`。
- 触发：普通玩家断线超过 10 秒，Bot 已执行指令，然后玩家在重连期限内恢复。
- 原因：Bot 使用该 owner 的权威命令序号推进房主的 `_accepted`，客人的独立 `_issued` 停留在断线前。`player_reconnected` 仅切回 human 并删除 Bot，没有协调游戏指令序号。中继握手中的传输层 `command_sequence` 与这里的 payload `seq` 是两个计数器，不能修复这一差额。
- 影响：玩家的移动、建造等操作连续被拒为“重复命令”，直到发送足够多次追平序号。房主的接收处理还忽略了 `submit()` 的拒绝结果，玩家看不到失败原因。
- 复现证据：玩家命令 `seq=1` 已接受，Bot 再提交 5 条后房主 `accepted=6`；玩家重连下一条 `seq=2` 返回 `{"ok":false,"error":"重复命令"}`，`pending=0`。
- 建议：在控制权恢复时同步权威命令计数或建立新的命令会话，并保留去重保护；覆盖真人→Bot→真人的完整指令流程。

本地证据：`.local/review-network-lifecycle.gd`、`.local/review-network-lifecycle.stdout`。

## 3. [P2] 房主恢复连接时没有应用最新席位控制状态

- 位置：`scripts/network/relay_client.gd:294–300`。
- 关联：`scripts/game.gd:1333–1348`；`scripts/network/match_replication.gd:109–112`；`server/relay_server.gd:675–678`。
- 触发：房主断线期间，其他玩家进入 Bot 接管状态、离开或恢复连接；房主随后在 30 秒内恢复。
- 原因：房主离线时无法收到控制权变更事件。恢复握手的 `start.config` 含有最新 roster，但接收端只更新私有 `_match`，未将 controller 应用到已有 `Game.players` 或重建/移除 `bots`，却立即解除暂停。
- 影响：可能留下本应由 Bot 接管却无人控制的阵营；反向情况则是真人已重连，但其部队仍由 Bot 控制，并因游戏内 controller 仍为 bot 而不再获得快照。
- 复现证据：给已有真实 Game 发送恢复 `start`，结果为 `relay_controller="bot"`、`game_controller="human"`、`has_bot=false`、`paused=false`。
- 建议：恢复对局前用中继的最新 roster 对现有权威模拟做一次控制权同步，之后再恢复处理；同时覆盖错过接管事件和错过恢复事件两条路径。

本地证据：`.local/review-network-lifecycle.gd`、`.local/review-network-lifecycle.stdout`。此问题与第 2 项分别属于席位状态和指令序号，需独立修复。

## 4. [P2] 部分主动退出路径会丢失 leave 消息，使席位滞留

- 位置：`scripts/network/relay_client.gd:192–200`。
- 直接调用路径：`scripts/lobby.gd:201–204`，以及部分切换单人模式和退出游戏流程。
- 触发：已加入房间的玩家按 Esc 关闭多人面板；调用方连续执行 `leave_room()` 和 `disconnect_relay()`。
- 原因：`leave_room()` 仅将可靠消息加入 ENet 队列，随后 `peer_disconnect_now()` 和连接销毁会丢弃尚未发出的消息。可靠标志并不保证队列在销毁前已发送。
- 影响：服务端按意外断线处理。普通玩家席位保持 human/未连接最多 120 秒，房主不能替换该席位，准备检查也无法通过；房主离开则使其他玩家等待 30 秒超时，而不是立即收到正常离开结果。
- 复现证据：真实本地 ENet 双端连接按原顺序执行，服务端得到 `disconnected=true, operations_received=[]`；对照组先提交并收到 leave，再断开，得到 `operations_received=["leave"]`。
- 建议：为主动退出设置明确的可靠发送/优雅断开顺序，避免立刻销毁待发控制消息；对实际关闭面板和退出路径加入回归。仅添加发送调用而不处理立即销毁的顺序问题不足以解决。

本地证据：`.local/review-network-leave.gd`、`.local/review-network-leave.stdout`。

## 5. [P2] 建筑放置校验漏掉地图树木和岩石

- 位置：`scripts/game.gd:98`，关联 `536–540`。
- 触发：在已经侦察到、没有其他单位或建筑遮挡的树石占地上放置建筑。
- 原因：放置检测掩码是 `6 | 128`，未包含地形层 1；地图 `NaturalObstacles` 中的树石位于层 1，且该函数没有其他地形占地校验。
- 影响：不合法占地被认定可建造，实际命令也复用该校验，会扣款并把工地放入树石内，导致场景重叠及施工/通路问题。
- 复现证据：初始 1v1 视野内发现 10 处树石中心返回允许建造。例如 `tree_pine_040` 的 `(-28, 0, -2)` 和 `rock_medium_046` 的 `(-34, 0, 1)`，`placement_error(at, 0, "defense_tower")` 返回空字符串。
- 建议：让放置检测准确覆盖自然障碍物，同时区别可建造地面，避免简单包含整块地面后把所有位置都判为占用；补地图树石的实际占地案例。

本地证据：`.local/review-combat/probe.gd`、`.local/review-combat/godot.log`。

## 6. [P2] 三管短炮追击慢速撤退目标时无法进入开火距离

- 位置：`scripts/unit_battery.gd:64–72`。
- 关联：`scripts/battle_unit.gd:305–306,578–597`。
- 触发：目标已经进入当前射程，但按照其撤退速度，预计在炮管前摇结束时又会离开射程。
- 原因：所有炮管因 `_can_start_strike()` 为 false 跳过发射，`engage()` 最后仍返回 true。主单位据此走炮组瞄准分支，跳过原本负责追击的移动分支，即使没有任何炮管处于前摇。
- 影响：炮车在最大射程附近反复停走，追得上慢速目标却不能开炮。
- 复现证据：目标剑士从距离 8.3 以 1 米/秒撤离，炮车速度 2.4，连续追击 8 秒 `shots=0`，间距约 8.38；初始状态为 `range=true, release=false, preferred=(0,0,0), winding=false`。
- 建议：区分“炮组正在占用单位动作”和“仅发现射程内目标”，在没有有效前摇且需要进一步接近时允许追击；避免为了修复而破坏各炮管的独立冷却。

本地证据：`.local/review-combat/probe.gd`、`.local/review-combat/godot.log`。

## 7. [P2] 积木战争炮弹超过 64 枚时渲染越界

- 位置：`scripts/block_war/war_effects.gd:68–72`；容量设置在 `24` 行。
- 触发：大地图中，多座高级塔同时发射，使在途炮弹超过 64 枚。环湖高原有 37 座可改建建筑，22 座三级塔各发射 3 枚即可达到 66 枚。
- 原因：炮弹 MultiMesh 固定为 64 个实例，`render_projectiles()` 却遍历全部炮弹，且没有像同文件伤亡渲染那样按数量扩容。
- 影响：超额炮弹无法正常显示，但仍参与伤害结算；变换写入与可见数量更新越界，后续渲染继续报错。
- 复现证据：在实际 highland 场景配置 22 座合法三级塔和各自射程内已出发的敌军，调用真实 `_fire_tower()` 后得到 `projectiles=66, capacity=64, visible=63`；引擎记录两次实例变换越界和一次可见数量超限。
- 建议：绘制前按实际在途数量扩展实例容量，并覆盖大地图多塔齐射的上界场景。

本地证据：`.local/review-block-war-projectile-cap.gd`、`.local/review-block-war-projectile-cap.log`。

## 审查与验证范围

静态审查覆盖联机中继、会话、命令验证、快照复制、RTS 战斗/生产/放置/导航、积木战争战斗/行军/AI/技能、肉鸽状态与存档、MOBA 流程，以及大厅/设置/场景切换/导出配置。额外扫描了 `scripts`、`server`、`scenes`、`data` 中 382 个脚本或文本资源文件的固定 `res://` 引用；扫描涉及的脚本约 26,639 行。此计数表示引用检查范围，不代表对每一行都做了动态验证。

使用 Godot **4.6.3 stable**，Dummy 音频和 headless 模式。以下 **14 个现有测试、1,999 项检查全部通过**：

| 测试 | 检查数 |
| --- | ---: |
| `settings_test.gd` | 162 |
| `rogue_state_test.gd` | 776 |
| `moba_test1_test.gd` | 68 |
| `block_war_menu_flow_test.gd` | 45 |
| `block_war_map_select_test.gd` | 54 |
| `block_war_departure_test.gd` | 91 |
| `block_war_rabbit_rush_test.gd` | 55 |
| `block_war_ai_test.gd` | 44 |
| `block_war_rabbit_test.gd` | 192 |
| `block_war_ai_skills_test.gd` | 178 |
| `block_war_team_campaign_test.gd` | 84 |
| `timed_production_research_test.gd` | 128 |
| `rts_spawn_placement_test.gd`（1v1） | 53 |
| `triple_cannon_battle_test.gd` | 69 |

联队回归中的 rivers 和 islands 分别在 359.4 和 665.45 个模拟秒后正常结束。专项探针另行覆盖上面七项缺陷，不计入通过的 1,999 项现有检查。

验证限制与环境说明：

- 肉鸽状态测试第一次因沙箱不能写入 `user://` 测试存档而失败；仅把临时测试副本的存档路径改为 `res://.local/review-rogue-state.json` 后完整通过 776 项。生产代码和用户存档未改动。
- 部分 headless 运行输出 Windows 根证书存储读取失败；本轮没有据此判断产品的联网故障。离开消息使用本机 ENet 双端实测，重连生命周期和炮塔快照使用真实游戏对象/协议的最小探针，没有连接公网中继。
- 网络生命周期探针退出有 Dummy 渲染资源释放日志；未将单次测试夹具退出日志直接列为产品内存泄漏。
- 未运行所有历史测试、发布包导出、公网 DTLS 端到端回归、GPU 画面检查或大规模性能基准。因此本报告不作这些方面的通过结论。
- 现有测试通过不覆盖上述边界：放置测试未检查地图树石，炮组战斗测试未检查慢速撤退，联机常规流程未完整覆盖接管/恢复状态交接及单精度 PI 边界。

所有临时探针和日志保存在忽略目录 `.local/`，不包含在本次提交中。结束前已用 `Get-CimInstance Win32_Process` 核实：`--headless` / `--check-only` Godot 剩余 0，本次启动的测试与辅助进程均已退出；保留原有正常编辑器 PID 40668（`-e`）。

后续清理：已按用户要求删除本轮临时探针、日志及测试输出；上文 `.local/` 路径仅记录当时的复现证据位置，不再保留文件。审查结论、修复报告和正式回归测试保留。
