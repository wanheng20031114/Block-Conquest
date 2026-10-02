# 参考项目真实模型导入

`src/` 是用户提供的 `medieval-voxel-railway` 项目九个建模源文件的原样快照，保留 UTF-8 内容和原始换行；`source-package.json` 记录其 ISC 许可和 Three.js 版本。原参考项目文件夹不会被修改。每个文件的 SHA-256 写入导出清单，可核实来源。

运行 `node tools/import_reference_railway.mjs`。该工具使用 `.local/railway-import/node_modules/three` 中的 Three.js 0.170.0 和官方 `GLTFExporter`，执行原 `TrackPath`、`World`、`meshTerrain`、`meshWater`、`buildProps`、`buildTrack` 和 `Train`。完整 168 × 40 世界及九节原车厢导出到 `assets/campaign/reference_railway/`。

跨引擎适配与用户指定的局部改建：

- 浏览器 `signMesh` 的 Canvas 字牌改为同尺寸、同底色平面，原文字、颜色、尺寸、世界变换写入 `manifest.json`，供 Godot 原生 `Label3D` 显示。
- Lambert 材质改为 `MeshStandardMaterial`，粗糙度 1、金属度 0，保持原材质颜色及原线性顶点色，不重复转换色彩空间。
- 按用户偏好，仅四种地表草地材质（普通、森林、山坡、花田）采用明亮、低饱和鼠尾草配色，并协调仅用于草地的两种暖色混合高光。树叶、屋顶、水、石材及列车保留原色；`manifest.json` 记录草色。源码快照不改，`MAT_COLORS` 只在内存赋值，`mesher` 的两处高光替换严格核对原语句后才写运行副本。
- `GLTFExporter` 的 `FileReader` 由 Node Blob 的两种明确转换补齐，不模拟 DOM。
- 九个车厢分别导出，清除整体路径位置及旋转，车头朝本地 +X；原车轮、车厢结构、颜色和尺寸全部保留。

六关战役保留原三个车站，另由 `campaign_stations.mjs` 执行原 `haltPlatform`，将其完整站台、雨棚、长椅、灯、木箱和站牌沿原铁路布置为林间驿站、河岸驿站、山麓驿站。原始建模快照不修改，只在运行副本中额外导出该函数。新站占地在原植被生成前留出，坡段只添加必要的原石色支柱；输出独立 `campaign_stations.glb`。原地图尺寸和铁路路线保持不变。

按用户偏好仅调整四种地表草色和草地高光，数值记录在 `manifest.json` 的 `grass_palette` / `grass_highlights`。树叶、建筑和列车仍使用原色。随后运行 `tools/bake_reference_railway.gd`，通过原生 `GLTFDocument` 转为 `native/*.scn`，并保存可直接打开的 Godot 铁路场景；完整构建步骤见 `docs/art/campaign_route_map.md`。

`manifest.json` 包含稠密铁路坐标（y 已包含车轮接触轨道的 +0.27）、原三站停车弧长、各车厢长度及编组间距、字牌和模型统计。旗帜与风车扇叶保留独立命名节点，便于在 Godot 中原生动画。

Godot 原生导入流程参考：[Importing 3D scenes](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html)。

`hydrangea_garden.mjs` 按用户要求将西侧花田改建为紫阳花海：196 丛灌木，每丛三球，近景每球 47 朵小花、每朵四瓣、每瓣七个体素颗粒。原扁平花排的几何被明确移除，随机序列保留；四块花床换成草地和弯曲小径，字牌改为“紫阳花海”。原始源码快照未修改。近远两级模型共享形状属性，Godot 烘焙时设置原生可见距离，运行时无花朵节点生成。
