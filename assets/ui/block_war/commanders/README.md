# 已采用的像素动物立绘

对应用户批准的 `docs/art/block_war_commanders.png`：squirrel 榛果、rabbit 跳豆、bear 栗团、beaver 木丁、fox 灯芯、frog 苔铃。

当前默认头像使用 squirrel.png。其余五张是正式采用的美术素材，专属技能与选人流程尚未实装。

通过内置 image_gen 对批准造型做透明背景提取，输出 1536×1024 RGBA；空白区具有真实 Alpha=0。后处理只按区域切分、按 Alpha 包围盒裁切、居中并底部对齐补入 576×576 透明画布（底边 20 px），保存 PNG。未根据 RGB 推断透明度，未重新描绘或缩放像素。Godot 导入无损、无 mipmap，HUD 最近邻采样。

源提取图名：`exec-81a28a10-055f-4224-9f3d-4bac24e22d21.png`。各角色切分区域（左、上、右、下）：

| 文件 | 提取图区域 |
| --- | --- |
| squirrel.png | 0, 0, 550, 524 |
| rabbit.png | 550, 0, 1035, 524 |
| bear.png | 1035, 0, 1536, 524 |
| beaver.png | 0, 524, 580, 1024 |
| fox.png | 580, 524, 1068, 1024 |
| frog.png | 1068, 524, 1536, 1024 |

提取提示词：

> Use case: background-extraction. Edit target: the approved six-animal pixel-art commander sheet attached. Extract these EXACT SIX approved animal sprites as a production RGBA sprite sheet. Preserve every animal's identity, color palette, expression, pose, ears, tails, clothing and props. Preserve the same 3-column by 2-row ordering: squirrel, rabbit, bear, beaver, fox, frog. Do not redesign or reinterpret any character. Remove the cream background completely, remove ALL numbered labels 01 through 06, remove all ground shadows. Output a GENUINELY TRANSPARENT background using an actual alpha channel. Not a checkerboard illustration, not white, cream, grey or black. Every empty area around and between animals, including holes between limbs and accessories, must have alpha zero. Keep the entire character including every ear, tail, foot, basket, shield, hammer and lantern inside its own grid cell with clean transparent padding. Keep clean hard pixel-art edges and clear small pixel clusters. Do not add glow halos, backgrounds, text or any new elements. One animal per cell, 3 columns x 2 rows, equal cell sizes and sufficient margins so the six separate characters can be cropped losslessly. Native transparent PNG RGBA output.
