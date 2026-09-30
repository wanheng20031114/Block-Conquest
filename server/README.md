# 积木战争 Relay

1.3.3 Relay 只管理房间、身份、加载屏障、参与权限和转发。开房者是战斗 Host，可以坐在任意位置；`player_id`、原生 ENet peer、位置和阵营没有固定相等关系。服务器不持有战斗世界，不运行 AI，也不在 Host 退出后接管仿真。

## 运行

原生 Godot `ENetConnection`，六个通道，UDP **42300**，每条连接启用 **DTLS**。客户端验证随发行包提供的 `scripts/network/relay_trust.crt` 和固定名称 `block-conquest-relay`，不使用不安全 TLS 模式。私钥只放在忽略的 `.local/network/` 和服务器权限为 `0600` 的配置目录。

服务端及客户端发行模板使用 **Godot 4.7.2**，避免 4.6.3 的 DTLS cookie 析构缺陷。`tools/deploy_block_war_relay.py --runtimes` 下载并核对固定 SHA256；`--templates` 另核对官方 `SHA512-SUMS.txt`，只提取所需 Windows release/debug 和 Linux release 模板。不会替换用户安装的 Godot。

本地开发可用：

```powershell
$env:BLOCK_CONQUEST_RELAY_CONFIG = 'C:/absolute/path/relay.cfg'
godot --headless --path . --script res://server/relay_main.gd
```

```ini
[relay]
bind="127.0.0.1"
port=42300
max_rooms=32

[tls]
private_key="C:/absolute/private/relay.key"
certificate="C:/absolute/private/relay.crt"
```

`server/relay.tscn` 是预搭的启动场景。生产部署复制独立的服务器工程配置，不加载游戏场景或 Session。Tokyo 生产默认最多 **8 房间**，每房最多 6 名真人，额外 32 个原生连接用于握手/重连；容量配置可为 1–64，但须依据服务器资源实测。无身份连接 15 秒握手超时，已握手连接 8 秒无心跳会断开，空闲大厅 15 分钟关闭。

## 身份、房间与恢复

