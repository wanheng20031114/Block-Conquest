# 400 人沙盒 GPU 压力核对

2026-09-15，接续[移动性能调查](movement-investigation-2026-09-15.md)。本轮核对用户可视分析器截图，并在同一冻结游戏构建上检查分辨率敏感度及 GPU 硬件遥测。

## 1. 对截图判断的补正

**是，截图已经显示部分 GPU 历史帧超过了 60 FPS 的帧时间预算。** 先前只引用左表 6.42 ms 来评估 GPU 压力并不充分；这个数字属于当前选中帧，最高尖峰在另一个时刻。

| 图中元素 | 实际含义 |
|---|---|
| 图表左半区，CPU 标题下 | CPU 渲染工作，不包含普通分析器里的全部脚本和物理时间 |
| 图表右半区，RTX 3080 标题下 | GPU 渲染时间历史；高峰明显越过 16.67 ms |
| “联合”勾选 | 英文是 Linked，只统一两侧纵轴刻度，不相加 CPU 和 GPU 时间 |
| 16.67 ms 横线 | 60 FPS 的每帧时间预算，不是利用率、功耗或显存上限 |
| 两条白色竖线 | 同一选中帧分别在 CPU／GPU 两个半区的位置 |
| 左表 Render Viewports GPU 6.42 ms | 所选帧 70521 的值，不是历史最大值 |

