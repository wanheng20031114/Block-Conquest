// 小火车：车头 + 煤水车 + 货车 + 客车 + 守车，沿轨道往返雪山
import * as THREE from 'three';
import { BoxBuilder } from './builder.js';
import { shade } from './props.js';

const TEAL = 0x2f8f86, CREAM = 0xf3e6c8, RED = 0xcf4a3c, BRASS = 0xeab84d, DARK = 0x3a3d48, GLASS = 0x56739a;

const matCache = new Map();
function flatMat(hex) {
  if (!matCache.has(hex)) matCache.set(hex, new THREE.MeshLambertMaterial({ color: hex, flatShading: true }));
  return matCache.get(hex);
}
function cyl(r, len, hex, segs = 8) {
  const g = new THREE.CylinderGeometry(r, r, len, segs);
  g.rotateY(Math.PI / segs);
  g.rotateZ(Math.PI / 2); // 轴线沿 x
  const m = new THREE.Mesh(g, flatMat(hex));
  m.castShadow = true;
  return m;
}
function wheel(r) {
  const grp = new THREE.Group();
  const g = new THREE.CylinderGeometry(r, r, 0.1, 8);
  g.rotateX(Math.PI / 2); // 轴线沿 z
  const m = new THREE.Mesh(g, flatMat(0x45434f));
  const hub = new THREE.Mesh(new THREE.BoxGeometry(r * 0.9, r * 0.25, 0.12), flatMat(RED));
  m.castShadow = true;
  grp.add(m, hub);
  return grp;
}

function chassis(b, len) {
  b.box(0, 0.36, 0, len - 0.1, 0.14, 0.92, DARK);
  b.box(len / 2 + 0.06, 0.36, 0, 0.16, 0.08, 0.1, DARK);
  b.box(-len / 2 - 0.06, 0.36, 0, 0.16, 0.08, 0.1, DARK);
  for (const sd of [-1, 1]) b.box(sd * (len / 2 - 0.04), 0.36, 0, 0.08, 0.18, 1.04, RED);
}

function finish(b, mat, len, wheelXs, r, extra = {}) {
  const group = new THREE.Group();
  group.rotation.order = 'YZX';
  const body = b.mesh(mat, { cast: true, receive: true });
  group.add(body);
  const wheels = [];
  for (const x of wheelXs) for (const z of [-0.5, 0.5]) {
    const w = wheel(r);
    w.position.set(x, r, z);
    group.add(w);
    wheels.push(w);
  }
  return { group, len, wheels, r, ...extra };
}

function buildLoco(mat) {
  const b = new BoxBuilder(31);
  const len = 2.6;
  chassis(b, len);
  // 排障器
  b.box(1.42, 0.22, 0, 0.18, 0.16, 1.0, 0xf2c14e);
  b.box(1.52, 0.12, 0, 0.12, 0.1, 0.78, 0xf2c14e);
  // 驾驶室
  b.box(-0.72, 0.96, 0, 0.95, 1.0, 1.06, TEAL);
  b.box(-0.72, 0.6, 0, 0.97, 0.08, 1.08, BRASS);
  for (const sd of [-1, 1]) {
    b.box(-0.72, 1.15, sd * 0.535, 0.5, 0.34, 0.02, GLASS, 0, 0, 0, 0);
    b.box(-0.72, 1.15, sd * 0.545, 0.58, 0.04, 0.02, CREAM, 0, 0, 0, 0);
  }
  b.box(-0.24, 1.2, 0.26, 0.02, 0.26, 0.26, GLASS, 0, 0, 0, 0);
  b.box(-0.24, 1.2, -0.26, 0.02, 0.26, 0.26, GLASS, 0, 0, 0, 0);
  b.box(-0.72, 1.52, 0, 1.18, 0.1, 1.26, CREAM);
  b.box(-0.72, 1.61, 0, 0.92, 0.08, 1.0, shade(CREAM, 0.9));
  // 烟囱、汽包、头灯
  b.box(0.98, 1.3, 0, 0.24, 0.44, 0.24, DARK);
  b.box(0.98, 1.56, 0, 0.36, 0.12, 0.36, DARK);
  b.box(0.3, 1.27, 0, 0.3, 0.2, 0.3, BRASS);
  b.box(0.3, 1.39, 0, 0.18, 0.06, 0.18, BRASS);
  b.box(1.25, 1.08, 0, 0.12, 0.18, 0.22, 0xfff0b0, 0, 0, 0, 0);
  b.box(1.22, 1.08, 0, 0.1, 0.24, 0.28, DARK);
  // 侧走板
  for (const sd of [-1, 1]) b.box(0.4, 0.5, sd * 0.5, 1.6, 0.05, 0.14, DARK);
  const car = finish(b, mat, len, [-0.75, 0.05, 0.85], 0.24);
  const boiler = cyl(0.38, 1.5, TEAL);
  boiler.position.set(0.42, 0.86, 0);
  const smokebox = cyl(0.39, 0.24, DARK);
  smokebox.position.set(1.12, 0.86, 0);
  car.group.add(boiler, smokebox);
  for (const x of [0.0, 0.62]) {
    const band = cyl(0.395, 0.06, BRASS);
    band.position.set(x, 0.86, 0);
    car.group.add(band);
  }
  car.chimney = new THREE.Vector3(0.98, 1.72, 0);
  car.seat = new THREE.Vector3(-0.72, 0.5, 0);
  return car;
}

