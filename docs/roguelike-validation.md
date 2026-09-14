# 单人肉鸽第一层验证记录

日期：2026-09-14。引擎：Godot 4.6.3，项目使用 Godot 4.6 / Forward Plus。实现与接口见 [实施记录](roguelike-implementation.md)。以下区分规则正确性、真实战斗基线和导出检查，不将一次自动战斗样本解读为稳定胜率。

## 已完成的检查

| 检查 | 结果 | 主要覆盖 |
|---|---:|---|
| `tests/rogue_state_test.gd` | 614 / 614 | 100 个地图种子、三套餐人口、开局可达性、成长与叠加、招募批量、布阵、奖励幂等、存档损坏/版本/原子替换、围剿待触发、领奖阶段军队修改、独立难度存储与范围、事件概率默认随机序列 |
| `tests/rogue_army_ui_test.gd` | 31 / 31 | 真实面板、双地图编队、基地禁区、候选与批量、取消不扣资源、人口限制 |
| `tests/rogue_battle_test.gd` | 32 / 32 | 两张真实战场、出生与导航、驻守/搜索、胜负、紧急变体、围剿波次/上限/同帧失败优先、开场/跳过/暂停、65 单位合法指令 |
| `tests/rogue_lobby_test.gd` | 77 / 77 | 肉鸽大厅入口、开局跳转、现有入口和图鉴结构 |
| `tests/lobby_ui_test.gd` | 216 / 216 | 原大厅 UI 回归；已更新与现有图鉴类别及原生预览结构一致的断言 |
| `tests/balance_matrix_test.gd` | 2440 / 2440 | 原竞技模式数值矩阵及不可变基础资源 |
| `tests/balance_combat_test.gd` | 82 / 82 | 原战斗真实伤害与结算回归 |
| `tests/rogue_flow_test.gd`（headless） | 38 / 38 | 节点交互、商店/事件/营地、领奖、军队、强制围剿与阶段界面、资源调价后的显示和选项禁用 |
| `tests/rogue_flow_test.gd`（渲染） | 52 / 52 | 原生物理节点点击、地图平移/缩放、资源文案同步、截图、1280×720 / 1600×900 / 1920×1080 布局 |
| `tests/rogue_transition_test.gd` | 30 / 30 | 实际地图→普通/紧急战斗→领奖→围剿→失败读档→层间休整与读档 |
| `scripts/qa/rogue_release_probe.gd`（源码） | 13 / 13 | 发布启动入口、真实场景、模型、战斗返回、保存加载和层间状态 |
| Windows 导出目录/资源检查 | 233 / 233 | 导出资源清单、数值、6 张原地图、清单哈希；不是联机对战测试 |
| 导出 EXE 肉鸽 smoke | 13 / 13 | 在 Windows 导出产物中实际启动肉鸽、打开军队、进入两张战场、结算与读档 |

本次已核实的本地记录包括 `.local/rogue-flow-headless.log`、`rogue-flow-render.log`、`rogue-transition.log`、`rogue-lobby-entry.log`、`rogue-lobby-regression-corrected.log`、`rogue-release-source.log`、`rogue-windows-build.log` 和 `rogue-release-package.log`。这些是本地验证日志，不要求加入发行包。Windows 构建日志记录 `passed:true`、233 检查且无失败，导出 EXE 日志记录 13 检查且无失败。

渲染流程结果保存在 `artifacts/rogue/flow-results.json`，截图包括开局战略/初军、三种窗口大小的地图、商店、事件、收藏品选择、编队、招募、围剿简报、失败和层间页。战场截图及已复核的真实战斗报告见 [首轮战斗基线](../report/rogue-battle-baseline.md)。`artifacts/` 中的自动生成文件不代表长期性能报告。

## 平衡基线与限制

当前围剿资源为 1800 HP 基地、双甲 3、基础攻击 24、150 秒坚守、同时活敌上限 24；7 波在 10/30/50/70/90/110/130 秒生成 4/5/6/7/8/9/9 名敌军。前哨保留 5 塔 3 营，普通 16 名敌军、紧急 20 名；塔攻击 9 是基础值，仍保留原单位类别附伤，不能当作实际每击扣血。

首轮样本使用正式导航、动画和弹道，没有脚本扣血。远程战略下，稳阵、远射、机动三套 18 人口初军分别在 102.1 / 91.2 / 127.1 秒完成普通前哨站，存活 11 / 12 / 3 名。机动队虽通过，此样本伤亡明显更高。

1800 HP 围剿的首轮三套裸初军样本只通过稳阵；另有未固定战斗随机初相位的成长样本失败。为排除该差异，固定全局战斗种子 24681 后，同策略稳阵 Lv1 在 144.8 秒失败，Lv2 增派 3 名弓兵（21/25 人口）坚守成功，基地剩余 397 HP。该对照表明此样本能从成长受益，不能据此声称所有初军、所有种子均可稳定过关。

样本仅覆盖远程战略和简单自动指挥；近战/射程战略、更多种子、招募与收藏品组合、熟练玩家操作及长期经济曲线仍需继续调平衡。加速模拟用于取得战斗结果，不用于帧率、内存或性能结论。多人肉鸽、第二层及难度 2–5 不在本轮验收范围；首层围剿后保存到层间休整，不展示完整肉鸽结局。

## 复现

在项目根目录执行以下单项命令；测试均应自行退出。状态、流程和发布 smoke 使用独立测试存档，避免覆盖真实远征检查点；流程与发布 smoke 的存档路径含 PID，允许并行运行时相互隔离。

```powershell
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --audio-driver Dummy --script res://tests/rogue_state_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --audio-driver Dummy --script res://tests/rogue_transition_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --audio-driver Dummy --script res://tests/rogue_flow_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --path . --audio-driver Dummy --script res://tests/rogue_flow_test.gd
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --audio-driver Dummy -- --rogue-release-smoke
& './builds/windows/积木争霸.exe' --headless --audio-driver Dummy -- --rogue-release-smoke
```

固定种子围剿成长对照：

```powershell
& 'C:/Program Files/Godot/Godot_console.exe' --headless --path . --audio-driver Dummy --script res://tests/rogue_battle_balance.gd -- --siege-only --active-defense --growth --steady-pair
```

该命令写入 `artifacts/rogue_battle_balance_results.json`。报告中同时保留了旧 1500 HP 样本，复现时应以当前 `data/rogue/battles/siege.tres` 的 1800 HP 配置为准。验证结束按 `AGENTS.md` 核实并清理自己启动的辅助进程；只处理对应测试的 `--headless` / `--check-only` 实例，不关闭用户编辑器。
