# 建筑点击动画候选

2026-09-23。六版使用游戏当前二级住宅、材质与光照，由原生 Godot Tween 驱动 Curve 资源后直接录制。每个 GIF 为正常速度的 3 秒循环：第 0.6 秒同时点击，动作收稳后停留，再清除选择。候选尚未接入正式游戏，待用户选择编号。

![六版同步对比](art/selection_motion/overview.gif)

| 编号 | 单独 GIF | 动作 | 收稳时间 |
| --- | --- | --- | --- |
| 01 | [重心回弹](art/selection_motion/01.gif) | 脚底压实，向上回弹，两次减幅后收住；上下伸缩时横向补偿体积 | 0.54 秒 |
| 02 | [轻跃落定](art/selection_motion/02.gif) | 轻微蓄力，抬起 0.25 米，落地压缩后回稳 | 0.62 秒 |
| 03 | [左右摇摆](art/selection_motion/03.gif) | 从脚底边缘左右摆动，逐次减幅回到中线 | 0.66 秒 |
| 04 | [旋拧回正](art/selection_motion/04.gif) | 绕竖轴轻拧、反向回旋，伴随少量纵向弹性 | 0.62 秒 |
| 05 | [上层跟随](art/selection_motion/05.gif) | 主体先弹，屋顶滞后跟随，分层收稳 | 0.68 秒 |
| 06 | [前倾点头](art/selection_motion/06.gif) | 朝相机轻倾，反向缓冲后迅速站稳 | 0.52 秒 |

推荐 01：脚底稳定，压实和回弹容易辨认，适合反复选择。02 更活泼，03/04 有更明显的方向感，05 强调屋顶惯性，06 最短促。

## 实现边界

`tests/block_war_selection/review.tscn` 预先摆放六座建筑，曲线保存在 `presets/01.tres` 至 `06.tres`。预览只改变 `Building/Visual` 和 05 的屋顶局部位置，人口牌、点击碰撞区域和建筑世界位置保持固定。侧倾与前倾按接地边缘补偿高度，回弹保持近似体积，结束后回到作者原始变换。旗帜等环境待机动画在此预览中暂停，便于比较点击本身。

曲线通过 `Tween.tween_method()` 采样，用 `Tween.custom_step()` 固定步进，六版同步且可重现。正式整合时需要按选定版本处理连点重触发，以及占领、施工完成和炮塔后坐的动画衔接。本阶段没有替换 `WarBuilding.set_selected()` 的现有行为。

原生能力参考：[Tween](https://docs.godotengine.org/en/stable/classes/class_tween.html)、[Curve](https://docs.godotengine.org/en/stable/classes/class_curve.html)、[Node3D](https://docs.godotengine.org/en/stable/classes/class_node3d.html)。

## 复现与验证

在仓库根目录执行（Godot 4.6、FFmpeg）：

```powershell
Godot --path . --script res://tests/block_war_selection/render.gd --fixed-fps 30 --audio-driver Dummy
./tests/block_war_selection/encode_gifs.ps1
```

原生 PNG 帧输出至忽略的 `artifacts/block_war_selection/`；总览及六个单独 GIF 输出至本页的 `art/selection_motion/`。渲染入口附加 `--headless` 可仅执行动作检查，不输出图片。

本轮 36 项检查通过，覆盖六版动作幅度、完成时限、建筑及上层原位恢复、人口牌和点击区域稳定。人工检查动作关键帧与导出后的 GIF 画面，文字与模型不重叠。FFprobe 确认七个 GIF 都是 90 帧、3 秒；总览 1200×1000，单版 480×500。