Godot 4.6.3 源码明确把 CPU 绘制在左半区、GPU 绘制在右半区；Linked 只让两个纵轴使用共同最大值。图中的历史 GPU 尖峰因此是真正的 GPU 计时超预算证据，不能解释成父子分类重复累加或 CPU/GPU 叠加。[图表绘制源码](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/debugger/editor_visual_profiler.cpp#L195-L291)

左表 `Render Viewports → Render Viewport 0 → Render 3D Scene` 是嵌套汇总，不能把它们相加。GPU 6.42 ms 中已包含 Opaque 3.81 ms 等子阶段。普通 CPU 游戏逻辑则须在普通分析器中查看。[层级汇总源码](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/debugger/editor_visual_profiler.cpp#L327-L385)、[官方可视分析器说明](https://docs.godotengine.org/en/4.6/tutorials/scripting/debug/debugger_panel.html#visual-profiler)

**能够确认的是 GPU 的部分帧超预算；仍不能从截图确认显卡持续满载、显存不足，或所有慢帧都由 GPU 单独决定。** 要定位截图中最高峰的具体阶段，应选中右半区最高峰，再读左表 GPU 列；当前 3.81 ms Opaque 不能作为那个峰的直接分项。

## 2. 本轮测量方法

沿用先前冻结的 400 人真实沙盒：每侧盾卫 80、火枪手 80、剑士 20、长枪兵 20；生命乘 100，保留真实交战、移动、避让和物理；30 Hz 模拟。开局 8 秒、持续 20 秒、近景 12 秒。地图／摆阵是复现实验假设，并非用户原场景的逐帧回放。

同一个 Release EXE 和 PCK，固定 1600×900 输出窗口和相机，按 **1.0 → 0.5 → 0.5 → 1.0** 顺序运行，再测一次 1.6。仅改变 3D 渲染比例：

| 比例 | 3D 内部分辨率 | 相对像素数 |
|---|---|---:|
| 1.0 | 1600×900 | 100% |
| 0.5 | 800×450 | 25% |
| 1.6 | 2560×1440 | 256% |

保留 Forward+、4× MSAA、TAA、阴影及环境效果，关闭帧率限制／垂直同步。缩放用 Viewport 原生 `scaling_3d_scale`，相机视野不变；输出 UI 分辨率也不变。缩放可能影响自动 LOD，故它是渲染分辨率敏感度实验，不能严格等同于只改变 fragment 指令数量。[原生分辨率缩放](https://docs.godotengine.org/en/4.6/tutorials/3d/resolution_scaling.html)

每显示帧记录墙钟间隔、实际物理步数、最近取得的 Viewport GPU／CPU 渲染时间。GPU 读数来自异步时间戳，不能假定与同一数组行的墙钟帧严格对应，也不能用 GPU 时间除以帧间隔冒充硬件利用率。[RenderingServer 计时接口](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)

另用 `nvidia-smi` 每 500 ms 采样利用率、显存、功耗、温度、时钟及限频原因，按系统时间对齐阶段。这是**整张 RTX 3080** 的观测，包含正常编辑器和桌面等工作；利用率是驱动采样窗口的统计，不能捕获或排除所有毫秒级饱和。编辑器保留，所有实验串行。[NVIDIA 遥测定义](https://docs.nvidia.com/deploy/nvidia-smi/index.html)

## 3. 实测结果

### 持续交战阶段

以下按实际运行顺序排列。GPU 平均／P95 是本轮读取到的异步 Viewport 时间；FPS 和显示帧 P95 来自墙钟。GPU 利用率另取 NVIDIA 的全卡采样中位数。

| 运行 | GPU 平均 ms | GPU P95 ms | FPS | 显示帧 P95 ms | 全卡 GPU 利用率中位数 |
|---|---:|---:|---:|---:|---:|
| 1600×900，第一次 | 2.660 | 2.866 | 79.57 | 21.548 | 34% |
| 800×450，第一次 | 1.455 | 1.632 | 95.79 | 16.445 | 47% |
| 800×450，第二次 | 1.472 | 1.630 | 84.34 | 18.348 | 46% |
| 1600×900，第二次 | 2.561 | 2.811 | 92.94 | 17.143 | 60% |
| 2560×1440 | 4.283 | 4.640 | 88.02 | 17.473 | 73% |

降低分辨率后 GPU 常态耗时明确下降，但两次 FPS 范围重叠，第二次 1600×900 还高于第二次 800×450。高分辨率的 GPU 时间升高，却没有按同样比例拖慢总帧率。**这支持存在可减少的 GPU 渲染工作，但没有支持“本复现负载的持续帧率只由 GPU 限制”。** CPU／同步及背景变化仍需考虑，不能把首对 FPS 差值单独当成 GPU 优化收益。

本轮各阶段均有真实伤害，人口采样保持 400。持续阶段伤害次数按表序为 1,686／1,565／1,530／1,459／1,656；模拟并非锁步，移动／交战轨迹仍有差别。整卡 GPU 利用率在运行间也有漂移，无法分离游戏与背景负载贡献，因此不将本轮 FPS 与前一轮约 103 FPS 做净性能差值比较。

### 尖峰确实出现，尚未定位到具体渲染阶段

第一次 1600×900 的持续阶段记录了三个超过 16.67 ms 的 GPU **读取样本**：20.270、63.663、34.476 ms。该阶段 GPU P95 仅 2.866 ms，属于长尾；63.663 ms 读数附近也有 88.754 ms 显示帧。异步读取缺少唯一 GPU 帧编号，不能把三个样本直接当成三个独立完成帧，也不能从同一数组行认定精确因果。

其余四场的所有三个正式阶段没有读到超过 16.67 ms 的 GPU 样本；2560×1440 近景的 GPU P95 为 5.213 ms、最大 5.464 ms。因此没有稳定复现原截图的 GPU 峰形，当前不能确认尖峰来自 Opaque、阴影、资源上传、调度竞争还是其它因素。下一步要捕获峰值帧的分项，而非用常态平均数替代。

### 硬件遥测：功率限制、显存与温度

- 本轮整卡显存最高 **5,616 / 10,240 MiB，约 54.8%**。没有看到显存容量耗尽。
- 正式阶段最高温度 **68℃**；硬件及软件热限制标记均未激活。
- 2560×1440 的软件功率限制标记在开局 **3/16**、持续 **20/39**、近景 **21/24** 个遥测样本中为 Active；其它四场正式阶段为 0。
- 高分辨率持续阶段全卡利用率范围 **67–81%**，中位数 73%；近景中位数 76.5%。它不等于整段 100%，但已出现真实的功率限制信号。

所以“没有持续饱和证据”不等于“硬件完全没有压力”。高分辨率实验期间整卡出现了功率限制标记，减少 GPU 工作值得评估；但单次高分辨率运行不能独立证明是分辨率变化导致了全部限频。驱动报告功率上限 370 W，而功耗读数具有自己的采样／平均口径；不能因为某一行功耗小于 370 W 就否认同一轮的功率限制标记。整卡采样也不能独立归因到游戏进程。[NVIDIA 功率与时钟事件说明](https://docs.nvidia.com/deploy/nvidia-smi/index.html)

## 4. 具体 GPU 优化候选

下面是源码确认的候选，尚未进行这些画质开关的 A/B，不能将它们写成已确定的尖峰根因。

### 4.1 先单独检查 PCSS 软阴影

`scenes/sandbox.tscn` 中 Sun 的 `light_angular_distance=1.6`，启用了 PCSS 软阴影。其采样成本会计入物体着色，所以截图 `Render Shadows=0.16 ms` 只说明阴影图生成在选中帧较轻，不能排除 Opaque 内的阴影采样成本。官方文档明确指出这个参数大于零会产生额外性能成本。[Light3D 文档](https://docs.godotengine.org/en/4.6/classes/class_light3d.html#class-light3d-property-light-angular-distance)

最小实验是仅把冻结场景的 `Sun.light_angular_distance` 改为 `0.0`，保留阴影开关及其余画质，比较总 GPU、Opaque、Depth 和帧时间分位数。只有效果明确后，再决定是否降低软阴影质量；不能把全部关闭阴影的收益都归给 PCSS。[沙盒灯光配置](../scenes/sandbox.tscn)

### 4.2 分离活兵与尸体淡出材质

活兵与尸体共用 [unit_batch_surface.gdshader](../assets/models/units/batched/unit_batch_surface.gdshader)。活兵透明度为 1，运行时不会丢弃像素，但 shader 中仍有屏幕网点淡出的 `discard`，编译材质会带 `uses_discard` 标记。Godot Forward+ 的共享阴影材质要求没有这个标记，当前材质因此失去该共享材质／简化 shadow mesh 路径。[共享阴影材质条件](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.h#L271)、[shadow mesh 使用处](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp#L3716)

先在维持 400 活兵的实验副本中仅去掉 coverage／discard，测 GPU 总量及阶段成本。若收益稳定，再设计正常不透明活兵批次和尸体淡出批次，并在死亡时迁移。正式实现需检查尸体、阴影、TAA 和槽位迁移，不能直接删除死亡视觉。**这不等于当前完全没有深度预通道。**

### 4.3 分别检查抗锯齿，保留现有批处理

目前同时使用 4× MSAA 和 TAA；可分别测试只保留 TAA、只保留 MSAA，观察 GPU 帧时间和边缘效果。MSAA 并不意味着 fragment shader 固定执行四次，不能用“关掉就快四倍”估计收益。[Godot 抗锯齿说明](https://docs.godotengine.org/en/4.6/tutorials/3d/3d_antialiasing.html)

单位已经采用每兵种／部件 MultiMesh，并在 CPU 提交时筛除不活跃模型。动画推进、全局变换读取和提交 API 是 CPU 热点；只有减少实际几何、像素、shader 或上传工作，才有直接的 GPU 工作量变化。当前大 custom AABB 也不代表全部离屏单位必然被绘制。[当前批量提交](../scripts/unit_render_batches.gd)

SSAO、SSIL、烟雾透明等在所选帧中的值较小，但它们在峰值帧中的成本尚未读到。项目的 MultiMesh primitives 统计还存在已知的实例计数解释限制，本轮保留计数用于观察，不用它证明实际三角形数量或几何收益。

## 5. 复现与交付

```powershell
python tools/build_movement_investigation.py --output .local/gpu-next/build --base .local/movement-investigation-20260915/baseline-v2 --variant baseline --refresh-harness
python tools/run_gpu_investigation.py --build .local/gpu-next/build --output .local/gpu-next/runs --label full-1 --scale 1.0
python tools/run_gpu_investigation.py --build .local/gpu-next/build --output .local/gpu-next/runs --label half-1 --scale 0.5
python tools/run_gpu_investigation.py --build .local/gpu-next/build --output .local/gpu-next/runs --label half-2 --scale 0.5
python tools/run_gpu_investigation.py --build .local/gpu-next/build --output .local/gpu-next/runs --label full-2 --scale 1.0
python tools/run_gpu_investigation.py --build .local/gpu-next/build --output .local/gpu-next/runs --label high-1 --scale 1.6
python tools/summarize_gpu_investigation.py --runs .local/gpu-next/runs --build .local/gpu-next/build --output .local/gpu-next/summary.json
```

已有本地冻结目录才能直接使用上述 `--base`；另一台机器可省略 `--base`，从当时工作区创建新的明确基线。旧游戏输入包含未提交改动，Git HEAD 单独不能重建旧负载。工具会记录构建与运行身份，拒绝覆盖已有 run-id，并在运行结束或失败时停止自己的游戏和遥测进程。

本轮只增加调查工具及证据，未实施上述材质或画质候选。完整数值与来源文件哈希见 [GPU 证据数据](gpu-investigation-2026-09-15.json)。
