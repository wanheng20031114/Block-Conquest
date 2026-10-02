// 地形生成：高度图 → 铁路压平 → 隧道 → 体素填充
// 世界坐标 x ∈ [X0, X1)，数组下标 = x - X0
import { X0, X1, WT, D, H, GROUND, RIVER_BED, MAT, ZONE, PEAKS, FIELDS } from './config.js';
import { fbm2, noise2, smoothstep } from './noise.js';

export class World {
  constructor(path) {
    this.path = path;
    const N = WT * D;
    this.h = new Int16Array(N);          // 每格地表高度
    this.top = new Uint8Array(N);        // 顶层材质
    this.zone = new Uint8Array(N);       // 区域
    this.water = new Uint8Array(N);      // 是否为河水
    this.lavender = new Uint8Array(N);   // 薰衣草
    this.solid = new Uint8Array(N);      // 被建筑/树木占据
    this.reserved = new Uint8Array(N);   // 留空（街道、铁路、花田）
    this.floor = new Int16Array(N).fill(-1);    // 隧道内地面
    this.extra = new Float32Array(N).fill(-99); // 站台、桥面等可行走表面
    this.trackD = new Float32Array(N).fill(99); // 到铁路中心线的距离
    this.trackY = new Float32Array(N);
    this.vox = new Uint8Array(WT * H * D);
    this.generate();
  }

  i(x, z) { return z * WT + (x - X0); }
  inside(x, z) { return x >= X0 && z >= 0 && x < X1 && z < D; }
  hAt(x, z) {
    x = Math.max(X0, Math.min(X1 - 1, Math.floor(x)));
    z = Math.max(0, Math.min(D - 1, Math.floor(z)));
    return this.h[this.i(x, z)];
  }
  setVox(x, y, z, m) { this.vox[(y * D + z) * WT + (x - X0)] = m; }
  getVox(x, y, z) { return this.vox[(y * D + z) * WT + (x - X0)]; }
  walkAt(x, z) { return this.walk[this.i(x, z)]; }
  inTunnel(x, z) {
    const tx = Math.floor(x), tz = Math.floor(z);
    return this.inside(tx, tz) && this.floor[this.i(tx, tz)] >= 0;
  }
  isLavender(x, z) {
    const tx = Math.floor(x), tz = Math.floor(z);
    return this.inside(tx, tz) && this.lavender[this.i(tx, tz)] === 1;
  }

  // 一块矩形区域是否可以放东西
  isFree(x0, z0, w, d, allowReserved = false) {
    for (let z = z0; z < z0 + d; z++) for (let x = x0; x < x0 + w; x++) {
      if (!this.inside(x, z)) return false;
      const t = this.i(x, z);
      if (this.solid[t] || this.water[t] || (!allowReserved && this.reserved[t])) return false;
    }
    return true;
  }
  block(x0, z0, w, d) {
    for (let z = z0; z < z0 + d; z++) for (let x = x0; x < x0 + w; x++)
      if (this.inside(x, z)) this.solid[this.i(x, z)] = 1;
  }
  reserve(x0, z0, w, d) {
    for (let z = z0; z < z0 + d; z++) for (let x = x0; x < x0 + w; x++)
      if (this.inside(x, z)) this.reserved[this.i(x, z)] = 1;
  }
  setExtra(x0, z0, w, d, y) {
    for (let z = z0; z < z0 + d; z++) for (let x = x0; x < x0 + w; x++)
      if (this.inside(x, z)) {
        const t = this.i(x, z);
        this.extra[t] = Math.max(this.extra[t], y);
      }
  }

