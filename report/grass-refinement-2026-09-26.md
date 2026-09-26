# 草地噪波、色块与林间小路修正

本轮依据用户后补的草地参考，修正上一版地面的大块冷暖混色、重复域扭曲和泥状道路过渡。积木战争六图为主，一般模式共用色块方法并保留较暖配色。用户确认草地后，进一步将小路改为缓弯走向与渐变路肩；确认过的草地 include 和噪波资源通过 SHA256 核对保持不变。

## 材质变化

- 三档相近的橄榄绿色代替偏蓝暗绿与偏黄亮绿的组合。块内保持纯色，树木和建筑的真实投影继续由原有日光、阴影与环境遮蔽产生。
- 原生 `FastNoiseLite` 关闭域扭曲，以一个形状场确定色块。保留权重 0.23 的第二个 octave，使轮廓不全是圆滑长条；不把噪波直接叠到颜色上。
- 细噪波只改变轮廓。根据形状场在世界坐标中的梯度缩放扰动，把边缘位移约束在约四分之一米，避免平缓区域被固定幅度的噪波打散成碎斑。
- `NoiseTexture2D` 提升到 1024×1024，世界坐标重复周期 190 米，大于最大地图的可玩宽度。导数抗锯齿仅覆盖色块边缘，不再用大范围模糊混色。
- 草簇改为三片尖叶，尺度和朝向有小幅变化，密度降低，远处淡出。保留已有的立体地被、花与树石。
- 土路内部使用统一土色，去掉让草斑透进整个路面的半透明混色。根据后续反馈，将最初较硬的边缘改为约 0.94 米的渐变路肩，中心保持清楚。噪波控制磨损造成的宽窄变化，庭院和门前土路也柔和融入草地。
- 小路采用低频噪波统一弯曲整套路网，位移长度限制为 1.4 米；岔路使用平滑距离并集柔化内角。建筑周边和真实桥面区域逐渐关闭弯曲，保证门口与桥头仍接在原位置，桥上道路保持笔直。
- 天空原本使用同一个噪波资源，现将其原数据保存为 `daylight_clouds.tres`。逐字核对与旧噪波资源一致，天空和水面反射不随草地参数改变。
- 六张地图定义、五张场景材质覆盖和作者工具同步配色与桥面区域。场景差异仅为材质参数，树石变换、导航、建筑与桥梁几何均未修改。

主要编辑入口：

| 用途 | 文件 |
| --- | --- |
| 色块、轮廓抗锯齿、尖叶草簇 | `assets/block_war/environment/meadow_surface.gdshaderinc` |
| 原生形状噪波 | `assets/block_war/environment/meadow_noise.tres` |
| 积木战争配色和土路 | `forest_ground.gdshader`、`map_ground.gdshader` |
| 小路弯曲、岔口与渐变路肩 | `assets/block_war/environment/woodland_paths.gdshaderinc` |
| 一般模式配色 | `assets/models/environment/skirmish_meadow.gdshader` |

## 实拍验证

Godot 4.6.3 / Forward+ / RTX 3080 Ti / 1600×900。草地经过三轮实际渲染调整色块尺度、轮廓与草簇；确认后继续实拍检查六图小路。

- `tests/meadow_surface_visual.gd`：六图全景与近景、同一地面在战术缩放下平移及静止对照，共 15 张。最终运行没有脚本、材质编译或资源退出错误。
- 镜头平移后等待 45 帧，再拍同一镜头。林湖右侧无树、水、烟的草地 ROI（x=1250–1369，y=355–499）RGB 平均差约 0.011/255，99% 分位为 0；其余少量差异来自抗锯齿收敛。这是静止对照，不代表全部动态场景的量化测试。
- `tests/block_war_maps_visual.gd`：六图真实对局、桥头与中央石台、镜头微移。草地阶段还检查了三页选图；包含选图的验证退出时提示两个资源未释放，上一轮已定位为选择音效，详见树石复查报告。本轮未修改音频代码。
- 一般模式真实出生点实拍，检查石路、草色、建筑阴影与战争迷雾，正常退出。
- `tests/block_war_map_authoring_test.py`：10 项通过，包括原有道路骨架到桥面、建筑门口的连接与桥梁几何。
- 六张地图定义与作者工具配色一致，五张地图材质中的桥面区域与地图定义逐项相符。场景除材质参数外与修改前完全相同。天空噪波与修改前数据一致。
- `python tools/build_content_manifest.py --check` 通过，无需重建联机内容清单。

最终独立环境预览 GPU 中位数约 3.12–5.22 ms，P95 约 3.36–5.61 ms。该采样不含战斗负载，且宿主同时运行用户编辑器，仅用于检查明显的材质性能异常。

截图保存在本机 `artifacts/grass_refinement/after/`；修改前的同镜头对局截图在 `before/`，第一轮草地试稿在 `iteration1/`，用户确认草地后、小路调整前的画面在 `path_before/`。完整对局与选图结果另在 `artifacts/block_war_maps/`。这些图片按项目规则不提交。

- [林湖最终对局](../artifacts/grass_refinement/after/lake_gameplay.png)
- [林湖草地近景](../artifacts/grass_refinement/after/lake_ground.png)
- [林湖修改前](../artifacts/grass_refinement/before/lake_gameplay.png)
- [一般模式最终实拍](../artifacts/grass_refinement/after/normal_gameplay.png)

复查：`Godot_console.exe --path . --audio-driver Dummy --script tests/meadow_surface_visual.gd`；末尾追加 `-- lake rift` 可只检查小图。

实现参考：[Godot FastNoiseLite](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html)、[shader 导数函数](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_functions.html)。本轮直接修正原生程序化材质，没有新增位图素材或运行时景观节点。
