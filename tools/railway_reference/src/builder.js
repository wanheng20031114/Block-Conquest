// 方块合并器：把成千上万个小方块合并成一个网格（每个方块可旋转、可着色）
import * as THREE from 'three';
import { mulberry32, smoothstep } from './noise.js';

// 单位立方体 6 个面：法线 + 4 个角（从外面看逆时针）
const FACES = [
  [[1, 0, 0], [[.5, -.5, -.5], [.5, .5, -.5], [.5, .5, .5], [.5, -.5, .5]]],
  [[-1, 0, 0], [[-.5, -.5, -.5], [-.5, -.5, .5], [-.5, .5, .5], [-.5, .5, -.5]]],
  [[0, 1, 0], [[-.5, .5, -.5], [-.5, .5, .5], [.5, .5, .5], [.5, .5, -.5]]],
  [[0, -1, 0], [[-.5, -.5, -.5], [.5, -.5, -.5], [.5, -.5, .5], [-.5, -.5, .5]]],
  [[0, 0, 1], [[-.5, -.5, .5], [.5, -.5, .5], [.5, .5, .5], [-.5, .5, .5]]],
  [[0, 0, -1], [[-.5, -.5, -.5], [-.5, .5, -.5], [.5, .5, -.5], [.5, -.5, -.5]]],
];

const _m = new THREE.Matrix4();
const _e = new THREE.Euler(0, 0, 0, 'YZX');
const _v = new THREE.Vector3();
const _n = new THREE.Vector3();
const _c = new THREE.Color();

export class BoxBuilder {
  constructor(seed = 7) {
    this.pos = [];
    this.nor = [];
    this.col = [];
    this.idx = [];
    this.vc = 0;
    this.groundY = null;   // 设定后，靠近地面的顶点会变暗（接触阴影）
    this.rand = mulberry32(seed);
    this.cache = new Map();
  }

  color(hex) {
    let c = this.cache.get(hex);
    if (!c) { c = new THREE.Color().setHex(hex); this.cache.set(hex, c); }
    return c;
  }

  setGround(y) { this.groundY = y; }

  // 中心点 + 尺寸 + 旋转（ry 偏航, rz 俯仰, rx 侧倾）
  box(cx, cy, cz, sx, sy, sz, hex, ry = 0, rz = 0, rx = 0, jitter = 0.05, skipBottom = false) {
    const base = typeof hex === 'number' ? this.color(hex) : hex;
    const k = 1 + (this.rand() - 0.5) * 2 * jitter;
    const rot = ry !== 0 || rz !== 0 || rx !== 0;
    if (rot) { _e.set(rx, ry, rz, 'YZX'); _m.makeRotationFromEuler(_e); }
    const g = this.groundY;
    for (let f = 0; f < 6; f++) {
      if (skipBottom && f === 3) continue;
      const [n, corners] = FACES[f];
      _n.set(n[0], n[1], n[2]);
      if (rot) _n.applyMatrix4(_m).normalize();
      const shade = f === 3 ? 0.72 : 1;
      for (let i = 0; i < 4; i++) {
        const cc = corners[i];
        _v.set(cc[0] * sx, cc[1] * sy, cc[2] * sz);
        if (rot) _v.applyMatrix4(_m);
        _v.x += cx; _v.y += cy; _v.z += cz;
        let ao = 1;
        if (g !== null) ao = 0.74 + 0.26 * smoothstep(0, 1.0, _v.y - g);
        _c.copy(base).multiplyScalar(k * ao * shade);
        this.pos.push(_v.x, _v.y, _v.z);
        this.nor.push(_n.x, _n.y, _n.z);
        this.col.push(_c.r, _c.g, _c.b);
      }
      const v = this.vc;
      this.idx.push(v, v + 1, v + 2, v, v + 2, v + 3);
      this.vc += 4;
    }
  }

  // 以最小角点定位的轴对齐方块
  cube(x, y, z, sx, sy, sz, hex, jitter = 0.05) {
    this.box(x + sx / 2, y + sy / 2, z + sz / 2, sx, sy, sz, hex, 0, 0, 0, jitter);
  }

  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setIndex(this.idx);
    g.computeBoundingSphere();
    return g;
  }

  mesh(material, { cast = true, receive = true } = {}) {
    const m = new THREE.Mesh(this.geometry(), material);
    m.castShadow = cast;
    m.receiveShadow = receive;
    return m;
  }
}
