# 1.3.3：正式导出中文断行修复

## 已确认的根因

项目没有启用 `internationalization/locale/include_text_server_data`。编辑器内置 ICU 断词词典与 Unicode 断行规则，正式模板需要从 PCK 加载 `icudt_godot.dat`；缺失时，按词换行的中文 Label 会退化，长段无空格中文越过容器。

用同一旧 PCK、相同 1600×900 窗口及相同 4.7.2 引擎分别运行编辑器和正式模板：

| 占领与胜负的 GuideTip | 可用宽度 | 行数 | 最宽一行 |
| --- | ---: | ---: | ---: |
| 编辑器运行旧 PCK | 206 px | 3 | 190 px |
| 正式模板运行旧 PCK | 206 px | 1 | 570 px |
| 正式模板运行修复后 PCK | 206 px | 3 | 190 px |

因此不是窗口分辨率、字体大小或容器宽度造成的差异。`FEATURE_BREAK_ITERATORS` 在缺失词典的正式模板中也返回 true，不能仅以功能位判断断行可用。

## 修复与防止漏检

- 全项目启用 Godot 原生文本支持数据导出，保留原有自动换行模式、文案及布局。
- 模板准备工具从经过官方 SHA256/SHA512 校验的 4.7.2 模板包中额外提取 `icudt_godot.dat`，记录文件摘要。Godot 从自定义模板的相邻目录读取它，使手动导出与构建脚本都使用模板匹配的数据；不会给编辑器本身替换词典。
- 客户端、Windows 文件/产品版本、发行说明、联机协议版本、兼容清单和 Relay 版本统一为 1.3.3。
- 原有构建烟雾测试由编辑器执行 PCK，会掩盖词典缺失。新增实际发行 EXE 的文本检查，覆盖 12 条战场指南、6 位英雄的 24 项技能，以及 1280×720、1600×900、2560×1440 三种窗口。
- 使用原生 TextParagraph 实际整形后的行宽检测水平越界，并检测 Label 行数/垂直裁切。仅检查控件最小尺寸无法发现此次问题。
- 官方发行模板关闭外部 `--path`、`--main-pack` 和脚本覆盖入口。因此用 PCKPacker 原样复制正式资源，只在隔离测试副本中增加测试 autoload 和启动配置；发行包不含测试入口。检查明确要求 `editor=false`、`debug=false`。
- GPU 截图通过不激活的 Windows 私有桌面获取，使用 Dummy 音频，不发送桌面输入；测试副本也使用独立用户数据目录。

模板数据大小为 4,797,472 字节，SHA256：`64e407b570a21a4b740531a14cd95f0cefc46cef3d8224fd09a0dd386fb7016a`。4.6.3 编辑器内置数据与 4.7.2 数据摘要不同；已实际验证当前编辑器手动导出的包也可通过 942 项检查，并补齐模板侧数据以避免依赖跨版本兼容。

## 验证与发布

| 检查 | 结果 |
| --- | --- |
| 旧包执行新增文本回归 | 942 项中 143 项失败，正确拦截原问题 |
| 1.3.3 发行 EXE 无头文本检查 | 942 项通过 |
| 1.3.3 发行 EXE GPU 文本检查及 6 张截图 | 948 项通过 |
| 正式 PCK 启动、全部地图与返回主菜单 | 104 项通过 |
| 本地发行 Relay 原生 DTLS | 64 项通过 |
| Tokyo 公网原生 DTLS | 64 项通过 |

Windows 交付目录：`builds/windows-1.3.3`；发行压缩包：`builds/积木战争-1.3.3-Windows-x64.zip`。

东京 `block-conquest-relay.service` 于 2026-09-30 21:53（日本时间）切换至发行目录 `670597e4ca68f3c7`，客户端/中继内容指纹为 `94ab29da3bffbb54e650ac96ac83ee3692e084efa7d39f511d350cbafd8c7a09`。切换前及上传后均核实空闲，保留证书与 8 房间容量。公网检查后核实服务正常、未自重启、0 房间/0 连接、部署文件摘要一致，其他 Relay 的 PID/InvocationID 未变。

断线重连专项期间服务记录 3 条原生 `TLS handshake error: -30464`；客户端检查全部通过，无脚本错误，服务未自重启。未将这些已观察到的诊断计为“无错误”。

本机证据保存于忽略目录 `.local/cjk-wrap/`、`.local/release-text-check/` 和 `.local/relay-release-1.3.3/`。

## 官方依据

- [ProjectSettings：include_text_server_data](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-internationalization-locale-include-text-server-data)
- [TextServer：可选数据与原生断行](https://docs.godotengine.org/en/stable/classes/class_textserver.html)
- [Godot 导出器的数据选择逻辑](https://github.com/godotengine/godot/blob/4.6/editor/export/editor_export_platform.cpp)
