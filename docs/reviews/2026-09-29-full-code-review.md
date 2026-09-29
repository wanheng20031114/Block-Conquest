# 全量深度代码审查

审查日期：2026-09-29。固定基线：[`3a0eecccd644e7f7951dccec7bd23950a5f27787`](https://github.com/wanheng20031114/Block-Conquest/tree/3a0eecccd644e7f7951dccec7bd23950a5f27787)。

本轮确认 **5 项 P2 功能缺陷**，并发现回归测试的过期断言及一项尚未通过的长战役回归。本文记录审查结果与修复方向，没有修改产品代码。

后续修复状态见 [深度审查修复复核](2026-09-29-review-fixes.md)。以下仍保留原审查基线与复现证据。

审查开始后，主工作区出现另一任务的并发修改，因此改用固定提交的隔离工作树进行验证。以下行号、结论与测试结果均对应上述基线，不将编辑中的中间状态计为缺陷，也不覆盖其他任务的改动。

## 范围与方法

- 人工分区审查 63 个客户端脚本与 4 个服务器脚本，沿输入、命令、模拟、事件、快照、HUD 与退出清理追踪状态变化。
- 检查 50 个产品场景的节点关联、6 张地图定义、烘焙路线、资源引用及相关 shader/资源配置；静态产品验证覆盖 197 个运行时源文件。
- 审查地图制作、资源烘焙、网络指纹、Windows 打包与 Relay 部署工具的输入输出和产品边界。
- 使用 Godot 4.7.2；功能验证采用无头运行，需要鼠标拾取或 GPU 输出的测试采用项目自带私有桌面验证器。测试使用独立用户目录或现有测试的临时设置文件。
- 对可疑点补充实际输入、固定步长和 Relay 状态机复现。原生网络测试仅连接本机并使用自生成测试证书。

## 1. [P2] 设置窗口未接管键盘焦点，可以误重开当前对局

位置：[scripts/game_settings.gd:125–128](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/scripts/game_settings.gd#L125-L128)。

`open_menu()` 只刷新、显示并播放设置窗口动画，没有把键盘焦点移入设置窗口，也没有限制焦点遍历范围。背景暂停菜单的按钮仍然持有焦点并接收按键。

复现：在战斗暂停菜单中，将焦点放到“设置”，按 Enter 打开设置，再按一次 Tab、一次 Enter。Tab 进入背景的 `PauseRestart`；Enter 无二次确认重开本局。设置窗口仍保持打开，玩家却已经失去本局进度。指挥官选择页同样可以通过背景“返回”切换到首页。

固定基线的完整战斗场景实测结果：

```text
OPEN ... settings_open=true
TAB ... PauseRestart
ACTIVATED game_closing=true settings_open=true
AFTER same_game=false settings_open=true
```

修复方向：打开设置时保存原焦点、把焦点移入设置页，并保证 Tab/Shift+Tab 不会遍历到背景控件；关闭后恢复合适的焦点。仅设置鼠标过滤不会解决键盘穿透。应补充实际按键打开、遍历、关闭设置的回归。

## 2. [P2] 房主在加载期间掉线，会丢失其他玩家的加载完成确认

位置：[server/war_relay_rooms.gd:303–306](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/server/war_relay_rooms.gd#L303-L306)；关联 [scripts/network/war_online.gd:269–271](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/scripts/network/war_online.gd#L269-L271)。

加载阶段房主断线后，房间进入 `host_lost`。如果仍在线的客端在此时完成加载，`_loaded()` 因阶段不是 `loading` 直接丢弃其确认。房主恢复后，这些客端只收到 `room` 消息；客户端只在本人收到 `member` 时重发已完成的确认。因此，即使所有人均已加载且保持连接，屏障仍缺少客端记录，最终到加载超时后全员退回房间。

复现顺序：双人房间开始加载 → 房主先确认加载 → 房主掉线 → 客端确认加载 → 房主用原身份恢复并重发确认。

```text
guest_loaded_during_host_loss phase=host_lost barrier={1:true}
host_restored phase=loading barrier={1:true} guest_connected=true
host_resent_loaded phase=loading barrier={1:true}
manually_resend_guest phase=match barrier={1:true,2:true}
```

最后一行是对照验证：额外补发客端确认后立即开局，证明阻塞源自丢失确认。现有正常加载、普通断线重连测试没有覆盖这一交叉时序。

修复方向：在 `host_lost` 且待恢复阶段为 `loading` 时保存合法确认，但不提前解除屏障；或让客端在房间恢复 `loading` 时幂等重发本局已完成的确认。补充掉线前、掉线中和恢复后完成加载的排列测试。

## 3. [P2] 护盾在到期帧提前失效，可能改变建筑归属

位置：[scripts/block_war/block_war.gd:298–301](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/scripts/block_war/block_war.gd#L298-L301)；攻击到达在同函数第 311 行推进。

`_simulate_step()` 先从护盾剩余时间扣掉整个时间步，并删除到期护盾，随后才推进部队和结算抵达。本时间步中较早发生的攻击因而也看不到护盾，即使攻击的实际抵达时刻早于护盾到期。

已使用游戏实际的 30 Hz 步长复现。隔离一个不产兵的目标建筑，驻军为 `0.8`，护盾剩 `0.02` 秒；一名敌兵距离终点 `0.031` 米，约 `0.01` 秒后抵达。两次试验初始状态与总模拟时长一致：

| 推进方式 | 最终归属 | 最终驻军 |
| --- | --- | --- |
| `simulate(1.0 / 30.0)` | 敌方 | `0.2` |
| `10 × simulate(1.0 / 300.0)` | 己方 | `0.05` |

这不是只有超长帧才能触发的问题；实际固定时间步内也会让应当挡住的攻击夺取建筑。

修复方向：把护盾到期时间纳入模拟分步边界，并在其最后一个有效区间的战斗结算后移除。只增加分步边界、仍在区间开头删除护盾，依然会提前失效。应回归保护到期前抵达、到期后抵达及不同分步大小下的建筑归属。

## 4. [P2] 平局判定遗漏熊可以用工具箱返还施工人口

位置：[scripts/block_war/block_war.gd:1075–1076](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/scripts/block_war/block_war.gd#L1075-L1076)；关联 [scripts/block_war/war_bear_skills.gd:42–48](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/scripts/block_war/war_bear_skills.gd#L42-L48)。

`_check_victory()` 只把住宅、改建中的住宅、至少一名完整驻军或在途士兵视为仍能推进战局，却没有考虑熊的工具箱能即时完成施工并返还一半建设人口。因此，双方没有可派整兵时，即使玩家仍有合法恢复兵力的技能操作，下一时间步也会提前结束为平局。

固定基线复现：熊仅剩一级炮塔、30 人，敌方仅剩能量塔、0.5 人，无行军。熊有足够技力且工具箱无冷却，合法升级炮塔后消耗 30 人。此时工具箱仍合法且能够返还 15 人，但等待一次 `simulate(1.0 / 30.0)` 就被判为平局。对照试验在推进前施放工具箱，立即获得 15 人，对局正常继续。

```text
BEFORE accepted=true refundable=true population=0.0
AFTER instant_toolbox=false finished=true winner=-1 population=0.0
TOOLBOX_CAST=true
AFTER instant_toolbox=true finished=false winner=-2 population=15.0
```

修复方向：将付费施工配合可用工具箱恢复人口的路径纳入僵局判断，避免在玩家仍有推进操作时终局。补充“升级耗尽最后驻军但可返还”和“确实没有任何恢复路径”的对照回归。

## 5. [P2] 奇数联机席位的攻击和增援路线颜色相反

位置：[scripts/block_war/war_overlay.gd:83–84](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/scripts/block_war/war_overlay.gd#L83-L84)。

拖兵路线使用 `FACTIONS.allied(game.hovered.faction, 0)` 决定友军颜色，把观察者写死为阵营 0。联机允许本地玩家处于任意合法席位；阵营 1、3、5 的玩家向己方或盟友增援时会看到攻击黄线，攻击阵营 0、2、4 时反而显示友军绿线。部队实际结算阵营正确，但预览对敌我的提示相反，直接误导下令。

这是由明确条件可静态确认的问题：奇数阵营与偶数阵营属于不同队伍，固定与 0 比较会反转奇数玩家的判断。

修复方向：按 `game.drag_source.faction` 或 `game.local_faction` 判断目标是否为友军；至少覆盖双方各一个席位的己方、盟友、敌方与中立目标。

## 测试质量问题

以下是测试期望与已实现功能不一致，不应误报为首页或图鉴功能损坏：

| 位置 | 现有断言与失败原因 | 建议 |
| --- | --- | --- |
| [tests/lobby_ui_test.gd:45](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/tests/lobby_ui_test.gd#L45) | 仍要求主菜单只有 3 个入口；当前已增加多人联机入口，在两种窗口尺寸各失败一次。 | 验证当前入口集合及动作，不沿用旧数量。 |
| [tests/lobby_diorama_test.gd:109](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/tests/lobby_diorama_test.gd#L109) | 要求版本为 `v1.0.1`，基线实际版本为 `v1.1.0`。GPU 重跑后其余拾取与悬停检查均通过。 | 从项目配置获得期望版本，并验证界面同步。 |
| [tests/codex_test.gd:243](https://github.com/wanheng20031114/Block-Conquest/blob/3a0eecccd644e7f7951dccec7bd23950a5f27787/tests/codex_test.gd#L243) | 假设按条目标题搜索只返回 1 条；新增能量塔摘要也包含“铁匠铺”，合法子串搜索返回多个结果，导致 1/1181 项检查失败。 | 验证目标条目存在且可选择，同时允许合理的相关搜索结果。 |

此外，`block_war_rabbit_integration_test.gd` 虽然报告 100 项断言全部通过，却出现两次 `MenuEntrance._after_layout()` 的脚本错误。该测试直接切换场景，使旧菜单在同一帧脱离树后仍收到布局回调。另用实际导航入口进行了 8 次转场、400 余次快速点击、66 项检查，未复现用户可遇到的菜单故障。应维护测试场景切换方式，并在运行器中同时检查脚本错误，而非只看退出码或 `failures=0`。

两个网络测试依赖被忽略目录中的固定证书路径，干净副本无法直接执行。本次使用 native 测试自生成的证书，仅替换临时测试副本中的证书路径后通过。正式测试宜自建临时证书，避免要求部署私钥才能运行。

## 尚未通过的长战役回归

`block_war_team_campaign_test.gd` 在独立运行、将执行器时限从 200 秒延长到 420 秒后，正常退出但报告 **84 项检查、1 项失败**。2v2 双河平原在模拟 317.65 秒结束；3v3 群岛长滩推进至模拟 1800 秒仍 `finished=false`，未满足测试的 30 分钟内结束要求。本次执行耗时 284.55 秒，最终失败不是外部超时导致。

没有发现可确认的最后士兵永久滞留路径。双方仍占有建筑和兵力；AI 的单波出兵门槛、优先支援和对同一目标的进攻互斥会延长围城，但尚未定位到独立的确定逻辑缺陷。因此保留为需要继续评估的 AI 收尾/测试时限回归，不把它与上述工具箱误判平局混为一谈，也不将其计入五项已确认功能缺陷。

## 验证记录

验证汇总见同目录的 `2026-09-29-verification.json`；其记录最终采用的执行方式、断言摘要及未执行项。

基线共有 67 个 `*_test.gd` 入口，本次执行 66 个：61 个通过且无脚本错误，1 个断言通过但产生上述菜单生命周期错误，4 个未通过（3 个过期断言、1 个长战役回归）；另 1 个发行包入口未执行。因此，本轮回归不能表述为“全部通过”。

- 产品静态检查：197 个运行时源文件，0 个产品边界或资源引用错误。
- 联机指纹：92 个文件，清单与基线一致。
- Python 地图/植被测试：13 项全部通过；使用现成离线依赖环境和经网格摘要校验的地形缓存。
- 六地图：5,205 项检查通过，全部建筑对路线可用，采样未发现离开地面；裂谷详细路线额外检查 430,860 个足迹采样，无穿墙或离地。
- 快照：1,263 项检查通过；增量复制 45 项通过；4,096 兵恢复压力测试 10 项通过。
- 原生本机 DTLS：41 项通过；安全负例 6 项通过，包括 2 类预期证书拒绝；六人传输负载 31 项通过。
- GPU：能量塔 HUD 67 项、驻军可见性 584 项、士气 HUD 654 项、出兵比例 89 项通过。
- 设置 37 项、迁移 19 项、技能技力 295 项、原生音频混音 88 项通过；其余玩法、队伍、技能和菜单回归的摘要保存在验证汇总。

本次没有重新导出 Windows 发行包，因此未运行要求隔离 PCK 的 `product_release_test.gd`。没有访问公网 Relay，也没有重跑所有音画素材生成和离线烘焙流程。并发任务在基线之后产生的修改不属于本报告结论范围。

## 建议处理顺序

先修复设置焦点穿透、加载屏障和错误平局，再修复护盾时序及联机路线颜色；随后更新过期测试断言，分析长战役收尾，并把上述复现场景加入回归。已有回归覆盖较广，但测试通过不能证明这些跨状态、跨时序条件正确。