- 首次握手验证协议版本和 `data/block_war/network_manifest.json` 内容指纹。地图、路线或战斗规则变化需重建清单并同步部署。
- 每张地图有固定的 2/4/6 个席位。任意席位可放电脑，真人可以移动到空位或与电脑交换位置。已有真人不能被房主静默覆盖，缩小地图也不能挤掉真人。
- 角色、地图、席位变化清除所有真人准备状态。全部席位有人或电脑、全部真人准备，房主才可发起加载。全部真人确认同一对局/内容后才开局；60 秒加载超时退回房间。
- 首次入房发放 256 位随机重连凭证，仅在受保护连接内发给本人，保留在客户端内存。重连时换发新凭证，客户端确认收到前保留上一份，以便握手回复丢失后仍可恢复。原连接立即失去权限，迟到的断线事件不能撤销新连接。
- 普通真人掉线马上撤销控制，10 秒后由 Host 的电脑接管，120 秒内可恢复同一身份和阵营。恢复镜像完成前，控制者为 `reconnecting`；Host 调用 `complete_recovery(player_id, recovery_epoch)` 必须匹配建立该快照时的控制权版本，旧连接的迟到确认不能放行新连接。
- 投降由 Host 计算并提交，再调用 `confirm_surrender(player_id)` 持久确认本局参与权限。Relay 单向记录 `surrendered=true`，撤销指令和鼠标发布权限；Host 自己投降后仍可发送所有权威结果。观战者保留接收战況和发送时钟 ACK / 恢复请求的权限，断线、10 秒接管期限、120 秒身份失效、主动离开和 Host 恢复均不能使其复活为参战者或 AI。
- 正在恢复的观战者保持 `reconnecting` 直到快照确认，再恢复为 `spectator`。补发此前尚未送达的投降确认不改变这次恢复的 epoch；重复确认幂等。回大厅清空投降标记，新局重新建立权限。资产转移、驻军损失、暂停规则和团队胜负均属于 Host 游戏计算，中继不重复实现。
- 进行中非 Host 主动离开视为投降请求：中继立即解绑连接并销毁原凭证、返回 `left`，同时保留原 `kind=human/player_id`，记录 `forfeit_requested=true`、`connected=false/controller=spectator`。退出者可以立即进入其他房间；原房间 Host 在暂停时也需处理这份待办，完成资产转移/胜负后调用 `confirm_surrender`，中继才释放旧身份并保留不会运转的 `kind=bot/controller=spectator` 席位。该待办随房间状态持久送达，Host 断线不会丢失，也不因普通 120 秒重连期限而变成 AI。回大厅或关闭房间会清理未处理身份。
- Host 掉线时阶段变为 `host_lost`，允许同一进程 30 秒内恢复，并要求远端重新同步。超时或主动离开明确关闭房间；无 Host 迁移。短暂断线仍按 10 秒电脑代管/120 秒重连机制处理；加载、大厅及结算后的离开也不创建进行中的投降待办。
- `host_lost` 是掉线前阶段的包装：大厅中的离开仍释放空位，加载阶段仍等待所有未离开真人完成加载。Host 离线期间收到的其他玩家加载确认会保存，Host 回来后即按已有确认检查屏障，无需客机重发；Host 未回来时不会提前开局。10 秒电脑代管仅适用于正在进行的战斗，不会因 Host 在大厅、加载或结算时掉线而提前启动。
- 多名玩家同时退出时，每个待办分别持久保存。若处理第一份请求已导致结算，Host 仍应对剩余 `forfeit_requested` 身份发送确认以完成清理；这只是清理已离开的身份，不重新计算结局或转移已结束的战场资产。
- 对局中拒绝陌生人加入。Host 返回大厅保留房间与角色，但清掉准备、对局编号和复制队列；下一局使用新的随机编号。

## 通道和边界

| 通道 | 模式 | 消息 |
| --- | --- | --- |
| 0 | reliable | 房间、握手、加载、控制权、鼠标显示/隐藏 |
| 1 | reliable | 玩家 command、command_result、ack、resync |
| 2 | reliable | events、digest、time、finished |
| 3 | unsequenced | 队友鼠标移动 |
| 4 | unsequenced | anchors |
| 5 | reliable | snapshot_begin/chunk/end |

所有消息为有界 JSON 基础数据，禁止对象反序列化、NaN/Infinity、深于 16 层或过多值。整包 64 KiB，房间/指令 4 KiB，鼠标 1 KiB，不可靠整包最多 1200 字节避免隐式分片。JSON 使用完整浮点精度；运行状态摘要还必须归一 JSON 整数与浮点数的数值类型。

Host 入口上限为 1000 包/秒和 1 MiB/秒，普通客户端 120 包/秒和 32 KiB/秒；令牌桶容许 3 秒合法抖动积压。指令另限 40 次/秒，房间请求 15 次/秒，鼠标 40 次/秒。先依据实际连接权限/通道/长度拒绝大包，再解析。低权限客户端只可发送命令及 ACK/重同步请求，不能广播战斗结果或自报身份。

恢复分块在 Online 中以 256 KiB/秒发送，突发 64 KiB；可靠待发恢复队列上限 8 MiB，超限明确报错并断开，绝不无声丢掉关键消息。命令和房间控制不排在恢复队列后面。上层复制器还需有自己的队列上限及更低的发布预算；它可调用 `abort_connection(reason)` 安全终止房间并给玩家明确原因。可靠转发后立即 `flush()`，仍保留 ENet 自身拥塞控制。服务器每 30 秒只记录房数、连接数和收发累计字节/包数，不记录地址、名字、房间码、凭证或载荷。

## 队友鼠标