function buildTender(mat) {
  const b = new BoxBuilder(32);
  const len = 1.7;
  chassis(b, len);
  b.box(0, 0.72, 0, 1.55, 0.58, 1.0, TEAL);
  b.box(0, 0.62, 0, 1.57, 0.07, 1.02, BRASS);
  b.box(0, 1.03, 0, 1.6, 0.06, 1.05, CREAM);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 3; j++) {
    b.box(-0.55 + i * 0.37, 1.06 + ((i + j) % 2) * 0.06, -0.3 + j * 0.3, 0.3, 0.14, 0.26, 0x2b2a31, 0, 0, 0, 0.1);
  }
  return finish(b, mat, len, [-0.45, 0.45], 0.2, { seat: new THREE.Vector3(0, 1.1, 0) });
}

function buildWagon(mat) {
  const b = new BoxBuilder(33);
  const len = 2.2;
  chassis(b, len);
  b.box(0, 0.48, 0, 2.1, 0.1, 1.0, 0x9c6a42);
  for (const sd of [-1, 1]) {
    b.box(0, 0.7, sd * 0.47, 2.1, 0.34, 0.08, 0xb07a48);
    b.box(0, 0.88, sd * 0.47, 2.14, 0.05, 0.1, 0x704b31);
    for (let k = -2; k <= 2; k++) b.box(k * 0.5, 0.7, sd * 0.515, 0.06, 0.36, 0.02, 0x704b31);
  }
  for (const sd of [-1, 1]) b.box(sd * 1.03, 0.7, 0, 0.08, 0.34, 1.0, 0xb07a48);
  // 货物：木箱 + 原木
  b.box(0.6, 0.78, -0.18, 0.5, 0.5, 0.5, 0xc0904f);
  b.box(0.6, 0.78, -0.18, 0.52, 0.08, 0.52, 0x8c6235);
  b.box(0.62, 0.74, 0.25, 0.4, 0.42, 0.36, 0xd2a362);
  b.box(0.58, 1.17, -0.15, 0.36, 0.3, 0.36, 0xc99a58);
  for (let k = 0; k < 3; k++) b.box(-0.05, 0.64 + (k === 2 ? 0.2 : 0), -0.25 + (k === 2 ? 0.12 : k * 0.25), 0.3, 0.2, 0.22, 0x8a5a36);
  return finish(b, mat, len, [-0.65, 0.65], 0.2, { seat: new THREE.Vector3(-0.55, 0.53, 0) });
}

