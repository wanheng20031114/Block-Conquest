# 单人战役：积木地貌大地图（2026-10-02）

主菜单「单人战役」进入真实渲染的 3D 积木微缩景观。采用正交俯视，保留 2D 地图清晰、安静的浏览方式。西侧森林村落经过溪谷木桥、群峰隘口，抵达东侧雪原与雪冠要塞，六处关卡保持原有顺序。

当前完成大地图建模与选关预览，六个战斗关卡仍待制作。界面明确显示「路线已展开 · 关卡制作中」，浏览选择不会记录通关或修改玩家偏好。

![实际渲染](campaign/route-map.png)

## 模型与风格

以用户提供的积木场景为造型参考，重做几何、结构和材质：连接成簇的方块树冠、分层针叶与积雪、草皮和岩层厚度、连续弯曲的石径与台阶、木桥的桥板与桩柱、房屋的木梁窗框与屋瓦、要塞的院落、城门、塔楼和垛口。使用原创建筑与布景，未复制参考图中的列车、角色或界面。

90 棵树编排成 11 处疏密不同的树群。模型摆放检查树根跨台地、道路、建筑和岩石的净空。地形、植被、房屋和桥梁都是可独立查看的三维几何；没有用图片平面冒充建模。

![森林村落细节](campaign/woodland.png)
![溪谷木桥细节](campaign/bridge.png)
![雪冠要塞细节](campaign/summit.png)

定向光、柔和阴影、SSAO 和少量 SSIL 表现接触与层次。草地保持大面积干净色面，低幅空间色差只用于区分缓慢变化的区域。水面采用世界坐标波纹、天空反射与屏幕空间反射；河口有连续落水面。旗帜、树冠与流水保持轻微动态，雪域保留稀疏飘雪。

## 原生场景结构

- `scenes/campaign/campaign_map.tscn`：UI、六个独立标记和输入。
- `scenes/campaign/campaign_diorama.tscn`：SubViewportContainer → SubViewport → 独立 World3D、环境光、正交相机与地貌场景。
- `scenes/campaign/campaign_landscape.tscn`：Terrain、Landmarks、Groves、StageAnchors 和原生 Path3D。编辑器中可单独调整地标与树木实例。
- `scenes/campaign/models/`：阔叶树、松树、雪松、村屋、雪屋、瞭望塔、木桥、要塞与旗帜的可复用 PackedScene。
- `assets/campaign/`：树冠、旗帜、河水与瀑布着色器。
- `data/campaign/journey_3d.tres`：真实地形上的 Curve3D。六个 Marker3D 位于这条路线的准确节点，Camera3D.unproject_position 投影到 UI，替代插画时代的手写屏幕坐标。
- `data/campaign/01_woodland.tres` 至 `06_summit.tres`：关卡名称、地区、说明文字。

所有节点和 MultiMesh 均已保存在场景里。游戏运行时只加载与渲染，不生成地形、树木或建筑节点。MultiMesh 将同一模型的重复积木合批，避免每块屋瓦和树叶都成为运行时节点。

`tools/build_campaign_diorama.py` 是离线建模源文件，只依赖 Python 标准库。运行它可确定性重建模型、地形场景与三维路线。修改生成内容前，应同步修改该文件以保留可再现的建模源；手工场景调整也可直接在 Godot 内完成，但重建时会覆盖生成文件。它不修改相机、UI 或关卡文案。

建模时查阅 Godot 官方 [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)、[SubViewport](https://docs.godotengine.org/en/stable/classes/class_subviewport.html)、[Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)、[Curve3D](https://docs.godotengine.org/en/stable/classes/class_curve3d.html)、[Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html) 的批量渲染、投影与环境表现能力。

## 操作与验证

鼠标、方向键、数字行和数字小键盘 1–6 选择关卡；光点沿三维路线的屏幕投影在 0.38 秒内抵达目标。Esc 返回，保留本次运行的选择。设置弹窗打开时冻结地图渲染和环境粒子。1600 × 900 设计画面在其他比例下等比完整显示。

Godot 4.7.2 / Forward+，隔离 Windows 桌面实机检查，不操作用户窗口。

- `tests/campaign_map_test.gd`：221 项通过，覆盖选关、快速打断、投影与三维路线一致性、连续小台阶、设置隔离、返回记忆、1600 × 900 / 1280 × 720 截图、超宽和 4:3 适配。
- `tests/campaign_model_visual.gd`：全图、森林、木桥、要塞实拍；传入 `--motion` 保存 168 帧的六关切换。
- `tools/validate_product.py`：310 个运行时文件，资源引用与产品边界检查无错误。

可复现视觉检查：

```powershell
python tools/run_godot_private_desktop.py res://tests/campaign_model_visual.gd --output artifacts/campaign_model_final --script-arg=--motion --godot .local/network/runtime/Godot_v4.7.2-stable_win64.exe --timeout 110
```

## 插画参考的定位

之前由内置 image_gen 生成的 `assets/ui/campaign/forest_to_summit.png` 保留为构图参考。它帮助确定森林、溪谷、雪山的连续布局，当前运行场景不再引用它。最终画面来自上述真实三维场景的渲染。
