// 世界尺寸与全局常量
// x 轴：左(城镇) → 右(雪山)；z 轴：后(远) → 前(近，靠镜头)；y 轴：高度
export const X0 = -40;       // 地图最左端（向左扩出来的花田）
export const X1 = 128;       // 地图最右端（不含）
export const WT = X1 - X0;   // 地图总宽（格）
export const D = 40;         // 地图深（格）
export const H = 36;         // 最大体素高度
export const GROUND = 8;     // 平地地表高度
export const RIVER_BED = 5;  // 河床高度
export const WATER_Y = 7.55; // 水面高度

export const MAT = {
  AIR: 0, GRASS: 1, FGRASS: 2, DIRT: 3, DIRT2: 4, STONE: 5, DEEP: 6,
  ROCK: 7, SNOW: 8, COBBLE: 9, PATH: 10, SAND: 11, GRAVEL: 12, HILLGRASS: 13,
  MEADOW: 14, SOIL: 15,
};

// 每种材质的 [顶面色, 侧面色]（sRGB）——偏《一起开火车》那种饱和又柔和的配色
export const MAT_COLORS = {
  [MAT.GRASS]:     [0x9fd055, 0x8dc04b],
  [MAT.FGRASS]:    [0x86c14f, 0x76b047],
  [MAT.DIRT]:      [0xd09862, 0xc98f5a],
  [MAT.DIRT2]:     [0xb07a4e, 0xa9724a],
  [MAT.STONE]:     [0x968fa6, 0x928ba2],
  [MAT.DEEP]:      [0x77718c, 0x726c86],
  [MAT.ROCK]:      [0xa3abc0, 0x99a1b8],
  [MAT.SNOW]:      [0xf5f9ff, 0xe1eaf7],
  [MAT.COBBLE]:    [0xd6cbb6, 0xc2b7a2],
  [MAT.PATH]:      [0xe2bd88, 0xd1a978],
  [MAT.SAND]:      [0xf0de9f, 0xe2cd8d],
  [MAT.GRAVEL]:    [0xb8ac9a, 0xaa9e8c],
  [MAT.HILLGRASS]: [0xa6d65c, 0x93c450],
  [MAT.MEADOW]:    [0xc4e896, 0xb0d683],  // 西边花田的浅绿草地
  [MAT.SOIL]:      [0xd2b07e, 0xc29f6e],  // 薰衣草垄间的土
};

export const ZONE = { TOWN: 0, FARM: 1, FOREST: 2, RIVER: 3, FOOT: 4, MOUNT: 5, HILL: 6, MEADOW: 7 };

// 雪山的几座山峰：位置、高度、坡度
export const PEAKS = [
  { x: 94,  z: 7,  h: 19, s: 1.8 },
  { x: 104, z: 3,  h: 27, s: 1.7 },
  { x: 114, z: 7,  h: 34, s: 1.55 },
  { x: 125, z: 5,  h: 31, s: 1.6 },
  { x: 121, z: 19, h: 31, s: 1.5 },
  { x: 125, z: 33, h: 27, s: 1.7 },
  { x: 110, z: 37, h: 21, s: 1.8 },
];

// 薰衣草田（矩形，含端点）。偶数行种薰衣草，奇数行留出土垄
export const FIELDS = [
  { x0: -31, x1: -17, z0: 3, z1: 13 },
  { x0: -31, x1: -17, z0: 20, z1: 28 },
  { x0: -12, x1: -6, z0: 3, z1: 13 },
  { x0: -13, x1: -6, z0: 32, z1: 38 },
];

// 铁路走向（拐角处自动倒圆角）。首尾两点藏在山体隧道里
export const WAYPOINTS = [
  [-38.5, 16.5], [-12.5, 16.5], [-12.5, 24.5], [40.5, 24.5], [40.5, 15.5], [79.5, 15.5],
  [79.5, 27.5], [89.5, 27.5], [89.5, 19.5], [124.5, 19.5],
];

export const STATION_NAMES = { meadow: '花田站', town: '橡木镇', mountain: '雪峰站' };
export const NPC_SPOT = { x: 106.2, z: 22.4 };  // 雪峰站老站长站的位置

// 线路图上的分区（世界 x 坐标）
export const ZONES_X = [
  { key: 'meadow', from: X0, to: 0, label: '花田' },
  { key: 'town', from: 0, to: 37, label: '橡木镇' },
  { key: 'farm', from: 37, to: 50, label: '' },
  { key: 'forest', from: 50, to: 82, label: '林地 · 河' },
  { key: 'snow', from: 82, to: X1, label: '雪峰站' },
];

// 天空 / 雾色
export const SKY = { fog: 0xcde6ee, top: '#a9d4ea', bottom: '#e4f0e6' };