function buildCoach(mat, body = CREAM, band = RED, roof = TEAL, seed = 34) {
  const b = new BoxBuilder(seed);
  const len = 2.4;
  chassis(b, len);
  b.box(0, 0.62, 0, 2.3, 0.36, 1.0, band);
  b.box(0, 1.08, 0, 2.3, 0.58, 1.0, body);
  b.box(0, 0.82, 0, 2.32, 0.05, 1.02, BRASS);
  for (const sd of [-1, 1]) {
    for (let k = 0; k < 4; k++) {
      b.box(-0.78 + k * 0.52, 1.1, sd * 0.505, 0.32, 0.28, 0.02, GLASS, 0, 0, 0, 0);
    }
  }
  b.box(0, 1.42, 0, 2.46, 0.1, 1.14, roof);
  b.box(0, 1.52, 0, 2.3, 0.1, 0.86, shade(roof, 0.88));
  b.box(0, 1.6, 0, 2.1, 0.06, 0.5, roof);
  return finish(b, mat, len, [-0.75, 0.75], 0.2, { seat: new THREE.Vector3(0.2, 1.57, 0) });
}

// 运薰衣草的敞车
function buildFlowerWagon(mat) {
  const b = new BoxBuilder(36);
  const len = 2.2;
  chassis(b, len);
  b.box(0, 0.48, 0, 2.1, 0.1, 1.0, 0x8a6a9e);
  for (const sd of [-1, 1]) {
    b.box(0, 0.66, sd * 0.47, 2.1, 0.26, 0.08, 0x7a5cb0);
    b.box(0, 0.8, sd * 0.47, 2.14, 0.05, 0.1, CREAM);
    b.box(sd * 1.03, 0.66, 0, 0.08, 0.26, 1.0, 0x7a5cb0);
  }
  const lav = [0x9a7fd8, 0xa58ae0, 0x8c6fd0];
  for (let i = 0; i < 5; i++) for (let j = 0; j < 3; j++) {
    const x = -0.8 + i * 0.4, z = -0.3 + j * 0.3;
    b.box(x, 0.72 + ((i + j) % 2) * 0.06, z, 0.3, 0.2, 0.24, lav[(i + j) % 3], 0, 0, 0, 0.06);
    b.box(x, 0.86 + ((i + j) % 2) * 0.06, z, 0.08, 0.1, 0.08, 0xc2a8f0, 0, 0, 0, 0);
  }
  return finish(b, mat, len, [-0.65, 0.65], 0.2, { seat: new THREE.Vector3(0, 0.95, 0) });
}

// 油罐车
function buildTank(mat) {
  const b = new BoxBuilder(37);
  const len = 2.0;
  chassis(b, len);
  b.box(0, 0.48, 0, 1.9, 0.08, 0.9, DARK);
  for (const x of [-0.6, 0.6]) b.box(x, 0.56, 0, 0.1, 0.12, 0.8, DARK);
  b.box(0, 1.27, 0, 0.36, 0.16, 0.36, 0xd8d4c8);
  b.box(0, 1.37, 0, 0.26, 0.06, 0.26, DARK);
  for (const sd of [-1, 1]) b.box(0.3, 0.95, sd * 0.47, 0.04, 0.6, 0.04, DARK);
  const car = finish(b, mat, len, [-0.6, 0.6], 0.2, { seat: new THREE.Vector3(-0.3, 1.36, 0) });
  const tank = cyl(0.43, 1.8, 0xe9e4d6);
  tank.position.set(0, 0.93, 0);
  car.group.add(tank);
  for (const x of [-0.82, 0.82]) {
    const cap = cyl(0.41, 0.08, 0xcfc8b6);
    cap.position.set(x * 1.07, 0.93, 0);
    car.group.add(cap);
  }
  const band = cyl(0.44, 0.12, RED);
  band.position.set(0, 0.93, 0);
  car.group.add(band);
  return car;
}

// 原木平车
function buildLogCar(mat) {
  const b = new BoxBuilder(38);
  const len = 2.2;
  chassis(b, len);
  b.box(0, 0.48, 0, 2.1, 0.1, 1.0, 0x6b4a32);
  for (const x of [-0.95, -0.3, 0.3, 0.95]) for (const sd of [-1, 1]) b.box(x, 0.8, sd * 0.47, 0.07, 0.6, 0.07, DARK);
  const rows = [[-0.3, 0.0, 0.3], [-0.15, 0.15]];
  rows.forEach((row, k) => {
    for (const z of row) {
      b.box(0, 0.66 + k * 0.26, z, 2.0, 0.26, 0.26, 0x8a5a36, 0, 0, 0, 0.08);
      for (const sd of [-1, 1]) b.box(sd * 1.005, 0.66 + k * 0.26, z, 0.02, 0.22, 0.22, 0xdcb27a, 0, 0, 0, 0.04);
    }
  });
  return finish(b, mat, len, [-0.65, 0.65], 0.2, { seat: new THREE.Vector3(0.2, 1.05, 0) });
}

