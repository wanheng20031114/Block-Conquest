// 体素网格化：只生成暴露面，并在顶点上烘焙环境光遮蔽（AO）
import * as THREE from 'three';
import { X0, WT, D, H, MAT_COLORS, WATER_Y, RIVER_BED } from './config.js';
import { hash3 } from './noise.js';

const AO_LEVELS = [0.5, 0.68, 0.85, 1.0];
// 每个轴向：[法线轴 d, 切线轴 u, 切线轴 v]，满足 e_u × e_v = e_d
const AXES = [[0, 1, 2], [1, 2, 0], [2, 0, 1]];
const POS_CORNERS = [[0, 0], [1, 0], [1, 1], [0, 1]];
const NEG_CORNERS = [[0, 0], [0, 1], [1, 1], [1, 0]];

function linearColor(hex) {
  return new THREE.Color().setHex(hex);
}

export function meshTerrain(world) {
  const { vox } = world;
  const solid = (x, y, z) => {
    if (y < 0) return true;
    if (x < 0 || z < 0 || x >= WT || z >= D || y >= H) return false;
    return vox[(y * D + z) * WT + x] !== 0;
  };

  const palette = {};
  for (const k of Object.keys(MAT_COLORS)) {
    palette[k] = [linearColor(MAT_COLORS[k][0]), linearColor(MAT_COLORS[k][1])];
  }
  const warm = linearColor(0xc6dc62);
  const paleWarm = linearColor(0xe0f0a8);

  const pos = [], nor = [], col = [], idx = [];
  let vc = 0;
  const p = [0, 0, 0], b = [0, 0, 0], q = [0, 0, 0];
  const c = new THREE.Color();
  const aos = [0, 0, 0, 0];

  for (let y = 0; y < H; y++) for (let z = 0; z < D; z++) for (let x = 0; x < WT; x++) {
    const m = vox[(y * D + z) * WT + x];
    if (!m) continue;
    const pal = palette[m];
    const jit = 0.93 + 0.13 * hash3(x + X0, y, z);
    const grassy = m === 1 || m === 2 || m === 13;
    const meadow = m === 14;
    const warmMix = grassy || meadow ? hash3(x + X0 + 17, y, z - 5) * (meadow ? 0.45 : 0.28) : 0;

    for (let a = 0; a < 3; a++) {
      const [d, u, v] = AXES[a];
      for (const sign of [1, -1]) {
        q[0] = x; q[1] = y; q[2] = z;
        q[d] += sign;
        if (solid(q[0], q[1], q[2])) continue;

        const isTop = d === 1 && sign > 0;
        const isBottom = d === 1 && sign < 0;
        c.copy(isTop ? pal[0] : pal[1]);
        if (warmMix && isTop) c.lerp(meadow ? paleWarm : warm, warmMix);
        c.multiplyScalar(jit * (isBottom ? 0.7 : 1));

        const corners = sign > 0 ? POS_CORNERS : NEG_CORNERS;
        for (let k = 0; k < 4; k++) {
          const [cu, cv] = corners[k];
          // 顶点位置
          p[0] = x; p[1] = y; p[2] = z;
          if (sign > 0) p[d] += 1;
          p[u] += cu; p[v] += cv;
          // AO：检查法线方向那一层里的三个邻居
          b[0] = x; b[1] = y; b[2] = z; b[d] += sign;
          const su = cu ? 1 : -1, sv = cv ? 1 : -1;
          q[0] = b[0]; q[1] = b[1]; q[2] = b[2]; q[u] += su;
          const s1 = solid(q[0], q[1], q[2]) ? 1 : 0;
          q[0] = b[0]; q[1] = b[1]; q[2] = b[2]; q[v] += sv;
          const s2 = solid(q[0], q[1], q[2]) ? 1 : 0;
          q[0] = b[0]; q[1] = b[1]; q[2] = b[2]; q[u] += su; q[v] += sv;
          const s3 = solid(q[0], q[1], q[2]) ? 1 : 0;
          const ao = s1 && s2 ? 0 : 3 - (s1 + s2 + s3);
          aos[k] = ao;
          const f = AO_LEVELS[ao];
          pos.push(p[0] + X0, p[1], p[2]);
          nor.push(d === 0 ? sign : 0, d === 1 ? sign : 0, d === 2 ? sign : 0);
          col.push(c.r * f, c.g * f, c.b * f);
        }
        if (aos[0] + aos[2] < aos[1] + aos[3]) {
          idx.push(vc, vc + 1, vc + 3, vc + 1, vc + 2, vc + 3);
        } else {
          idx.push(vc, vc + 1, vc + 2, vc, vc + 2, vc + 3);
        }
        vc += 4;
      }
    }
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  g.computeBoundingSphere();
  return g;
}

// 河水：顶面 + 地图边缘的切面；岸边顶点调亮做出泡沫感
export function meshWater(world) {
  const { water } = world;
  const isW = (x, z) => x >= X0 && z >= 0 && x < X0 + WT && z < D && water[z * WT + (x - X0)] === 1;
  const base = linearColor(0x56c3e6);
  const deep = linearColor(0x3fa7d6);
  const foam = linearColor(0xe9fbff);
  const pos = [], nor = [], col = [], idx = [];
  let vc = 0;
  const c = new THREE.Color();

  const cornerFoam = (vx, vz) => {
    // 共享该顶点的四个格子里有非水格 → 泡沫
    for (const [ox, oz] of [[0, 0], [-1, 0], [0, -1], [-1, -1]]) {
      const tx = vx + ox, tz = vz + oz;
      if (tx < X0 || tz < 0 || tx >= X0 + WT || tz >= D) continue;
      if (!isW(tx, tz)) return 1;
    }
    return 0;
  };

  for (let z = 0; z < D; z++) for (let x = X0; x < X0 + WT; x++) {
    if (!isW(x, z)) continue;
    const corners = [[x, z], [x, z + 1], [x + 1, z + 1], [x + 1, z]];
    for (const [vx, vz] of corners) {
      const f = cornerFoam(vx, vz);
      c.copy(base).lerp(deep, 0.5 + 0.5 * Math.sin(vx * 0.9 + vz * 0.7));
      if (f) c.lerp(foam, 0.55);
      pos.push(vx, WATER_Y, vz);
      nor.push(0, 1, 0);
      col.push(c.r, c.g, c.b);
    }
    idx.push(vc, vc + 1, vc + 2, vc, vc + 2, vc + 3);
    vc += 4;

    // 前后边缘的水体切面
    for (const [edgeZ, nz] of [[D - 1, 1], [0, -1]]) {
      if (z !== edgeZ) continue;
      const zz = nz > 0 ? z + 1 : z;
      const quad = nz > 0
        ? [[x, RIVER_BED, zz], [x + 1, RIVER_BED, zz], [x + 1, WATER_Y, zz], [x, WATER_Y, zz]]
        : [[x, RIVER_BED, zz], [x, WATER_Y, zz], [x + 1, WATER_Y, zz], [x + 1, RIVER_BED, zz]];
      for (const v of quad) {
        pos.push(v[0], v[1], v[2]);
        nor.push(0, 0, nz);
        c.copy(deep).multiplyScalar(v[1] > 6 ? 1 : 0.8);
        col.push(c.r, c.g, c.b);
      }
      idx.push(vc, vc + 1, vc + 2, vc, vc + 2, vc + 3);
      vc += 4;
    }
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}
