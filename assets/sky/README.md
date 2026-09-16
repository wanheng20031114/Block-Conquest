# 沙盒晴天天空

2026-09-16：为英雄第一人称补充蓝天、低多边形白云与浅蓝地平线。

## 资源

- `clear_day.tres`：原生 `Sky` 资源，直接由 `scenes/sandbox.tscn` 的 `WorldEnvironment` 引用。
- `clear_day.png`：1774 × 887 的 2:1 全景纹理；生图工具原创，并通过一次编辑清除接缝边缘的云块。没有改变图片长宽比。
- `clear_day.gdshader`：显示全景；辐照贴图生成阶段读取原有光照。纵向 UV 钳制与显式纹理采样层级避免仰视天顶时出现亮点。
- `sandbox_lighting_source.tres`：保存修改前沙盒的原生程序天空颜色。
- `sandbox_lighting.exr`：由 Godot 原生 `RenderingServer.sky_bake_panorama` 离线烘焙的 512 × 256 线性 HDR 光照。不是可见天空美术。

可见天空与照明分开，避免蓝色背景把原有金属、衣服、地面整体染冷。沙盒环境的 `fog_sky_affect = 0`，保留地面原有雾效并让天空保持清晰。RTS 和第一人称共用同一套环境，不在 F5 时切换或重新烘焙天空。

天空是静态资源，原生 `Sky.PROCESS_MODE_QUALITY` 在需要时构建光照缓存；没有 `TIME`、随相机位置变化的参数、体积云步进、粒子或新增逐帧脚本。背景每个可见像素采样一次全景纹理。

## 编辑与重建

改变天空外观：编辑 `clear_day.png`，保留 2:1 经纬投影和水平连续性。不要在左右边缘留下截断云块；上下极点附近应保持干净的同色天空。

只有有意修改沙盒原有光照或太阳方向时，才需编辑 `sandbox_lighting_source.tres` 并重新烘焙：

```powershell
& 'C:/Program Files/Godot/Godot_console.exe' --path . --script tools/bake_sandbox_sky_lighting.gd --audio-driver Dummy
```

烘焙依赖图形渲染器，不能加 `--headless`。普通游戏启动直接加载已保存的 EXR，不执行此工具。

## 验证

- `tests/hero_sky_visual_review.gd`：真实 Vulkan 渲染，检查平视、四向转头、78° 仰视、70° / 110° FOV、透明背包及返回 RTS。
- 对照原天空的固定 RTS 画面，地面采样区域 RGB 平均绝对差约 0.04 / 255，原有照明基本保持。
- `tests/hero_sandbox_test.gd`：64 项通过，0 失败。
- 图形运行日志无脚本或着色器错误。截图仅放在被忽略的 `.local/hero/sky/`，交付保留两张必要展示图。

美术来源：本任务生图结果 `exec-e73224ee-8d20-4bd3-b8e0-0d32dada294b.png`，接缝修订 `exec-0ec77108-731a-4254-8b4d-ae42a00f0896.png`。生成原稿留在本机工具输出目录，运行资源仅保存最终版本。

原生能力依据：[Sky shaders](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/sky_shader.html)、[Sky](https://docs.godotengine.org/en/4.6/classes/class_sky.html)、[Environment](https://docs.godotengine.org/en/4.6/classes/class_environment.html)。