function buildCaboose(mat) {
  const b = new BoxBuilder(35);
  const len = 1.9;
  chassis(b, len);
  b.box(0.12, 0.88, 0, 1.4, 0.92, 1.0, RED);
  b.box(0.12, 0.62, 0, 1.42, 0.06, 1.02, BRASS);
  for (const sd of [-1, 1]) b.box(0.12, 1.06, sd * 0.505, 0.36, 0.3, 0.02, GLASS, 0, 0, 0, 0);
  b.box(0.12, 1.39, 0, 1.6, 0.1, 1.16, CREAM);
  b.box(0.2, 1.62, 0, 0.6, 0.36, 0.7, RED);
  b.box(0.2, 1.66, 0.355, 0.36, 0.18, 0.02, GLASS, 0, 0, 0, 0);
  b.box(0.2, 1.84, 0, 0.74, 0.08, 0.84, CREAM);
  // 后平台栏杆与尾灯
  b.box(-0.88, 0.75, 0, 0.05, 0.4, 0.95, DARK);
  b.box(-0.88, 1.0, 0, 0.12, 0.16, 0.16, 0xff5a4a, 0, 0, 0, 0);
  return finish(b, mat, len, [-0.5, 0.55], 0.2, { seat: new THREE.Vector3(0.2, 1.88, 0) });
}

export class Train {
  constructor(scene, path, world, mat) {
    this.path = path;
    this.world = world;
    this.cars = [
      buildLoco(mat),
      buildTender(mat),
      buildCoach(mat),
      buildCoach(mat, 0xe7dcf6, 0x7a5cb0, CREAM, 39),   // 薰衣草色客车
      buildWagon(mat),
      buildFlowerWagon(mat),
      buildTank(mat),
      buildLogCar(mat),
      buildCaboose(mat),
    ];
    const gap = 0.3;
    let off = 0;
    this.cars.forEach((c, i) => {
      if (i > 0) off += this.cars[i - 1].len / 2 + gap + c.len / 2;
      c.offset = off;
      c.s = 0;
      c.yaw = 0;
      c.visible = true;
      scene.add(c.group);
    });
    const last = this.cars[this.cars.length - 1];
    this.sStart = world.sPortalL - this.cars[0].len / 2 - 0.4;
    this.sEnd = world.sPortalR + last.offset + last.len / 2 + 0.6;
    this.length = last.offset + last.len / 2 + this.cars[0].len / 2;
    this.stops = [
      // 花田站：让最后一节车厢刚好钻出西山隧道
      { s: world.sPortalL + last.offset + last.len / 2 + 0.8, key: 'meadow', dwell: 7 },
      { s: path.sNear(32.3, 24.5), key: 'town', dwell: 6 },
      { s: path.sNear(108.6, 19.5), key: 'mountain', dwell: 8 },
    ];
    this.vmax = 3.6;
    this.accel = 1.0;
    this.brake = 1.2;
    this.next = 1;
    this.s = this.stops[1].s;
    this.v = 0;
    this.state = 'dwell';
    this.timer = 6;
    this.smokeT = 0;
    this._pf = {};
    this._pb = {};
    this.place(0);
  }

