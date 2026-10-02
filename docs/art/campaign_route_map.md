# 单人战役：积木地貌大地图（2026-10-02）

主菜单「单人战役」进入真实渲染的 3D 积木微缩景观。采用正交俯视，保留 2D 地图清晰、安静的浏览方式。西侧森林村落经过溪谷木桥、群峰隘口，抵达东侧雪原与雪冠要塞，六处关卡保持原有顺序。

当前完成大地图建模与选关预览，六个战斗关卡仍待制作。界面明确显示「路线已展开 · 关卡制作中」，浏览选择不会记录通关或修改玩家偏好。

![实际渲染](campaign/route-map.png)

## 模型与风格

以用户提供的积木场景为造型参考，重做几何、结构和材质：连接成簇的方块树冠、分层针叶与积雪、草皮和岩层厚度、连续弯曲的石径与台阶、木桥的桥板与桩柱、房屋的木梁窗框与屋瓦、要塞的院落、城门、塔楼和垛口。使用原创建筑与布景，未复制参考图中的列车、角色或界面。

75 棵树编排成 11 处疏密不同的树群。根部净空检查采用更细的地形，避免树根跨越台地。阔叶树冠由 0.22 单位小块组成，松树使用 0.18 单位小块，合并相连树冠后只保留外壳，顶面增加轻微起伏；雪片直接落在针叶顶面。窗格、百叶窗、屋瓦、城堡石砖和木桥铆钉进一步细分。地形与地表细节合计 31,099 块，使用 0.25 单位网格，大块平地合并为 0.5 单位地块，山脊和道路保留小块。

道路先调整沿线的真实地形，再嵌入 3,193 块小路砖。路砖宽 0.123 单位、间距 0.125，底部嵌入地面，路面仅高出地表 0.008；外圈路肩更低，弯道宽度略有变化。坡段采用连续小台阶，桥头高度与桥面匹配。移除旧的抬高路基及屏幕空间路线叠层，选关光点仍沿实际地表路线行进。

![森林村落细节](campaign/woodland.png)
![溪谷木桥细节](campaign/bridge.png)
![雪冠要塞细节](campaign/summit.png)

定向光、柔和阴影、SSAO 和少量 SSIL 表现接触与层次。草地保持大面积干净色面，低幅空间色差只用于区分缓慢变化的区域。水面采用世界坐标波纹、天空反射与屏幕空间反射；河口有连续落水面。旗帜、树冠与流水保持轻微动态，雪域保留稀疏飘雪。

## 原生场景结构

- `scenes/campaign/campaign_map.tscn`：UI、六个独立标记和输入。
- `scenes/campaign/campaign_diorama.tscn`：SubViewportContainer → SubViewport → 独立 World3D、环境光、正交相机与地貌场景；CameraMotion 是镜头的原生 AnimationPlayer。
- `scenes/campaign/campaign_landscape.tscn`：Terrain、Landmarks、Groves、StageAnchors、原生 Path3D 和 Entrance AnimationPlayer。编辑器中可单独调整地标、树木实例与动画轨道。
- `scenes/campaign/models/`：阔叶树、松树、雪松、村屋、雪屋、瞭望塔、木桥、要塞与旗帜的可复用 PackedScene。
- `assets/campaign/`：地形展开、树冠、旗帜、河水与瀑布着色器。
- `data/campaign/journey_3d.tres`：真实地形上的 Curve3D。六个 Marker3D 位于这条路线的准确节点，Camera3D.unproject_position 投影到 UI，替代插画时代的手写屏幕坐标。
- `data/campaign/01_woodland.tres` 至 `06_summit.tres`：关卡名称、地区、说明文字。

所有节点和 MultiMesh 均已保存在场景里。游戏运行时只加载与渲染，不生成地形、树木或建筑节点。MultiMesh 将同一模型的重复积木合批，避免每块屋瓦和树叶都成为运行时节点。