鼠标包含世界 X/Z、是否可见、是否按下、玩家独立序号和 presence epoch。Relay 使用房间内真实团队关系选择接收者，敌方 Host 也收不到敌队鼠标。收端再次校验队伍、对局、房间版本和发送者参与权限。过时序号/旧 epoch/旧房间版本都丢弃；投降和结算后的发送者不能继续发布。显示和隐藏可靠发送，普通移动可丢失。HUD、失焦、过期淡出和本地投影由 authored `TeammateCursors` 场景处理。

## 部署与回退

仅 `C:/Users/wh/Documents/.env` 中用户指定的 Tokyo 配置可用于本工具；若该文件只有一个无命名的 `ip/password` 块，则按用户明确指定视为 Tokyo，默认 SSH 用户 `root`。不会读取其他项目的 Shanghai 凭据。SSH 首次成功连接后把主机密钥固定在忽略目录，后续身份变化拒绝连接。

```powershell
python tools/deploy_block_war_relay.py --certificate
python tools/deploy_block_war_relay.py --configure-client
python tools/deploy_block_war_relay.py --probe
python tools/deploy_block_war_relay.py --build-relay
python tools/deploy_block_war_relay.py --deploy
```

`--build-relay` 生成只含服务器脚本及内容清单的 PCK，搭配未修改的官方 4.7.2 release 模板，输出在 `.local/network/relay-package/`。开发入口使用编辑器，正式服务使用 release 模板及同名 PCK，不以编辑器进程冒充发行服务器。

部署只涉及 `/opt/block-conquest-relay` 和 `block-conquest-relay.service`，运行专用用户 `blockconquest`，`MemoryHigh=128M` / `MemoryMax=192M`。上传内容先核验摘要，版本目录不可变，切换前保留旧配置及版本；新服务不健康即停止并恢复旧版本。修改前后比对其他 Relay 的 PID/InvocationID，不停用或覆盖 Block RTS/Bot Jump 服务。若 42300 已被非本服务占用则拒绝部署。云安全组和 SSH 可用性独立于代码；仅看到 READY 不等于公网客户端已验证。

## 验证入口

- `tests/block_war_relay_test.gd`：纯房间/协议状态机，包括身份防伪、任意席位、开始屏障、跨通道权限、敌端无鼠标包、断线超时、旧连接事件、丢失重连凭证回复、精确恢复 epoch、投降观战全生命周期、同时退出结算清理、旧房间身份与新房间连接隔离，以及 Host 在各阶段掉线的组合边界。
- `tests/block_war_native_network_test.gd`：真实 DTLS 和多个独立 ENet 连接，完整房间→加载→所有通道→光标→自动重连→投降观战→主动退出确认→回房间→再次开局与加载中 Host 恢复→关闭。测试证书自动生成在 `.local/network-tests/`。
- `tests/block_war_network_load_test.gd`：六真人混合角色、另一个独立房间、两名队友鼠标、相当于 8192 名单位的 2 Hz 校正流，同时发送可靠事件和快照块；验证保护上限不会误踢合法流量。它不运行 8192 兵战斗仿真。
- `tests/block_war_network_security_test.gd`：错误证书身份、相同 CN 的错误信任根、错误内容指纹均拒绝；测试会产生预期的原生 TLS 拒绝日志。
- `tools/run_block_war_network_tests.py --build`：发行模板 Relay 和独立进程内的多个原生客户端。可加 `--loss 0.05 --latency 150 --jitter 35 --duplicate 0.02`，在真实加密 UDP 数据报上制造丢包、延迟、乱序与重复；每次重连的源端口有独立上游映射，旧 DTLS 返回数据仍发往旧连接。使用 finally 清理本地服务、客户端及代理线程，不访问 Tokyo。`tests/network_udp_proxy_test.py` 用真实本地套接字单独验证映射与延迟返回路径。

上述测试验证传输与房间，不代替游戏复制、六人大战仿真帧率、不同镜头视觉或两台外网设备测试。