  generate() {
    const { h, top, zone, water } = this;

    // 1) 原始高度与材质
    for (let z = 0; z < D; z++) for (let x = X0; x < X1; x++) {
      const i = this.i(x, z), xc = x + 0.5, zc = z + 0.5;
      let hh = GROUND, tm = MAT.GRASS, zn = ZONE.TOWN;
      if (x < 0) { zn = ZONE.MEADOW; tm = MAT.MEADOW; }
      if (x >= 37) zn = ZONE.FARM;
      if (x >= 50) {
        zn = ZONE.FOREST;
        tm = MAT.FGRASS;
        if (x < 77 && fbm2(x * 0.13, z * 0.13, 3) > 0.6) hh = GROUND + 1;
      }
      // 城堡山（顶部 x 0..7）
      const qx = Math.max(xc - 7.5, 0.5 - xc, 0), qz = Math.max(Math.abs(zc - 21) - 12.5, 0);
      const hv = 13 - Math.ceil(Math.hypot(qx, qz) - 1e-6);
      if (hv > hh) { hh = hv; zn = ZONE.HILL; tm = MAT.HILLGRASS; }
      // 最西边的小山（列车从这里的隧道驶出）
      const qx2 = Math.max(xc + 34.5, 0), qz2 = Math.max(Math.abs(zc - 19) - 14, 0);
      const hv2 = 14 - Math.ceil(Math.hypot(qx2, qz2) * 1.5 - 1e-6);
      if (hv2 > hh) { hh = hv2; zn = ZONE.HILL; tm = MAT.HILLGRASS; }
      // 河流（森林中间，南北向）
      const xr = 63 + 2 * Math.sin(z * 0.2 + 0.6);
      const dr = Math.abs(xc - xr);
      if (dr < 2.1) { hh = RIVER_BED; tm = MAT.SAND; zn = ZONE.RIVER; water[i] = 1; }
      else if (dr < 3.1) { hh = GROUND; tm = MAT.SAND; }
      // 山麓与雪山（右侧）
      if (x >= 76) {
        const base = GROUND + 5 * smoothstep(79, 97, xc);
        const bump = Math.max(0, fbm2(x * 0.13, z * 0.13, 21) - 0.5) * 10 * smoothstep(80, 90, xc);
        let mh = base + bump;
        for (const p of PEAKS) {
          const d = Math.hypot(xc - p.x, zc - p.z);
          const v = p.h - d * p.s + (noise2(x * 0.35, z * 0.35, 5) - 0.5) * 2.4;
          if (v > mh) mh = v;
        }
        hh = Math.max(hh, Math.round(mh));
        if (x >= 82) { zn = xc > 96 ? ZONE.MOUNT : ZONE.FOOT; tm = MAT.GRASS; }
      }
      h[i] = hh; top[i] = tm; zone[i] = zn;
    }

    // 2) 街道与小路
    const paveIf = (x, z, m) => {
      const t = this.i(x, z);
      if (h[t] === GROUND && !water[t]) { top[t] = m; this.reserved[t] = 1; }
    };
    for (let x = 13; x <= 45; x++) { paveIf(x, 19, MAT.COBBLE); paveIf(x, 20, MAT.COBBLE); }
    for (let x = 13; x <= 47; x++) { paveIf(x, 32, MAT.COBBLE); paveIf(x, 33, MAT.COBBLE); }
    for (let z = 5; z <= 33; z++) { paveIf(34, z, MAT.COBBLE); paveIf(35, z, MAT.COBBLE); }
    for (let z = 13; z <= 18; z++) for (let x = 20; x <= 33; x++) paveIf(x, z, MAT.COBBLE);
    for (let z = 27; z <= 28; z++) for (let x = 12; x <= 33; x++) paveIf(x, z, MAT.COBBLE);
    for (let x = -31; x <= -6; x++) paveIf(x, 30, MAT.PATH);           // 花田小路
    for (let z = 29; z <= 34; z++) { paveIf(-24, z, MAT.PATH); }       // 通往农舍
    for (let x = 48; x <= 90; x++) {
      const pc = 32.5 + 1.6 * Math.sin((x - 48) * 0.16);
      for (let z = 29; z <= 36; z++) {
        const t = this.i(x, z);
        if (Math.abs(z + 0.5 - pc) < 1.1 && !water[t] && h[t] <= GROUND + 1) {
          top[t] = MAT.PATH; this.reserved[t] = 1;
          if (h[t] > GROUND && x < 77) h[t] = GROUND;
        }
      }
    }

    // 3) 右侧隧道口：找到山体足够高的位置
    let portalX = X1 - 8;
    for (let x = 100; x < X1 - 6; x++) {
      if (h[this.i(x, 18)] >= 17 && h[this.i(x, 19)] >= 17 && h[this.i(x, 20)] >= 17) { portalX = x; break; }
    }
    this.portalX = portalX;
    for (let x = portalX; x < X1; x++) for (let z = 16; z <= 22; z++) {
      const t = this.i(x, z);
      h[t] = Math.max(h[t], 17 + Math.min(4, x - portalX));
    }
    // 雪峰站所在的平台
    for (let x = 93; x < portalX; x++) for (let z = 16; z <= 28; z++) {
      const t = this.i(x, z);
      h[t] = 13; top[t] = MAT.SNOW; zone[t] = ZONE.MOUNT;
    }

    // 4) 铁路：标记、压平（城堡山里是贯通隧道，不压平）
    const P = this.path;
    this.westFace = -34;
    this.sPortalL = P.sNear(this.westFace, 16.5);
    this.sPortalR = P.sNear(portalX, 19.5);
    const tmp = {};
    for (let s = this.sPortalL - 4; s <= this.sPortalR + 4; s += 0.2) {
      P.at(s, tmp);
      const bx = Math.floor(tmp.x), bz = Math.floor(tmp.z);
      for (let dz = -3; dz <= 3; dz++) for (let dx = -3; dx <= 3; dx++) {
        const tx = bx + dx, tz = bz + dz;
        if (!this.inside(tx, tz)) continue;
        const t = this.i(tx, tz);
        const d = Math.hypot(tx + 0.5 - tmp.x, tz + 0.5 - tmp.z);
        if (d < this.trackD[t]) { this.trackD[t] = d; this.trackY[t] = tmp.y; }
      }
    }
    for (let z = 0; z < D; z++) for (let x = this.westFace; x < portalX; x++) {
      if (x >= -1 && x <= 8) continue; // 城堡山隧道段
      const t = this.i(x, z);
      const d = this.trackD[t];
      if (d >= 2.8) continue;
      const fy = Math.floor(this.trackY[t] + 1e-4);
      if (d < 1.45) {
        if (!water[t]) h[t] = fy;
        if (d < 0.95 && !water[t] && top[t] !== MAT.COBBLE) top[t] = MAT.GRAVEL;
      } else if (x >= 13 && x < portalX - 3 && zone[t] !== ZONE.HILL && !water[t]) {
        if (h[t] > fy + 1) h[t] = fy + 1;
      }
      if (d < 1.9) this.reserved[t] = 1;
    }
    for (let z = 22; z <= 26; z++) for (let x = -1; x <= 8; x++) this.reserved[this.i(x, z)] = 1;

    // 花田站站台
    for (let z = 17; z <= 19; z++) for (let x = -32; x <= -17; x++) this.reserved[this.i(x, z)] = 1;

    // 5) 薰衣草田：一垄花、一垄土
    for (const f of FIELDS) {
      for (let z = f.z0; z <= f.z1; z++) for (let x = f.x0; x <= f.x1; x++) {
        if (!this.inside(x, z)) continue;
        const t = this.i(x, z);
        if (this.reserved[t] || water[t] || h[t] !== GROUND) continue;
        if ((z - f.z0) % 2 === 0) this.lavender[t] = 1;
        else top[t] = MAT.SOIL;
        this.reserved[t] = 1;
      }
    }

    // 6) 雪线、裸岩：高处积雪，陡坡露出岩石
    for (let z = 0; z < D; z++) for (let x = 78; x < X1; x++) {
      const t = this.i(x, z);
      if (water[t] || top[t] === MAT.GRAVEL) continue;
      const snowLine = 88 + (noise2(z * 0.3, 1.7, 7) - 0.5) * 6;
      if (top[t] === MAT.PATH && x + 0.5 < snowLine) continue;
      if (h[t] >= 16 || x + 0.5 > snowLine) top[t] = MAT.SNOW;
      if (zone[t] === ZONE.MOUNT && h[t] >= 14) {
        let slope = 0;
        for (const [ax, az] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          if (this.inside(x + ax, z + az)) slope = Math.max(slope, h[t] - h[this.i(x + ax, z + az)]);
        }
        const capLine = 21 + (noise2(x * 0.4, z * 0.4, 13) - 0.5) * 4;
        if (h[t] < capLine && (slope >= 2 || hash01(x, z) > 0.55)) top[t] = MAT.ROCK;
      }
    }

    // 7) 填充体素
    for (let z = 0; z < D; z++) for (let x = X0; x < X1; x++) {
      const t = this.i(x, z);
      const hh = Math.min(h[t], H), tm = top[t], zn = zone[t];
      const mountain = zn === ZONE.MOUNT || zn === ZONE.FOOT;
      for (let y = 0; y < hh; y++) {
        let m;
        if (y === hh - 1) m = tm;
        else if (tm === MAT.SNOW && hh >= 18 && y >= hh - 2) m = MAT.SNOW;
        else if (y >= 27) m = MAT.SNOW;
        else if (mountain && y >= 9) m = (y >= hh - 3 && tm !== MAT.SNOW && tm !== MAT.ROCK) ? MAT.DIRT : MAT.ROCK;
        else if (y >= 6) m = MAT.DIRT;
        else if (y >= 4) m = MAT.DIRT2;
        else if (y >= 1) m = MAT.STONE;
        else m = MAT.DEEP;
        this.setVox(x, y, z, m);
      }
    }

    // 8) 挖隧道
    this.tunnels = [];
    const carve = (x0, x1, z0, z1, y0, y1) => {
      for (let x = x0; x <= x1; x++) for (let z = z0; z <= z1; z++) {
        for (let y = y0; y <= y1; y++) this.setVox(x, y, z, MAT.AIR);
        this.floor[this.i(x, z)] = y0;
      }
    };
    carve(-37, -35, 15, 17, GROUND, GROUND + 2);      // 西山隧道
    carve(-1, 8, 23, 25, GROUND, GROUND + 2);         // 城堡山贯通隧道
    carve(portalX, portalX + 2, 18, 20, 13, 15);      // 雪山隧道
    this.tunnels.push({ face: this.westFace, dir: 1, z: 16.5, y: GROUND });
    this.tunnels.push({ face: -1, dir: -1, z: 24.5, y: GROUND });
    this.tunnels.push({ face: 9, dir: 1, z: 24.5, y: GROUND });
    this.tunnels.push({ face: portalX, dir: -1, z: 19.5, y: 13 });
  }

  // 生成可行走高度表（道具放完之后调用）
  buildWalk() {
    const N = WT * D;
    this.walk = new Float32Array(N);
    for (let t = 0; t < N; t++) {
      // 隧道里不让人走：只看地表，这样山顶上也不会掉进隧道
      let w = this.h[t];
      if (this.water[t]) w = -50;
      if (this.extra[t] > -90) w = Math.max(this.water[t] ? -99 : w, this.extra[t]);
      this.walk[t] = w;
    }
  }
}

function hash01(x, z) {
  let n = Math.imul(x, 73856093) ^ Math.imul(z, 19349663);
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}