`tools/build_campaign_diorama.py` 是离线建模入口，只依赖 Python 标准库。`tools/campaign_ground.py` 负责地形修整与道路采样，`tools/campaign_intro_authoring.py` 保存可编辑的原生动画轨道。运行入口可确定性重建模型、地形场景、动画与三维路线。修改生成内容前，应同步修改对应源文件；手工场景调整也可直接在 Godot 内完成，但重建时会覆盖生成文件。生成器不修改相机、UI 或关卡文案。

建模时查阅 Godot 官方 [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)、[SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html)、[Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)、[Curve3D](https://docs.godotengine.org/en/stable/classes/class_curve3d.html)、[Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html) 的批量渲染、投影与环境表现能力。

## 立体开场

开场主时间轴为 2.55 秒，从近俯视的平面开始，地形按西向东的次序舒展至完整高度，镜头转向最终斜俯视。地形各层和细路砖共用所属地块的展开进度，避免铺路在展开时出现穿插条纹。水面、岸线、瀑布和地表细节使用相同展开函数。

地形展开后，树木从压平状态伸展；村屋、瞭望塔、桥梁、山门和城堡从高处依次落下，接触地面时轻微压缩，短促回弹后停稳。关卡标记等镜头稳定后重新投影，再连同说明面板显现。动画保存在原生 Animation 资源中，地形由每个场景独立的 ShaderMaterial 时钟驱动，重复进入时重新从平面开始。

进入动画等待共享转场幕布打开；设置窗口暂停并恢复模型和镜头时间轴。空格可跳过，数字行或数字小键盘 1–6 可直接跳至对应关卡；Esc 可在展开过程中返回。播放与跳过都恢复到相同的场景原始位置、缩放和最终镜头。

动画依据官方 [Animation](https://docs.godotengine.org/en/stable/classes/class_animation.html)、[AnimationPlayer](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html)、[ShaderMaterial](https://docs.godotengine.org/en/stable/classes/class_shadermaterial.html) 的三维变换轨道、暂停、即时 seek 和场景独立资源行为实现。

## 操作与验证

鼠标、方向键、数字行和数字小键盘 1–6 选择关卡；光点沿三维路线的屏幕投影在 0.38 秒内抵达目标。Esc 返回，保留本次运行的选择。设置弹窗打开时冻结地图渲染和环境粒子。1600 × 900 设计画面在其他比例下等比完整显示。

Godot 4.7.2 / Forward+，隔离 Windows 桌面实机检查，不操作用户窗口。

- `tests/campaign_map_test.gd`：221 项通过，覆盖开场完成后的选关、快速打断、投影与三维路线一致性、连续小台阶、设置隔离、返回记忆、1600 × 900 / 1280 × 720 截图、超宽和 4:3 适配。
- `tests/campaign_construction_test.gd`：311 项通过。从实际保存的 MultiMesh 读回地形与每块路砖四角，检查底部接地、顶面外露与两侧桥头；3,193 块路砖无悬空，实测最大路面高差约 0.008。另覆盖初始平面、建筑下降、设置暂停、自然结束、跳过、再次进入和中途退出。必须使用真实渲染器，headless 的 Dummy RenderingServer 不提供有效的实例变换读回。
- `tests/campaign_model_visual.gd`：全图、森林、木桥、要塞实拍；传入 `--motion` 保存 90 帧开场和 168 帧六关切换。检查开场关键帧、建筑落地、局部模型及道路。
- `tools/validate_product.py`：312 个运行时文件，资源引用与产品边界检查无错误。

可复现视觉检查：

```powershell
python tools/run_godot_private_desktop.py res://tests/campaign_model_visual.gd --output artifacts/campaign_unfold_final --script-arg=--motion --godot .local/network/runtime/Godot_v4.7.2-stable_win64.exe --timeout 110
```

本轮开场实录保存在 `artifacts/campaign_unfold_final/campaign-opening.mp4`，由引擎输出的原始帧按 24 fps 编码。验证录像与逐帧文件不纳入版本库，文档截图来自同轮渲染。

## 插画参考的定位

之前由内置 image_gen 生成的 `assets/ui/campaign/forest_to_summit.png` 保留为构图参考。它帮助确定森林、溪谷、雪山的连续布局，当前运行场景不再引用它。最终画面来自上述真实三维场景的渲染。