  update(dt, puffs) {
    if (this.state === 'dwell') {
      this.v = 0;
      this.timer -= dt;
      if (this.timer <= 0) { this.state = 'run'; this.next++; this.departing = 1.2; }
    } else if (this.state === 'run') {
      const stop = this.stops[this.next];
      let vT = this.vmax;
      if (stop) vT = Math.min(this.vmax, Math.max(0.35, Math.sqrt(2 * this.brake * Math.max(0, stop.s - this.s))));
      if (this.v < vT) this.v = Math.min(vT, this.v + this.accel * dt);
      else this.v = Math.max(vT, this.v - this.brake * 1.6 * dt);
      this.s += this.v * dt;
      if (stop && this.s >= stop.s) {
        this.s = stop.s; this.v = 0; this.state = 'dwell'; this.timer = stop.dwell;
      } else if (!stop && this.s >= this.sEnd) {
        this.state = 'tunnel'; this.timer = 4; this.v = 0;
      }
    } else if (this.state === 'tunnel') {
      this.timer -= dt;
      if (this.timer <= 0) { this.s = this.sStart; this.next = 0; this.state = 'run'; this.v = 1.6; }
    }
    if (this.departing) this.departing = Math.max(0, this.departing - dt);
    this.place(dt);

    // 冒烟
    const loco = this.cars[0];
    if (loco.visible && puffs) {
      this.smokeT -= dt;
      if (this.smokeT <= 0) {
        const moving = this.state === 'run';
        this.smokeT = moving ? 0.1 + 0.22 * (1 - this.v / this.vmax) : (this.departing ? 0.08 : 0.6);
        const p = loco.group.localToWorld(loco.chimney.clone());
        const big = this.departing ? 1.5 : 1;
        puffs.emit(p.x, p.y, p.z, {
          size: (0.42 + Math.random() * 0.2) * big,
          life: 1.6 + Math.random() * 0.8,
          vx: -loco.fx * this.v * 0.25 + 0.25, vy: 1.4 + Math.random() * 0.6, vz: -loco.fz * this.v * 0.25,
          gray: 0.84 + Math.random() * 0.12,
        });
      }
    }
  }

  place(dt) {
    const { path, world } = this;
    const pf = this._pf, pb = this._pb;
    for (const c of this.cars) {
      const sc = this.s - c.offset;
      c.s = sc;
      const half = c.len * 0.34;
      path.at(sc + half, pf);
      path.at(sc - half, pb);
      const dx = pf.x - pb.x, dz = pf.z - pb.z, dy = pf.y - pb.y;
      const hl = Math.hypot(dx, dz) || 1e-6;
      c.yaw = Math.atan2(-dz, dx);
      c.fx = dx / hl; c.fz = dz / hl;
      c.group.position.set((pf.x + pb.x) / 2, (pf.y + pb.y) / 2 + 0.27, (pf.z + pb.z) / 2);
      c.group.rotation.set(0, c.yaw, Math.atan2(dy, hl));
      c.visible = this.state !== 'tunnel' && sc > world.sPortalL - c.len / 2 && sc < world.sPortalR + c.len / 2;
      c.group.visible = c.visible;
      for (const w of c.wheels) w.rotation.z -= (this.v * dt) / c.r;
      c.group.updateMatrixWorld();
    }
  }

  get loco() { return this.cars[0]; }

  // 估算还要多少秒列车会停靠在某站（只是个大概）
  etaTo(key) {
    const idx = this.stops.findIndex((st) => st.key === key);
    const target = this.stops[idx].s;
    if (this.state === 'dwell' && this.next === idx) return 0;
    const avg = this.vmax * 0.78;
    let t = 0, s = this.s;
    if (this.state === 'dwell') t += this.timer;
    if (this.state === 'tunnel') { t += this.timer; s = this.sStart; }
    else if (s > target - 0.01) { t += (this.sEnd - s) / avg + 4; s = this.sStart; }
    for (const st of this.stops) if (st.s > s + 0.5 && st.s < target - 0.01) t += st.dwell;
    t += (target - s) / avg;
    return Math.max(1, Math.round(t));
  }

  status() {
    if (this.state === 'dwell') return { kind: 'dwell', at: this.stops[this.next].key, t: Math.max(1, Math.ceil(this.timer)) };
    if (this.state === 'tunnel') return { kind: 'tunnel' };
    if (this.s < this.world.sPortalL + 1) return { kind: 'emerge' };
    const stop = this.stops[this.next];
    return { kind: 'run', to: stop ? stop.key : 'tunnel' };
  }
}
