# 全面审查修复记录（2026-09-27）

对应 `report/code-review-2026-09-27.md` 的七项已复现缺陷，基于 `main` 的 `c4218f5` 修复。原审查报告保留为历史记录；本次没有修改用户已有的场景素材配置、删除项和无关未跟踪文件。

## 修复结果

| 原问题 | 本次改动 | 关键回归 |
| --- | --- | --- |
| P1 炮塔朝后导致整份快照拒收 | yaw 校验增加与 pitch 一致的 `0.00001` 浮点精度容差 | 原生 `aim_at()` 产生的正负 PI 经协议往返后均能更新客户端；仍拒绝明显越界、NaN 和无穷值 |
| P2 Bot 接管使真人命令序号落后 | 真人与 Bot 各自维护发送和接收序号，来源由可信本地调用参数指定 | 真人→Bot→真人后首条指令立即执行；旧包重放、伪造 payload 来源和越权单位请求仍被拒绝 |
| P2 房主重连未恢复最新席位状态 | 恢复 `start` 先同步 controller 与 Bot，再恢复运行；提前到达的生命周期事件按席位合并并在 roster 后应用 | 覆盖漏收接管、漏收玩家恢复、事件先于 start、最新暂停状态、断线清空缓冲；不重建现有对局 |
| P2 主动退出丢失 leave | 使用原生 `peer_disconnect_later()`；Session 继续服务退役连接，确认或最长 3 秒后销毁 | 真实本机 ENet/中继验证实际大厅关闭、模式切换、立即重连、延迟应答、同连接重新入房、房主离开和应用退出 |
| P2 建筑可放入树石 | 放置查询纳入地形层，仅排除场景中的支撑地面 RID | 1v1/2v2 可见树石拒绝建造，金币与工地数不变；建筑相邻间距、出生出口和采矿继续通过 |
| P2 三管短炮停在无法释放的位置 | 无有效前摇时，按预计释放距离允许车体继续追击，包括装填期间 | 对 1 米/秒撤退目标实际追击并开火；保留独立冷却、伤害和 HOLD 行为 |
| P2 超过 64 枚炮弹渲染越界 | 写入前按在途数量扩展 MultiMesh 容量 | 高原地图 22 座三级塔实发 66 枚炮弹；Vulkan 读取全部变换；缩小与清空后无多余可见实例 |

重连改动同时明确肉鸽敌方的 Bot 控制器身份，并同步复用 SkirmishBot 的测试宿主接口。未更改网络协议、内容清单或服务端部署。

优雅退出最多保留 4 条退役连接，容量满时新的主动连接返回 `ERR_BUSY`；意外断线仍走原重连路径。退出应用时也继续泵送可靠消息，总等待上限 3 秒。重连事件缓冲最多每席位一条，加一条暂停状态，不积累无限队列。

## 验证结果

Godot **4.6.3 stable**，Dummy 音频。以下最终运行共 **16 组、1,270 项检查通过**；其中 15 组为 headless，一组为原生 Vulkan/Forward+。测试输出和临时探针位于忽略目录 `.local/fix-*`，不提交。

| 测试 | 检查数 |
| --- | ---: |
| `cannon_tower_network_test.gd` | 29 |
| `network_reconnect_lifecycle_test.gd`（新增） | 40 |
| `network_command_validation_test.gd` | 193 |
| `network_game_expiry_test.gd` | 19 |
| `network_leave_test.gd`（新增，含两个独立 Godot 退出子进程） | 49 |
| `network_game_replication_test.gd` | 127 |
| `heavy_fortress_network_test.gd` | 32 |
| `triple_cannon_network_test.gd` | 40 |
| `bot_strategy_test.gd` | 181 |
| `rogue_outpost_ai_test.gd` | 34 |
| `rts_spawn_placement_test.gd`（1v1） | 74 |
| `rts_spawn_placement_test.gd -- --2v2` | 96 |
| `timed_production_research_test.gd` | 128 |
| `triple_cannon_battle_test.gd` | 92 |
| `block_war_tower_test.gd`（headless） | 131 |
| `block_war_tower_test.gd -- --large-volley-only`（Vulkan/Forward+） | 5 |

退出测试另以旧版立即断开实现作对照，实际大厅关闭路径稳定失败；修复版本通过。内容清单 `python tools/build_content_manifest.py --check` 通过（120 个资源）；`git diff --check` 通过。

测试夹具同步修正：Bot 假实体提供当前策略实际读取的单位定义；重连期限测试等待原生场景转场结束；建筑贴边检查临时排除树石以独立测量建筑间距，之后恢复正常查询并单独验证真实树石占地。headless 的 Dummy 渲染器不保存 MultiMesh 变换，因此变换读取只在实际 GPU 运行中断言。

## 验证边界与环境记录

- 本机退出回归使用实际 ENet、协议和中继房间逻辑，只跳过 DTLS socket 配置；重连回归通过真实 Game/RelayClient 注入指定协议顺序。没有进行公网 DTLS、发布包导出或完整跨机器对战测试。
- GPU 专项使用 NVIDIA GeForce RTX 3080 Ti、项目默认的 Vulkan/Forward+，只验证大规模齐射的容量、变换和可见数量，不代表完整视觉或性能验收。
- 早期额外选择 OpenGL Compatibility 的整套炮塔试跑触发 shader 实例变量硬件上限，已主动停止，不计入通过结果；随后默认 Vulkan 专项正常通过。没有为此修改项目渲染配置。
- headless 运行出现 Windows 根证书存储读取提示。原命令校验测试的 193 项断言通过，但其提前结束转场仍输出 Dummy 资源释放日志；没有把该测试退出日志认定为已修复的产品泄漏。
- 已通过 `Get-CimInstance Win32_Process` 核实全部测试、headless/check-only 和本次 GPU 验证进程退出；仅保留正常编辑器 PID 40668（`-e`）。
