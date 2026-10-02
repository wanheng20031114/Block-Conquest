// 场景道具：房屋、教堂、城堡、风车、车站、树木、岩石……全部用小方块拼出来
import * as THREE from 'three';
import { X0, X1, D, GROUND, MAT, ZONE, STATION_NAMES, NPC_SPOT } from './config.js';
import { mulberry32, fbm2 } from './noise.js';
import { BoxBuilder } from './builder.js';

export const C = {
  found: 0x9d958a, stone: 0xc2bbae, stoneDark: 0x9f978b, stoneLight: 0xd9d2c4,
  plaster: [0xf6ebd3, 0xf3e0c0, 0xf4e3ac, 0xece7de, 0xf3dac6],
  timber: 0x704b31, timberDark: 0x58392a, door: 0x82502d, glass: 0x506d92, glow: 0xffd47e,
  roofs: [0xd6683f, 0xbd4a3b, 0x5f7bab, 0xcfa75b, 0x4f9c88],
  shutters: [0x4f9c88, 0x5f7bab, 0xc9483b, 0x6cab52, 0xe0a33c],
  bark: 0x7a5236, wood: 0xa8743f, woodLight: 0xc4925a, metal: 0x4a4752, gold: 0xf0c34e,
  leaf: [0x5faf3e, 0x4fa040, 0x6dbb46, 0x58a83b], autumn: [0xe5a93a, 0xdb7a33, 0xe8c24a],
  pine: [0x2f8a55, 0x37985c, 0x2a7e4f], flower: [0xff7aa8, 0xffd84a, 0xffffff, 0xb48cf0, 0xff6b5a, 0x7cc6ff],
  snow: 0xf6f9ff, red: 0xc94a3c, cream: 0xf3e6c8, teal: 0x3f8f86, hay: 0xe4c56a,
};

export function shade(hex, f) {
  const r = Math.min(255, Math.round(((hex >> 16) & 255) * f));
  const g = Math.min(255, Math.round(((hex >> 8) & 255) * f));
  const b = Math.min(255, Math.round((hex & 255) * f));
  return (r << 16) | (g << 8) | b;
}
const pick = (rnd, arr) => arr[Math.floor(rnd() * arr.length)];

// 在墙面上摆放东西的小工具：side = '+z' | '-z' | '+x' | '-x'
function wall(b, side, x0, z0, w, d) {
  const alongX = side[1] === 'z';
  const sign = side[0] === '+' ? 1 : -1;
  const L = alongX ? w : d;
  const face = alongX ? (sign > 0 ? z0 + d : z0) : (sign > 0 ? x0 + w : x0);
  const a0 = alongX ? x0 : z0;
  return {
    L,
    put(along, y, out, sa, sy, so, col, j = 0.04, rot = 0) {
      const c = face + out * sign;
      if (alongX) b.box(a0 + along, y + sy / 2, c, sa, sy, so, col, 0, rot, 0, j);
      else b.box(c, y + sy / 2, a0 + along, so, sy, sa, col, 0, 0, rot, j);
    },
  };
}

function windowAt(wl, along, y, shutter, rnd, flowers = true) {
  const glow = rnd() < 0.22;
  wl.put(along, y - 0.05, 0.015, 0.52, 0.56, 0.05, C.timber);
  wl.put(along, y, 0.04, 0.36, 0.44, 0.04, glow ? C.glow : C.glass, 0.03);
  wl.put(along, y + 0.2, 0.06, 0.04, 0.04, 0.02, C.timberDark); // 窗棂
  if (shutter) {
    wl.put(along - 0.29, y - 0.02, 0.05, 0.14, 0.48, 0.05, shutter);
    wl.put(along + 0.29, y - 0.02, 0.05, 0.14, 0.48, 0.05, shutter);
  }
  if (flowers && rnd() < 0.5) {
    wl.put(along, y - 0.16, 0.09, 0.5, 0.1, 0.14, C.wood);
    for (let k = -1; k <= 1; k++) wl.put(along + k * 0.15, y - 0.07, 0.09, 0.09, 0.09, 0.09, pick(rnd, C.flower), 0.02);
  }
}

function framing(b, x0, y, z0, w, hgt, d, braces) {
  for (const side of ['+z', '-z', '+x', '-x']) {
    const wl = wall(b, side, x0, z0, w, d);
    const n = Math.max(1, Math.round(wl.L / 1.0));
    for (let k = 0; k <= n; k++) {
      const a = Math.min(wl.L - 0.06, Math.max(0.06, (k / n) * wl.L));
      wl.put(a, y, 0.02, 0.12, hgt, 0.05, C.timber, 0.05);
    }
    wl.put(wl.L / 2, y + hgt - 0.1, 0.02, wl.L, 0.1, 0.05, C.timber);
    wl.put(wl.L / 2, y, 0.02, wl.L, 0.08, 0.05, C.timber);
    if (braces && n >= 2) {
      const seg = wl.L / n;
      const len = Math.hypot(seg, hgt) * 0.92;
      const ang = Math.atan2(hgt, seg);
      wl.put(seg / 2, y + hgt / 2 - len / 2, 0.025, 0.09, len, 0.04, C.timber, 0.04, Math.PI / 2 - ang);
      wl.put(wl.L - seg / 2, y + hgt / 2 - len / 2, 0.025, 0.09, len, 0.04, C.timber, 0.04, -(Math.PI / 2 - ang));
    }
  }
}

// 阶梯状的人字屋顶
function roof(b, x0, z0, w, d, y, col, axis, o = {}) {
  const over = o.over ?? 0.22, step = o.step ?? 0.27, lh = o.lh ?? 0.25;
  const dark = shade(col, 0.86);
  let k = 0;
  if (axis === 'x') {
    const zc = z0 + d / 2;
    let half = d / 2 + over;
    while (half > 0.1) {
      b.cube(x0 - over, y, zc - half, w + 2 * over, lh, 2 * half, k % 2 ? dark : col, 0.03);
      y += lh; half -= step; k++;
    }
    b.cube(x0 - over - 0.05, y, zc - 0.13, w + 2 * over + 0.1, 0.1, 0.26, shade(col, 0.75));
  } else {
    const xc = x0 + w / 2;
    let half = w / 2 + over;
    while (half > 0.1) {
      b.cube(xc - half, y, z0 - over, 2 * half, lh, d + 2 * over, k % 2 ? dark : col, 0.03);
      y += lh; half -= step; k++;
    }
    b.cube(xc - 0.13, y, z0 - over - 0.05, 0.26, 0.1, d + 2 * over + 0.1, shade(col, 0.75));
  }
  return y + 0.1;
}

function house(ctx, x0, z0, w, d, o = {}) {
  const { b, world, rnd, dyn } = ctx;
  const g = world.hAt(x0 + w / 2, z0 + d / 2);
  world.block(x0, z0, w, d);
  b.setGround(g);
  const floors = o.floors ?? 1;
  const wallCol = o.wall ?? pick(rnd, C.plaster);
  const roofCol = o.roof ?? pick(rnd, C.roofs);
  const shut = o.shutter ?? pick(rnd, C.shutters);
  const doorSide = o.door ?? '+z';
  const axis = o.axis ?? (w >= d ? 'x' : 'z');

  b.cube(x0 + 0.06, g, z0 + 0.06, w - 0.12, 0.3, d - 0.12, C.found, 0.08);
  let y = g + 0.3;
  const ix = x0 + 0.16, iz = z0 + 0.16, iw = w - 0.32, id = d - 0.32;
  const f1 = 1.3;
  const lower = floors === 2 ? (o.wall1 ?? C.stone) : wallCol;
  b.cube(ix, y, iz, iw, f1, id, lower, 0.03);
  if (floors === 1) framing(b, ix, y, iz, iw, f1, id, false);
  else {
    // 石砌底层：随机凸出的石块
    for (let k = 0; k < 10; k++) {
      const side = pick(rnd, ['+z', '-z', '+x', '-x']);
      const wl = wall(b, side, ix, iz, iw, id);
      wl.put(0.3 + rnd() * (wl.L - 0.6), y + rnd() * (f1 - 0.3), 0.01, 0.3, 0.18, 0.04, shade(C.stone, 0.9));
    }
  }
  // 门与窗
  for (const side of ['+z', '-z', '+x', '-x']) {
    const wl = wall(b, side, ix, iz, iw, id);
    const doorPos = side === doorSide ? wl.L * (o.doorAt ?? 0.5) : -9;
    if (o.sign && side === '+z') {
      wl.put(wl.L / 2, y + 0.42, 0.02, 2.5, 0.72, 0.06, C.timberDark);
      const sm = signMesh(o.sign, 2.3, 0.56, o.signBg);
      sm.position.set(ix + iw / 2, y + 0.78, iz + id + 0.056);
      dyn.group.add(sm);
      for (const a of [0.45, wl.L - 0.45]) windowAt(wl, a, y + 0.55, shut, rnd, false);
      continue;
    }
    if (side === doorSide) {
      wl.put(doorPos, y - 0.02, 0.01, 0.74, 1.04, 0.05, C.timberDark);
      wl.put(doorPos, y, 0.04, 0.58, 0.94, 0.04, C.door);
      wl.put(doorPos + 0.18, y + 0.45, 0.07, 0.06, 0.06, 0.03, C.gold);
      wl.put(doorPos, y - 0.3, 0.2, 0.9, 0.3, 0.36, C.found);
    }
    const n = Math.floor(wl.L / 1.05);
    for (let k = 0; k < n; k++) {
      const a = ((k + 0.5) / n) * wl.L;
      if (Math.abs(a - doorPos) < 0.75) continue;
      if (floors === 2 || rnd() < 0.85) windowAt(wl, a, y + 0.55, floors === 1 ? shut : null, rnd, floors === 1);
    }
  }
  y += f1;
  if (floors === 2) {
    b.cube(x0 + 0.06, y, z0 + 0.06, w - 0.12, 0.12, d - 0.12, C.timber);
    y += 0.12;
    const ux = x0 + 0.08, uz = z0 + 0.08, uw = w - 0.16, ud = d - 0.16, f2 = 1.15;
    b.cube(ux, y, uz, uw, f2, ud, wallCol, 0.03);
    framing(b, ux, y, uz, uw, f2, ud, true);
    for (const side of ['+z', '-z', '+x', '-x']) {
      const wl = wall(b, side, ux, uz, uw, ud);
      const n = Math.max(1, Math.floor(wl.L / 1.4));
      for (let k = 0; k < n; k++) windowAt(wl, ((k + 0.5) / n) * wl.L, y + 0.45, shut, rnd, true);
    }
    y += f2;
  }
  b.cube(x0 + 0.04, y, z0 + 0.04, w - 0.08, 0.1, d - 0.08, C.timber);
  y += 0.1;
  const ridge = roof(b, x0, z0, w, d, y, roofCol, axis);
  if (o.chimney !== false) {
    const cx = axis === 'x' ? x0 + w * 0.72 : x0 + w / 2 + 0.35;
    const cz = axis === 'x' ? z0 + d / 2 + 0.35 : z0 + d * 0.72;
    const top = ridge + 0.35;
    b.box(cx, (y + top) / 2, cz, 0.42, top - y, 0.42, 0xa1958b, 0, 0, 0, 0.06);
    b.box(cx, top + 0.06, cz, 0.54, 0.12, 0.54, 0x7e746c);
    dyn.chimneys.push(new THREE.Vector3(cx, top + 0.2, cz));
  }
  return { g, top: ridge };
}

function church(ctx, x0, z0) {
  const { b, world, dyn } = ctx;
  const g = GROUND;
  const w = 5, d = 8;
  world.block(x0, z0, w, d + 3);
  b.setGround(g);
  const sc = 0xdcd4c4;
  b.cube(x0 + 0.05, g, z0 + 0.05, w - 0.1, 0.35, d - 0.1, C.found);
  const ix = x0 + 0.2, iz = z0 + 0.2, iw = w - 0.4, id = d - 0.4, wh = 2.7;
  b.cube(ix, g + 0.35, iz, iw, wh, id, sc, 0.03);
  for (const side of ['+x', '-x']) {
    const wl = wall(b, side, ix, iz, iw, id);
    for (let k = 0; k < 4; k++) {
      const a = 0.9 + k * 1.95;
      wl.put(a, g + 0.9, 0.03, 0.42, 1.25, 0.05, C.timberDark);
      wl.put(a, g + 0.95, 0.05, 0.3, 1.1, 0.04, 0x6b8cc4);
      wl.put(a, g + 1.6, 0.06, 0.06, 0.4, 0.02, 0xe8c45a);
      if (k < 3) wl.put(a + 0.98, g, 0.15, 0.3, 2.3, 0.3, C.stoneDark); // 扶壁
    }
  }
  roof(b, x0, z0, w, d, g + 0.35 + wh, 0x6d7ca3, 'z', { step: 0.26, lh: 0.27, over: 0.25 });
  // 钟楼
  const tx = x0 + 1, tz = z0 + d, tw = 3, th = 5.6;
  b.cube(tx, g, tz, tw, 0.4, tw, C.found);
  b.cube(tx + 0.1, g + 0.4, tz + 0.1, tw - 0.2, th, tw - 0.2, sc, 0.03);
  for (const [qx, qz] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
    for (let k = 0; k < 7; k++) {
      b.cube(tx + qx * (tw - 0.34) + 0.02, g + 0.5 + k * 0.78, tz + qz * (tw - 0.34) + 0.02, 0.32, 0.38, 0.32, C.stoneDark);
    }
  }
  for (const side of ['+z', '-z', '+x', '-x']) {
    const wl = wall(b, side, tx + 0.1, tz + 0.1, tw - 0.2, tw - 0.2);
    wl.put(wl.L / 2, g + th - 1.25, 0.02, 0.8, 1.0, 0.05, 0x3a3444);
    wl.put(wl.L / 2, g + th - 0.95, 0.06, 0.35, 0.4, 0.06, C.gold); // 钟
    if (side === '+z') {
      wl.put(wl.L / 2, g + 0.4, 0.03, 1.0, 1.55, 0.05, C.timberDark);
      wl.put(wl.L / 2, g + 0.4, 0.06, 0.8, 1.42, 0.04, 0x7a4528);
      wl.put(wl.L / 2, g + 2.6, 0.03, 0.85, 0.85, 0.05, 0xf8f4ea); // 钟面
      wl.put(wl.L / 2, g + 3.02, 0.07, 0.06, 0.32, 0.02, 0x2d2a33);
      wl.put(wl.L / 2 + 0.12, g + 3.0, 0.07, 0.26, 0.06, 0.02, 0x2d2a33);
      wl.put(wl.L / 2, g + 3.85, 0.03, 0.5, 0.5, 0.05, 0xd04f6a); // 玫瑰窗
      wl.put(wl.L / 2, g + 3.95, 0.06, 0.28, 0.3, 0.04, 0x6b8cc4);
    }
  }
  // 塔顶城垛 + 尖顶
  let y = g + 0.4 + th;
  b.cube(tx - 0.05, y, tz - 0.05, tw + 0.1, 0.18, tw + 0.1, C.stoneDark);
  y += 0.18;
  let half = tw / 2 - 0.1, k = 0;
  const cx = tx + tw / 2, cz = tz + tw / 2;
  while (half > 0.08) {
    b.cube(cx - half, y, cz - half, half * 2, 0.3, half * 2, k % 2 ? 0x6b7aa2 : 0x7f8db3, 0.03);
    y += 0.3; half -= 0.22; k++;
  }
  b.box(cx, y + 0.35, cz, 0.06, 0.7, 0.06, C.gold);
  b.box(cx, y + 0.72, cz, 0.18, 0.18, 0.18, C.gold);
  // 小旗
  addFlag(ctx, cx, y + 0.5, cz, 0x5f7bab, 0xf0c34e, 0.42);
}

function addFlag(ctx, x, y, z, col, stripe, size = 0.6) {
  const fb = new BoxBuilder(5);
  fb.box(size / 2, 0, 0, size, size * 0.62, 0.04, col, 0, 0, 0, 0);
  fb.box(size / 2, 0, 0.005, size, size * 0.14, 0.045, stripe, 0, 0, 0, 0);
  const m = fb.mesh(ctx.mat, { cast: true, receive: false });
  const grp = new THREE.Group();
  grp.position.set(x, y, z);
  grp.add(m);
  ctx.dyn.flags.push({ grp, phase: Math.random() * 6 });
  ctx.dyn.group.add(grp);
}

function castle(ctx) {
  const { b, world } = ctx;
  const g = 13;
  b.setGround(g);
  const x0 = 1, x1 = 8, z0 = 9, z1 = 20;
  const sc = 0xbcb6ab, wh = 2.2, t = 0.6;
  const merlons = (ax, az, bx, bz, y) => {
    const len = Math.hypot(bx - ax, bz - az);
    const n = Math.floor(len / 0.75);
    for (let k = 0; k <= n; k++) {
      const f = k / n;
      b.box(ax + (bx - ax) * f, y + 0.22, az + (bz - az) * f, 0.38, 0.44, 0.38, shade(sc, 0.96));
    }
  };
  // 城墙
  b.cube(x0, g, z0, x1 - x0, wh, t, sc, 0.04);
  b.cube(x0, g, z1 - t, x1 - x0, wh, t, sc, 0.04);
  b.cube(x0, g, z0, t, wh, z1 - z0, sc, 0.04);
  b.cube(x1 - t, g, z0, t, wh, 4.6, sc, 0.04);
  b.cube(x1 - t, g, z0 + 6.4, t, wh, z1 - z0 - 6.4, sc, 0.04);
  b.cube(x1 - t, g + 1.7, z0 + 4.6, t, 0.5, 1.8, sc); // 城门上方
  merlons(x0 + 0.2, z0 + 0.2, x1 - 0.2, z0 + 0.2, g + wh);
  merlons(x0 + 0.2, z1 - 0.2, x1 - 0.2, z1 - 0.2, g + wh);
  merlons(x0 + 0.2, z0 + 0.2, x0 + 0.2, z1 - 0.2, g + wh);
  merlons(x1 - 0.2, z0 + 0.2, x1 - 0.2, z1 - 0.2, g + wh);
  // 城门
  b.cube(x1 - 0.05, g, z0 + 4.65, 0.12, 1.65, 1.7, 0x2f2a33);
  for (let k = 0; k < 4; k++) b.cube(x1 + 0.05, g + 0.15, z0 + 4.8 + k * 0.42, 0.05, 1.5, 0.06, C.metal);
  // 墙体石块纹理
  for (let k = 0; k < 60; k++) {
    const side = k % 4;
    const y = g + 0.2 + ctx.rnd() * (wh - 0.5);
    if (side === 0) b.cube(x0 + 0.3 + ctx.rnd() * (x1 - x0 - 0.9), y, z1 - 0.04, 0.42, 0.22, 0.06, shade(sc, 0.9));
    else if (side === 1) b.cube(x1 - 0.04, y, z0 + 0.3 + ctx.rnd() * (z1 - z0 - 0.9), 0.06, 0.22, 0.42, shade(sc, 0.9));
    else if (side === 2) b.cube(x0 + 0.3 + ctx.rnd() * (x1 - x0 - 0.9), y, z0 - 0.02, 0.42, 0.22, 0.06, shade(sc, 0.9));
    else b.cube(x0 - 0.02, y, z0 + 0.3 + ctx.rnd() * (z1 - z0 - 0.9), 0.06, 0.22, 0.42, shade(sc, 0.92));
  }
  // 角楼
  for (const [cx, cz] of [[x0, z0], [x1, z0], [x0, z1], [x1, z1]]) {
    const s = 1.8, th = 3.6;
    b.cube(cx - s / 2, g, cz - s / 2, s, th, s, shade(sc, 1.04), 0.04);
    b.cube(cx - s / 2 - 0.1, g + th, cz - s / 2 - 0.1, s + 0.2, 0.2, s + 0.2, C.stoneDark);
    let y = g + th + 0.2, half = s / 2 + 0.15, k = 0;
    while (half > 0.08) {
      b.cube(cx - half, y, cz - half, half * 2, 0.3, half * 2, k % 2 ? 0xa83f34 : 0xc94a3c, 0.03);
      y += 0.3; half -= 0.18; k++;
    }
    for (const sd of [-1, 1]) b.cube(cx - 0.05, g + 1.6, cz + sd * (s / 2) - 0.03, 0.1, 0.5, 0.06, 0x2f2a33);
  }
  // 主楼
  const kx = 2.4, kz = 10.6, kw = 3.4, kd = 3.6, kh = 5.2;
  b.cube(kx, g, kz, kw, kh, kd, shade(sc, 1.06), 0.04);
  merlons(kx + 0.15, kz + 0.15, kx + kw - 0.15, kz + 0.15, g + kh);
  merlons(kx + 0.15, kz + kd - 0.15, kx + kw - 0.15, kz + kd - 0.15, g + kh);
  merlons(kx + 0.15, kz + 0.15, kx + 0.15, kz + kd - 0.15, g + kh);
  merlons(kx + kw - 0.15, kz + 0.15, kx + kw - 0.15, kz + kd - 0.15, g + kh);
  for (let k = 0; k < 3; k++) {
    b.cube(kx + 0.6 + k * 1.0, g + 3.2, kz + kd - 0.02, 0.24, 0.6, 0.06, 0x3a3444);
    b.cube(kx + kw - 0.02, g + 3.2, kz + 0.7 + k * 1.0, 0.06, 0.6, 0.24, 0x3a3444);
  }
  b.cube(kx + kw - 0.02, g, kz + 1.3, 0.08, 1.2, 0.9, C.door);
  // 主楼上的小塔
  const sx = kx + 0.4, sz = kz + 0.4;
  b.cube(sx, g + kh, sz, 1.4, 1.4, 1.4, shade(sc, 1.08));
  let y = g + kh + 1.4, half = 0.85, k = 0;
  while (half > 0.08) {
    b.cube(sx + 0.7 - half, y, sz + 0.7 - half, half * 2, 0.3, half * 2, k % 2 ? 0xa83f34 : 0xc94a3c, 0.03);
    y += 0.3; half -= 0.17; k++;
  }
  b.box(sx + 0.7, y + 0.5, sz + 0.7, 0.06, 1.0, 0.06, C.metal);
  addFlag(ctx, sx + 0.7, y + 0.82, sz + 0.7, 0xc94a3c, 0xf0c34e, 0.7);
  for (const [cx, cz] of [[x1, z0], [x0, z1]]) {
    b.box(cx, g + 5.9, cz, 0.05, 1.0, 0.05, C.metal);
    addFlag(ctx, cx, g + 6.2, cz, 0x5f7bab, 0xf6f0e0, 0.55);
  }
  // 院子
  b.cube(5.6, g, 16.6, 0.8, 0.6, 0.6, C.hay);
  b.cube(6.5, g, 16.8, 0.45, 0.6, 0.45, C.wood);
  // 碰撞：只挡墙和主楼，院子可走
  for (let x = x0; x < x1; x++) { world.block(x, z0, 1, 1); world.block(x, z1 - 1, 1, 1); }
  for (let z = z0; z < z1; z++) { world.block(x0, z, 1, 1); if (z < z0 + 4 || z > z0 + 6) world.block(x1 - 1, z, 1, 1); }
  world.block(x1, z0 - 1, 1, 2); world.block(x1, z1 - 1, 1, 2);
  world.block(2, 10, 4, 4);
}

function windmill(ctx, x0, z0) {
  const { b, world, dyn } = ctx;
  const g = world.hAt(x0 + 1.5, z0 + 1.5);
  world.block(x0, z0, 3, 3);
  b.setGround(g);
  const cx = x0 + 1.5, cz = z0 + 1.5;
  b.cube(x0 + 0.1, g, z0 + 0.1, 2.8, 0.5, 2.8, C.found);
  let y = g + 0.5;
  const sizes = [2.5, 2.3, 2.1, 1.9, 1.7];
  sizes.forEach((s, k) => {
    b.cube(cx - s / 2, y, cz - s / 2, s, 0.9, s, k % 2 ? 0xf2e6cc : 0xefe0c2, 0.02);
    b.cube(cx - s / 2 - 0.02, y, cz - s / 2 - 0.02, s + 0.04, 0.08, s + 0.04, C.timber);
    y += 0.9;
  });
  b.cube(cx - 0.32, g + 0.5, cz + 1.22, 0.64, 1.0, 0.08, C.door);
  b.cube(cx - 0.2, g + 2.4, cz + 1.07, 0.4, 0.45, 0.06, C.glass);
  b.cube(cx + 1.12, g + 1.6, cz - 0.2, 0.06, 0.45, 0.4, C.glass);
  // 帽顶
  let half = 1.15, k = 0;
  while (half > 0.1) {
    b.cube(cx - half, y, cz - half, half * 2, 0.26, half * 2, k % 2 ? 0x7c5136 : 0x8d5d3d, 0.03);
    y += 0.26; half -= 0.2; k++;
  }
  // 风车叶片（可旋转）
  const hubY = g + 4.3, hubZ = cz + 1.25;
  b.box(cx, hubY, hubZ - 0.2, 0.3, 0.3, 0.5, C.timberDark);
  const bb = new BoxBuilder(9);
  bb.box(0, 0, 0, 0.32, 0.32, 0.2, C.timberDark, 0, 0, 0, 0);
  for (let i = 0; i < 4; i++) {
    const a = (i * Math.PI) / 2;
    const ca = Math.cos(a), sa = Math.sin(a);
    const L = 2.5;
    // 叶臂
    bb.box(ca * L / 2, sa * L / 2, 0, i % 2 ? 0.12 : L, i % 2 ? L : 0.12, 0.1, C.timber, 0, 0, 0, 0);
    // 帆布
    const off = 0.28;
    const px = ca * (L * 0.58) - sa * off, py = sa * (L * 0.58) + ca * off;
    bb.box(px, py, 0.02, i % 2 ? 0.46 : 1.6, i % 2 ? 1.6 : 0.46, 0.04, 0xf4ecd8, 0, 0, 0, 0);
    for (let s = 0; s < 4; s++) {
      const t = 0.3 + s * 0.17;
      bb.box(ca * L * t - sa * off, sa * L * t + ca * off, 0.05, i % 2 ? 0.48 : 0.05, i % 2 ? 0.05 : 0.48, 0.03, C.timber, 0, 0, 0, 0);
    }
  }
  const blades = bb.mesh(ctx.mat, { cast: true, receive: false });
  blades.position.set(cx, hubY, hubZ + 0.1);
  dyn.group.add(blades);
  dyn.blades.push(blades);
}

// —— 小物件 ——
function lamp(b, x, z, g) {
  b.setGround(g);
  b.box(x, g + 0.08, z, 0.26, 0.16, 0.26, C.metal);
  b.box(x, g + 0.8, z, 0.09, 1.5, 0.09, C.metal);
  b.box(x, g + 1.62, z, 0.3, 0.06, 0.3, C.metal);
  b.box(x, g + 1.45, z, 0.22, 0.28, 0.22, C.glow, 0, 0, 0, 0);
  b.box(x, g + 1.66, z, 0.12, 0.08, 0.12, C.metal);
}
function barrel(b, x, z, g) {
  b.setGround(g);
  b.box(x, g + 0.3, z, 0.44, 0.6, 0.44, 0x8e5c35);
  b.box(x, g + 0.14, z, 0.47, 0.05, 0.47, 0x4f3d2e);
  b.box(x, g + 0.46, z, 0.47, 0.05, 0.47, 0x4f3d2e);
}
function crate(b, x, z, g, s = 0.5) {
  b.setGround(g);
  b.box(x, g + s / 2, z, s, s, s, 0xc0904f);
  b.box(x, g + s / 2, z, s + 0.02, s * 0.16, s + 0.02, 0x8c6235);
}
function hay(b, x, z, g, rot = 0) {
  b.setGround(g);
  b.box(x, g + 0.3, z, 0.85, 0.6, 0.6, C.hay, rot);
  b.box(x, g + 0.3, z, 0.12, 0.62, 0.62, 0xc9a34a, rot);
}
function bush(b, x, z, g, rnd) {
  b.setGround(g);
  const col = pick(rnd, C.leaf);
  b.box(x, g + 0.22, z, 0.55, 0.44, 0.5, col);
  b.box(x + 0.18, g + 0.36, z - 0.05, 0.36, 0.36, 0.36, shade(col, 1.1));
  if (rnd() < 0.4) b.box(x - 0.1, g + 0.46, z + 0.18, 0.09, 0.09, 0.09, pick(rnd, [0xff6b5a, 0xffd84a, 0xff7aa8]));
}
function flowers(b, x, z, g, rnd) {
  const col = pick(rnd, C.flower);
  for (let k = 0; k < 3; k++) {
    const fx = x + (rnd() - 0.5) * 0.6, fz = z + (rnd() - 0.5) * 0.6;
    b.box(fx, g + 0.09, fz, 0.04, 0.18, 0.04, 0x5c9e3c, 0, 0, 0, 0);
    b.box(fx, g + 0.21, fz, 0.1, 0.08, 0.1, col, 0, 0, 0, 0.02);
  }
}
function tuft(b, x, z, g, rnd, col) {
  for (let k = 0; k < 3; k++) {
    b.box(x + (rnd() - 0.5) * 0.3, g + 0.1, z + (rnd() - 0.5) * 0.3, 0.06, 0.2 + rnd() * 0.1, 0.06, col, 0, 0, 0, 0.08);
  }
}
function mushroom(b, x, z, g, rnd) {
  const s = 0.7 + rnd() * 0.6;
  b.box(x, g + 0.08 * s, z, 0.08 * s, 0.16 * s, 0.08 * s, 0xf3ead8, 0, 0, 0, 0);
  b.box(x, g + 0.2 * s, z, 0.24 * s, 0.1 * s, 0.24 * s, 0xd9483b, 0, 0, 0, 0.03);
  b.box(x + 0.05 * s, g + 0.255 * s, z, 0.05 * s, 0.02, 0.05 * s, 0xffffff, 0, 0, 0, 0);
}
function fence(b, ax, az, bx, bz, g) {
  const len = Math.hypot(bx - ax, bz - az);
  const n = Math.max(1, Math.round(len));
  const alongX = Math.abs(bx - ax) > Math.abs(bz - az);
  for (let k = 0; k <= n; k++) {
    const f = k / n;
    b.box(ax + (bx - ax) * f, g + 0.3, az + (bz - az) * f, 0.12, 0.6, 0.12, C.wood);
  }
  const cx = (ax + bx) / 2, cz = (az + bz) / 2;
  for (const hy of [0.24, 0.46]) {
    b.box(cx, g + hy, cz, alongX ? len : 0.06, 0.07, alongX ? 0.06 : len, C.woodLight);
  }
}
function wheat(b, x0, z0, g, rnd) {
  for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) {
    const x = x0 + 0.2 + i * 0.3 + (rnd() - 0.5) * 0.08, z = z0 + 0.2 + j * 0.3 + (rnd() - 0.5) * 0.08;
    const h = 0.45 + rnd() * 0.15;
    b.box(x, g + h / 2, z, 0.08, h, 0.08, 0xd9b54a, 0, 0, 0, 0.06);
    b.box(x, g + h + 0.07, z, 0.11, 0.16, 0.11, 0xf0d26e, 0, 0, 0, 0.05);
  }
}

// —— 树 ——
export function roundTree(b, cx, cz, g, sc, leaf, rnd, apples = false) {
  b.setGround(g);
  const th = 0.65 * sc + 0.2;
  b.box(cx, g + th / 2, cz, 0.24 * sc, th, 0.24 * sc, C.bark, 0, 0, 0, 0.08);
  const s = 1.15 * sc;
  const y0 = g + th;
  b.box(cx, y0 + s * 0.45, cz, s, s * 0.9, s, leaf, 0, 0, 0, 0.06);
  const s2 = s * 0.66;
  b.box(cx + (rnd() - 0.5) * 0.2, y0 + s * 0.9 + s2 * 0.3, cz + (rnd() - 0.5) * 0.2, s2, s2 * 0.62, s2, shade(leaf, 1.08), 0, 0, 0, 0.05);
  for (let k = 0; k < 2; k++) {
    const s3 = s * 0.46;
    const ox = (k ? 1 : -1) * s * 0.42, oz = (rnd() - 0.5) * s * 0.5;
    b.box(cx + ox, y0 + s * 0.3 + rnd() * 0.2, cz + oz, s3, s3 * 0.8, s3, shade(leaf, 0.93), 0, 0, 0, 0.05);
  }
  if (apples) {
    for (let k = 0; k < 5; k++) {
      const side = Math.floor(rnd() * 3);
      const px = side === 0 ? cx + s / 2 + 0.02 : cx + (rnd() - 0.5) * s * 0.8;
      const pz = side === 1 ? cz + s / 2 + 0.02 : cz + (rnd() - 0.5) * s * 0.8;
      const py = side === 2 ? y0 + s * 0.9 + 0.02 : y0 + 0.2 + rnd() * s * 0.6;
      b.box(px, py, pz, 0.12, 0.12, 0.12, 0xe0453a, 0, 0, 0, 0.03);
    }
  }
}

export function pine(b, cx, cz, g, sc, snowy, rnd) {
  b.setGround(g);
  b.box(cx, g + 0.22 * sc, cz, 0.2 * sc, 0.45 * sc, 0.2 * sc, C.bark, 0, 0, 0, 0.08);
  let y = g + 0.4 * sc;
  const col = pick(rnd, C.pine);
  const sizes = [1.25, 0.98, 0.72, 0.46, 0.22];
  sizes.forEach((s0, k) => {
    const s = s0 * sc, lh = (k === 4 ? 0.3 : 0.42) * sc;
    b.box(cx, y + lh / 2, cz, s, lh, s, k % 2 ? shade(col, 1.12) : col, 0, 0, 0, 0.05);
    if (snowy) b.box(cx, y + lh + 0.03, cz, s - 0.1, 0.07, s - 0.1, C.snow, 0, 0, 0, 0.02);
    y += lh;
  });
}

function rock(b, cx, cz, g, sc, snowy, rnd) {
  b.setGround(g);
  const col = pick(rnd, [0xaaa7b6, 0x9e9bad, 0xb5b2c0]);
  b.box(cx, g + 0.25 * sc, cz, 0.84 * sc, 0.5 * sc, 0.72 * sc, col, 0, 0, 0, 0.06);
  b.box(cx - 0.1 * sc, g + 0.6 * sc, cz + 0.05 * sc, 0.5 * sc, 0.25 * sc, 0.45 * sc, shade(col, 1.07));
  b.box(cx + 0.36 * sc, g + 0.15 * sc, cz + 0.25 * sc, 0.4 * sc, 0.3 * sc, 0.4 * sc, shade(col, 0.9));
  if (snowy) b.box(cx - 0.1 * sc, g + 0.75 * sc, cz + 0.05 * sc, 0.46 * sc, 0.06, 0.42 * sc, C.snow);
}

// —— 文字招牌（像素字） ——
function signMesh(text, w, h, bg = '#2f5a4f', fg = '#fff4d6') {
  const scale = 96;
  const cv = document.createElement('canvas');
  cv.width = Math.round(w * scale);
  cv.height = Math.round(h * scale);
  const x = cv.getContext('2d');
  x.fillStyle = bg;
  x.fillRect(0, 0, cv.width, cv.height);
  x.strokeStyle = fg;
  x.lineWidth = 6;
  x.strokeRect(8, 8, cv.width - 16, cv.height - 16);
  x.fillStyle = fg;
  x.font = `bold ${Math.round(cv.height * 0.56)}px "PingFang SC","Hiragino Sans GB","Microsoft YaHei","Noto Sans CJK SC",sans-serif`;
  x.textAlign = 'center';
  x.textBaseline = 'middle';
  x.fillText(text, cv.width / 2, cv.height / 2 + 1);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.magFilter = THREE.LinearFilter;
  tex.anisotropy = 4;
  tex.minFilter = THREE.LinearFilter;
  const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshLambertMaterial({ map: tex }));
  return m;
}

function townStation(ctx) {
  const { b, world } = ctx;
  const g = GROUND;
  b.setGround(g);
  // 低矮的露天站台（在铁轨南侧，不挡住火车），长度够停下 9 节车厢
  const px0 = 12, len = 22, pz0 = 25.3, pd = 1.7;
  b.cube(px0, g, pz0, len, 0.42, pd, 0xc5bdaf, 0.03);
  for (let k = 0; k < len * 2; k++) {
    b.cube(px0 + k * 0.5 + 0.02, g + 0.42, pz0 + 0.24, 0.46, 0.05, pd - 0.3, k % 2 ? 0xb88a58 : 0xc4955f, 0.04);
  }
  b.cube(px0, g + 0.42, pz0, len, 0.06, 0.22, 0xeedc9c);
  world.setExtra(px0, 25, len, 2, g + 0.47);
  world.reserve(px0, 25, len, 4);
  for (const x of [15.5, 20.0, 25.5, 30.0]) {
    b.box(x, g + 0.47 + 0.3, pz0 + 1.2, 0.95, 0.08, 0.32, C.wood);
    b.box(x, g + 0.47 + 0.52, pz0 + 1.4, 0.95, 0.3, 0.06, C.wood);
    b.box(x - 0.38, g + 0.47 + 0.14, pz0 + 1.2, 0.08, 0.28, 0.28, C.metal);
    b.box(x + 0.38, g + 0.47 + 0.14, pz0 + 1.2, 0.08, 0.28, 0.28, C.metal);
  }
  crate(b, 32.7, 26.55, g + 0.47, 0.5);
  crate(b, 33.25, 26.7, g + 0.47, 0.4);
  barrel(b, 12.5, 26.6, g + 0.47);
  barrel(b, 22.6, 26.7, g + 0.47);
  for (const x of [12.4, 17.8, 23.2, 28.6, 33.6]) lamp(b, x, 25.75, g + 0.47);
  // 站房：朝向镜头的一面挂站名牌
  house(ctx, 17, 29, 7, 3, { wall: 0xf3e3c3, roof: 0xbd4a3b, door: '-z', floors: 1, shutter: C.teal, sign: STATION_NAMES.town, signBg: '#2f5a4f' });
  // 水塔（铁轨北侧）
  const wx = 30.0, wz = 21.9;
  world.block(29, 21, 2, 2);
  b.setGround(g);
  for (const [ox, oz] of [[-0.55, -0.55], [0.55, -0.55], [-0.55, 0.55], [0.55, 0.55]]) b.box(wx + ox, g + 1.0, wz + oz, 0.14, 2.0, 0.14, C.timberDark);
  b.box(wx, g + 1.0, wz + 0.55, 1.2, 0.08, 0.08, C.timber, 0, 0.8);
  b.box(wx, g + 2.6, wz, 1.5, 1.2, 1.5, 0x9c6a42);
  for (const hy of [2.2, 2.6, 3.0]) b.box(wx, g + hy, wz, 1.54, 0.07, 1.54, C.metal);
  let y = g + 3.2, half = 0.85, k = 0;
  while (half > 0.08) { b.cube(wx - half, y, wz - half, half * 2, 0.22, half * 2, k % 2 ? 0x4b8b80 : C.teal); y += 0.22; half -= 0.2; k++; }
  b.box(wx, g + 2.3, wz + 0.95, 0.14, 0.14, 0.6, C.metal);
  b.box(wx, g + 2.05, wz + 1.2, 0.12, 0.4, 0.12, C.metal);
  signal(b, 31.5, 22.6, g);
}

function signal(b, x, z, g) {
  b.setGround(g);
  b.box(x, g + 0.9, z, 0.1, 1.8, 0.1, C.metal);
  b.box(x, g + 1.75, z, 0.28, 0.5, 0.18, 0x2f2d36);
  b.box(x, g + 1.88, z + 0.1, 0.12, 0.12, 0.04, 0xff5a4a, 0, 0, 0, 0);
  b.box(x, g + 1.66, z + 0.1, 0.12, 0.12, 0.04, 0x6be08a, 0, 0, 0, 0);
}

function stall(ctx, x0, z0, awning) {
  const { b, world, rnd } = ctx;
  const g = GROUND;
  b.setGround(g);
  world.block(Math.floor(x0), Math.floor(z0), 2, 1);
  const w = 1.8, d = 0.9;
  for (const [ox, oz] of [[0.05, 0.05], [w - 0.05, 0.05], [0.05, d - 0.05], [w - 0.05, d - 0.05]])
    b.box(x0 + ox, g + 0.75, z0 + oz, 0.08, 1.5, 0.08, C.timber);
  b.cube(x0, g + 0.62, z0, w, 0.1, d, C.wood);
  b.cube(x0 + 0.05, g, z0 + 0.05, w - 0.1, 0.62, d - 0.1, C.timber);
  const goods = [0xe0453a, 0xf0c34e, 0x6cab52, 0xd9a05b, 0xe8833a];
  for (let i = 0; i < 6; i++) for (let j = 0; j < 2; j++) {
    b.box(x0 + 0.2 + i * 0.28, g + 0.77, z0 + 0.25 + j * 0.38, 0.18, 0.16, 0.18, goods[(i + j * 2 + Math.floor(rnd() * 2)) % goods.length], 0, 0, 0, 0.06);
  }
  for (let i = 0; i < 6; i++) {
    b.cube(x0 - 0.1 + i * 0.333, g + 1.5, z0 - 0.15, 0.333, 0.12, d + 0.3, i % 2 ? 0xf6efe4 : awning, 0.02);
  }
  b.cube(x0 - 0.1, g + 1.62, z0 + 0.05, 2.0, 0.1, d - 0.1, i2(awning));
}
const i2 = (c) => shade(c, 0.85);

function well(ctx, cx, cz) {
  const { b, world } = ctx;
  const g = GROUND;
  b.setGround(g);
  world.block(Math.floor(cx - 0.6), Math.floor(cz - 0.6), 2, 2);
  b.box(cx, g + 0.32, cz - 0.55, 1.3, 0.64, 0.22, C.stone);
  b.box(cx, g + 0.32, cz + 0.55, 1.3, 0.64, 0.22, C.stone);
  b.box(cx - 0.55, g + 0.32, cz, 0.22, 0.64, 0.9, C.stone);
  b.box(cx + 0.55, g + 0.32, cz, 0.22, 0.64, 0.9, C.stone);
  b.box(cx, g + 0.52, cz, 0.9, 0.04, 0.9, 0x4fb6dc, 0, 0, 0, 0);
  b.box(cx - 0.55, g + 1.1, cz, 0.1, 1.1, 0.1, C.timber);
  b.box(cx + 0.55, g + 1.1, cz, 0.1, 1.1, 0.1, C.timber);
  b.box(cx, g + 1.45, cz, 1.2, 0.08, 0.08, C.timberDark);
  b.box(cx, g + 1.05, cz, 0.22, 0.22, 0.22, C.wood);
  let y = g + 1.65, half = 0.85, k = 0;
  while (half > 0.08) { b.cube(cx - 0.8, y, cz - half, 1.6, 0.16, half * 2, k % 2 ? 0xa83f34 : 0xc94a3c); y += 0.16; half -= 0.18; k++; }
}

function mountainStation(ctx) {
  const { b, world, dyn, rnd } = ctx;
  const g = 13;
  b.setGround(g);
  const px0 = 94, len = 16, pz0 = 21;
  b.cube(px0, g, pz0 - 0.05, len, 0.42, 2.05, 0xc5bdaf, 0.03);
  for (let k = 0; k < len * 2; k++) b.cube(px0 + k * 0.5 + 0.02, g + 0.42, pz0 + 0.18, 0.46, 0.05, 1.8, k % 2 ? 0xb88a58 : 0xc4955f, 0.04);
  b.cube(px0, g + 0.42, pz0 - 0.05, len, 0.06, 0.22, 0xeedc9c);
  // 积雪
  for (let k = 0; k < 11; k++) b.cube(px0 + 0.3 + rnd() * (len - 1.2), g + 0.47, pz0 + 0.5 + rnd() * 1.2, 0.5 + rnd() * 0.4, 0.05, 0.3 + rnd() * 0.3, C.snow, 0.02);
  world.setExtra(px0, pz0, len, 2, g + 0.47);
  world.reserve(93, 21, 18, 7);
  const h = house(ctx, 98, 23, 5, 3, { wall: 0xf1e4c8, roof: 0x8d4a3a, door: '-z', floors: 1, shutter: 0x5f7bab, sign: STATION_NAMES.mountain, signBg: '#3d4f7a' });
  // 屋顶积雪
  b.cube(97.85, h.top - 0.12, 24.3, 5.3, 0.14, 0.4, C.snow, 0.02);
  for (let k = 0; k < 4; k++) b.cube(97.85, h.top - 0.45 - k * 0.27, 24.0 - k * 0.27, 5.3, 0.08, 0.3, C.snow, 0.02);
  for (const x of [94.4, 102.0, 109.6]) lamp(b, x, 21.4, g + 0.47);
  signal(b, 110.7, 21.6, g);
  // 站长身边的小桌子（完成委托后摆上一瓶薰衣草）
  const pg = g + 0.47;
  b.setGround(pg);
  const tx = NPC_SPOT.x + 1.2, tz = NPC_SPOT.z + 0.05;
  b.box(tx, pg + 0.36, tz, 0.62, 0.07, 0.48, C.wood);
  b.box(tx, pg + 0.17, tz, 0.1, 0.34, 0.1, C.timberDark);
  b.box(tx, pg + 0.02, tz, 0.36, 0.04, 0.3, C.timberDark);
  b.box(tx + 0.12, pg + 0.46, tz - 0.05, 0.18, 0.12, 0.14, 0xf4ecd8); // 茶杯
  const vb = new BoxBuilder(41);
  vb.box(0, 0.12, 0, 0.18, 0.24, 0.18, 0x5f7bab, 0, 0, 0, 0);
  vb.box(0, 0.25, 0, 0.12, 0.04, 0.12, 0x4a6390, 0, 0, 0, 0);
  for (let k = 0; k < 7; k++) {
    const a = (k / 7) * Math.PI * 2;
    const ox = Math.cos(a) * 0.07, oz = Math.sin(a) * 0.07;
    vb.box(ox, 0.36, oz, 0.03, 0.22, 0.03, 0x6f9a5a, 0, 0, 0, 0);
    vb.box(ox * 1.4, 0.53, oz * 1.4, 0.06, 0.16, 0.06, k % 2 ? 0x9a7fd8 : 0xb79cec, 0, 0, 0, 0);
  }
  const vase = vb.mesh(ctx.mat, { cast: true, receive: false });
  vase.position.set(tx - 0.1, pg + 0.4, tz + 0.04);
  vase.visible = false;
  dyn.group.add(vase);
  dyn.vase = vase;
  // 长椅
  b.setGround(pg);
  b.box(104.0, pg + 0.3, 22.55, 1.0, 0.08, 0.32, C.wood);
  b.box(104.0, pg + 0.52, 22.74, 1.0, 0.3, 0.06, C.wood);
  b.box(103.6, pg + 0.14, 22.55, 0.08, 0.28, 0.28, C.metal);
  b.box(104.4, pg + 0.14, 22.55, 0.08, 0.28, 0.28, C.metal);
  b.box(103.8, pg + 0.38, 22.55, 0.7, 0.05, 0.26, C.snow, 0, 0, 0, 0.02);
  world.block(103, 22, 2, 1);
  world.block(Math.floor(tx), 22, 1, 1);
  // 雪人
  b.setGround(g);
  const sx = 104.6, sz = 25.2;
  b.box(sx, g + 0.32, sz, 0.66, 0.64, 0.66, C.snow, 0, 0, 0, 0.02);
  b.box(sx, g + 0.86, sz, 0.48, 0.44, 0.48, C.snow, 0, 0, 0, 0.02);
  b.box(sx, g + 1.27, sz, 0.38, 0.38, 0.38, C.snow, 0, 0, 0, 0.02);
  b.box(sx, g + 1.27, sz + 0.26, 0.08, 0.08, 0.16, 0xf08a3a);
  b.box(sx - 0.09, g + 1.36, sz + 0.2, 0.06, 0.06, 0.02, 0x2d2a33);
  b.box(sx + 0.09, g + 1.36, sz + 0.2, 0.06, 0.06, 0.02, 0x2d2a33);
  b.box(sx, g + 1.5, sz, 0.42, 0.1, 0.42, 0xc94a3c);
  b.box(sx, g + 1.62, sz, 0.26, 0.18, 0.26, 0xc94a3c);
  b.box(sx, g + 1.06, sz + 0.12, 0.5, 0.1, 0.3, 0x4f9c88);
  b.box(sx - 0.45, g + 0.95, sz, 0.5, 0.05, 0.05, C.bark, 0, 0.5);
  b.box(sx + 0.45, g + 0.95, sz, 0.5, 0.05, 0.05, C.bark, 0, -0.5);
  world.block(104, 25, 1, 1);
  for (const [x, z] of [[96.3, 24.4], [96.8, 25.2]]) crate(b, x, z, g, 0.48);
  for (let k = 0; k < 3; k++) b.box(103.2 + k * 0.05, g + 0.15 + k * 0.3, 24.3, 1.4, 0.28, 0.28, 0x8a5a36, 0, 0, 0);
}

function tunnelPortal(b, face, dir, zc, fy) {
  b.setGround(fy);
  const sc = 0xb3ab9d;
  const depth = 0.5;
  const x = face + dir * depth / 2;
  for (let k = 0; k < 6; k++) {
    for (const sd of [-1, 1]) {
      b.box(x, fy + 0.27 + k * 0.54, zc + sd * 1.82, depth, 0.52, 0.66, k % 2 ? sc : shade(sc, 1.06), 0, 0, 0, 0.05);
    }
  }
  b.box(x, fy + 3.3, zc, depth + 0.06, 0.6, 4.3, shade(sc, 1.03));
  b.box(x, fy + 3.72, zc, depth + 0.12, 0.24, 4.6, shade(sc, 0.9));
  b.box(x + dir * 0.04, fy + 3.3, zc, depth, 0.62, 0.5, 0xd8cfbf);
  b.box(x, fy + 2.82, zc - 1.25, depth, 0.36, 0.5, sc);
  b.box(x, fy + 2.82, zc + 1.25, depth, 0.36, 0.5, sc);
  // 隧道深处的暗面
  b.box(face - dir * 1.5, fy + 1.5, zc, 0.1, 3.0, 3.0, 0x15131b, 0, 0, 0, 0);
}

// ——————————————————————————————————————————————
export function buildProps(world, scene, mat) {
  const b = new BoxBuilder(11);
  const rnd = mulberry32(2024);
  const dyn = { chimneys: [], flags: [], blades: [], group: new THREE.Group() };
  const ctx = { b, world, rnd, dyn, mat };
  scene.add(dyn.group);

  // 隧道口
  for (const t of world.tunnels) tunnelPortal(b, t.face, t.dir, t.z, t.y);

  castle(ctx);

  // 城镇：后排（面朝后街）
  house(ctx, 13, 15, 3, 3, { floors: 2, roof: C.roofs[0] });
  house(ctx, 16, 15, 4, 3, { floors: 1, roof: C.roofs[2] });
  house(ctx, 13, 9, 4, 3, { floors: 2, roof: C.roofs[1] });
  house(ctx, 18, 8, 3, 3, { floors: 1, roof: C.roofs[3] });
  house(ctx, 22, 8, 4, 3, { floors: 2, roof: C.roofs[4] });
  house(ctx, 36, 15, 3, 3, { floors: 2, roof: C.roofs[1], door: '+z' });
  house(ctx, 36, 8, 4, 3, { floors: 1, roof: C.roofs[0] });
  house(ctx, 40, 8, 3, 3, { floors: 2, roof: C.roofs[2] });
  church(ctx, 27, 2);
  well(ctx, 24, 15.5);
  // 城镇：前排（面朝前街）
  house(ctx, 13, 34, 3, 3, { floors: 1, door: '-z', roof: C.roofs[3] });
  house(ctx, 16, 34, 4, 3, { floors: 2, door: '-z', roof: C.roofs[0] });
  house(ctx, 27, 34, 3, 3, { floors: 1, door: '-z', roof: C.roofs[4] });
  house(ctx, 30, 34, 4, 3, { floors: 1, door: '-z', roof: C.roofs[1] });
  house(ctx, 36, 34, 3, 3, { floors: 1, door: '-z', roof: C.roofs[2] });
  stall(ctx, 21.1, 34.3, 0xc9483b);
  stall(ctx, 24.0, 34.3, 0x4f9c88);
  for (const [x, z] of [[20.5, 36.6], [26.4, 35.2]]) barrel(b, x, z, GROUND);
  crate(b, 23.6, 36.5, GROUND, 0.45);
  // 酒馆
  const tav = house(ctx, 24, 29, 5, 3, { floors: 2, door: '+z', roof: 0x8d5a3e, wall: 0xf4e3ac });
  const tsign = signMesh('酒馆', 0.9, 0.5, '#7a4528');
  tsign.position.set(27.9, GROUND + 2.0, 32.15);
  dyn.group.add(tsign);
  b.setGround(GROUND);
  b.box(27.9, GROUND + 2.42, 32.0, 0.08, 0.08, 0.4, C.metal);
  void tav;
  townStation(ctx);

  // 路灯
  for (let x = 14; x <= 44; x += 6) lamp(b, x + 0.5, 31.6, GROUND);
  for (let x = 16; x <= 40; x += 8) lamp(b, x + 0.5, 21.4, GROUND);
  for (const [x, z] of [[20.6, 13.4], [33.4, 13.4], [20.6, 18.6], [33.4, 18.6]]) lamp(b, x, z, GROUND);
  for (const [x, z] of [[21, 17.8], [28, 17.6]]) {
    b.setGround(GROUND);
    b.box(x, GROUND + 0.3, z, 1.0, 0.08, 0.3, C.wood);
    b.box(x - 0.4, GROUND + 0.15, z, 0.08, 0.3, 0.26, C.metal);
    b.box(x + 0.4, GROUND + 0.15, z, 0.08, 0.3, 0.26, C.metal);
  }

  // 农场
  windmill(ctx, 47, 34);
  house(ctx, 44, 27, 4, 3, { floors: 1, roof: 0xbd4a3b, wall: 0xf3dac6, door: '-z' });
  for (const [x0, z0, x1, z1] of [[39, 35, 46, 39], [38, 27, 43, 31]]) {
    for (let x = x0; x < x1; x++) for (let z = z0; z < z1; z++) {
      if (!world.isFree(x, z, 1, 1)) continue;
      wheat(b, x, z, GROUND, rnd);
      world.reserve(x, z, 1, 1);
    }
    fence(b, x0, z0, x1, z0, GROUND);
    fence(b, x0, z1, x1, z1, GROUND);
    fence(b, x0, z0, x0, z1, GROUND);
  }
  for (const [x, z, r] of [[44.5, 31, 0.3], [45.8, 31.4, -0.2], [49.6, 30.6, 0.1], [50.4, 37.6, 0.5]]) hay(b, x, z, GROUND, r);
  // 果园
  for (let x = 44; x <= 50; x += 2) for (let z = 3; z <= 11; z += 2) {
    if (!world.isFree(x, z, 1, 1)) continue;
    roundTree(b, x + 0.5, z + 0.5, GROUND, 0.85 + rnd() * 0.15, pick(rnd, C.leaf), rnd, true);
    world.block(x, z, 1, 1);
  }

  // 森林里的伐木小屋与营地
  house(ctx, 53, 27, 3, 3, { floors: 1, roof: 0x8d5d3d, wall: 0xe9d2a9, door: '+z', chimney: true });
  for (let k = 0; k < 3; k++) for (let j = 0; j < 3 - k; j++) {
    b.setGround(GROUND);
    b.box(57.2 + j * 0.3 + k * 0.15, GROUND + 0.14 + k * 0.26, 28.4, 0.28, 0.28, 1.5, 0x8a5a36, 0, 0, 0, 0.06);
    b.box(57.2 + j * 0.3 + k * 0.15, GROUND + 0.14 + k * 0.26, 29.16, 0.24, 0.24, 0.02, 0xdcb27a, 0, 0, 0, 0.03);
  }
  world.block(57, 28, 1, 1);
  world.reserve(67, 3, 7, 6);
  campfire(ctx, 71.5, 6.5);

  // 人行木桥（跨河）
  footbridge(ctx, 32, 33);

  mountainStation(ctx);
  world.reserve(52, 26, 7, 5);
  meadow(ctx);

  // —— 植被 ——
  for (let z = 0; z < D; z++) for (let x = X0; x < X1; x++) {
    const t = world.i(x, z);
    if (world.lavender[t]) { lavenderBush(b, x + 0.5, z + 0.5, world.h[t], rnd); continue; }
    if (world.solid[t] || world.water[t]) continue;
    const zn = world.zone[t];
    const top = world.top[t];
    const g = world.h[t];
    const cx = x + 0.5 + (rnd() - 0.5) * 0.25, cz = z + 0.5 + (rnd() - 0.5) * 0.25;
    const freeTile = !world.reserved[t] && world.floor[t] < 0;
    const r = rnd();
    if (zn === ZONE.FOREST || (zn === ZONE.FARM && x >= 48)) {
      if (!freeTile || top === MAT.SAND) {
        if (top === MAT.SAND && r < 0.05 && freeTile) { rock(b, cx, cz, g, 0.6, false, rnd); }
        continue;
      }
      const dens = fbm2(x * 0.09, z * 0.09, 41) > 0.45 ? 0.62 : 0.24;
      if (r < dens) {
        const k = rnd();
        if (k < 0.38) pine(b, cx, cz, g, 0.85 + rnd() * 0.35, false, rnd);
        else roundTree(b, cx, cz, g, 0.85 + rnd() * 0.35, k > 0.9 ? pick(rnd, C.autumn) : pick(rnd, C.leaf), rnd);
        world.block(x, z, 1, 1);
      } else if (r < dens + 0.05) { rock(b, cx, cz, g, 0.6 + rnd() * 0.4, false, rnd); world.block(x, z, 1, 1); }
      else if (r < dens + 0.12) bush(b, cx, cz, g, rnd);
      else if (r < dens + 0.16) mushroom(b, cx, cz, g, rnd);
      else if (r < dens + 0.22) flowers(b, cx, cz, g, rnd);
      else if (r < dens + 0.4) tuft(b, cx, cz, g, rnd, 0x6aa83e);
    } else if (zn === ZONE.HILL) {
      if (!freeTile || (x >= 0 && x < 9 && z >= 8 && z <= 20)) continue;
      if (r < 0.28) {
        if (rnd() < 0.5) pine(b, cx, cz, g, 0.8 + rnd() * 0.3, false, rnd);
        else roundTree(b, cx, cz, g, 0.8 + rnd() * 0.3, pick(rnd, C.leaf), rnd);
        world.block(x, z, 1, 1);
      } else if (r < 0.36) flowers(b, cx, cz, g, rnd);
      else if (r < 0.42) bush(b, cx, cz, g, rnd);
      else if (r < 0.6) tuft(b, cx, cz, g, rnd, 0x7ab848);
    } else if (zn === ZONE.FOOT || zn === ZONE.MOUNT || (x >= 76 && zn !== ZONE.RIVER)) {
      if (!freeTile) continue;
      const snowy = top === MAT.SNOW;
      if (top === MAT.ROCK) { if (r < 0.1) rock(b, cx, cz, g, 0.7, false, rnd); continue; }
      if (zn === ZONE.MOUNT && g > 15) { if (r < 0.04) rock(b, cx, cz, g, 0.6, snowy, rnd); continue; }
      const dens = zn === ZONE.MOUNT ? 0.08 : 0.2;
      if (r < dens) { pine(b, cx, cz, g, 0.8 + rnd() * 0.35, snowy, rnd); world.block(x, z, 1, 1); }
      else if (r < dens + 0.05) { rock(b, cx, cz, g, 0.6 + rnd() * 0.5, snowy, rnd); world.block(x, z, 1, 1); }
      else if (!snowy && r < dens + 0.12) bush(b, cx, cz, g, rnd);
      else if (!snowy && r < dens + 0.2) tuft(b, cx, cz, g, rnd, 0x7ab848);
    } else if (zn === ZONE.MEADOW) {
      if (!freeTile) continue;
      if (r < 0.025) { birch(b, cx, cz, g, 0.85 + rnd() * 0.3, rnd); world.block(x, z, 1, 1); }
      else if (r < 0.035) { roundTree(b, cx, cz, g, 0.8 + rnd() * 0.3, pick(rnd, [0x8fcc58, 0x9fd462]), rnd); world.block(x, z, 1, 1); }
      else if (r < 0.2) wildflowers(b, cx, cz, g, rnd);
      else if (r < 0.42) tuft(b, cx, cz, g, rnd, 0xa6d474);
    } else if (zn === ZONE.TOWN || zn === ZONE.FARM) {
      if (!freeTile || top === MAT.COBBLE) continue;
      if (z <= 2 || z >= 38 || (x >= 37 && z <= 13)) {
        if (r < 0.35) { roundTree(b, cx, cz, g, 0.8 + rnd() * 0.3, pick(rnd, C.leaf), rnd); world.block(x, z, 1, 1); }
        else if (r < 0.5) bush(b, cx, cz, g, rnd);
        continue;
      }
      if (r < 0.04) { roundTree(b, cx, cz, g, 0.75 + rnd() * 0.25, pick(rnd, C.leaf), rnd); world.block(x, z, 1, 1); }
      else if (r < 0.12) flowers(b, cx, cz, g, rnd);
      else if (r < 0.18) bush(b, cx, cz, g, rnd);
      else if (r < 0.34) tuft(b, cx, cz, g, rnd, 0x7ab848);
    }
  }

  const mesh = b.mesh(mat);
  scene.add(mesh);
  return { mesh, dyn };
}

function campfire(ctx, cx, cz) {
  const { b, world, dyn } = ctx;
  const g = world.hAt(cx, cz);
  b.setGround(g);
  for (let k = 0; k < 8; k++) {
    const a = (k / 8) * Math.PI * 2;
    b.box(cx + Math.cos(a) * 0.45, g + 0.08, cz + Math.sin(a) * 0.45, 0.2, 0.16, 0.2, 0x8f8a99);
  }
  b.box(cx, g + 0.1, cz, 0.7, 0.12, 0.12, 0x7a4f30, 0.6);
  b.box(cx, g + 0.1, cz, 0.7, 0.12, 0.12, 0x7a4f30, -0.6);
  for (const [ox, oz, r] of [[-1.3, 0.2, 0], [1.2, -0.4, 1.3], [0.1, 1.3, 0.4]]) {
    b.box(cx + ox, g + 0.15, cz + oz, 1.0, 0.26, 0.3, 0x8a5a36, r);
  }
  // 帐篷
  const tx = cx - 2.6, tz = cz - 1.8;
  let y = g, half = 1.0, k = 0;
  while (half > 0.08) { b.cube(tx - half, y, tz - 0.8, half * 2, 0.2, 1.6, k % 2 ? 0xe9dcc2 : 0xf3e8d2); y += 0.2; half -= 0.13; k++; }
  b.cube(tx - 0.22, g, tz + 0.79, 0.44, 0.6, 0.03, 0x6e5a48);
  world.block(Math.floor(tx - 1), Math.floor(tz - 1), 2, 2);
  world.block(Math.floor(cx), Math.floor(cz), 1, 1);
  // 火焰（动画）
  const fb = new BoxBuilder(3);
  fb.box(0, 0.12, 0, 0.3, 0.24, 0.3, 0xff8a2a, 0, 0, 0, 0);
  fb.box(0, 0.3, 0, 0.18, 0.2, 0.18, 0xffc94a, 0, 0, 0, 0);
  fb.box(0.06, 0.45, -0.04, 0.08, 0.12, 0.08, 0xfff1a8, 0, 0, 0, 0);
  const fire = fb.mesh(new THREE.MeshBasicMaterial({ vertexColors: true }), { cast: false, receive: false });
  fire.position.set(cx, g + 0.12, cz);
  dyn.group.add(fire);
  dyn.fire = fire;
  dyn.chimneys.push(new THREE.Vector3(cx, g + 0.8, cz));
}

function footbridge(ctx, z0, z1) {
  const { b, world } = ctx;
  let minX = X1, maxX = -1;
  for (let z = z0; z <= z1; z++) for (let x = 50; x < 80; x++) {
    if (world.water[world.i(x, z)]) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); }
  }
  if (maxX < 0) return;
  const xa = minX - 0.6, xb = maxX + 1.6, y = GROUND + 0.12;
  b.setGround(null);
  for (let x = xa; x < xb; x += 0.34) {
    b.cube(x, y - 0.12, z0 - 0.15, 0.32, 0.12, z1 - z0 + 1.3, (Math.round(x * 3) % 2) ? 0xb07a48 : 0xa06d3f, 0.05);
  }
  for (const zz of [z0 - 0.2, z1 + 1.1]) {
    b.cube(xa, y - 0.26, zz, xb - xa, 0.16, 0.12, C.timberDark);
    for (let x = xa + 0.1; x <= xb; x += 1.2) b.box(x, y + 0.25, zz + 0.06, 0.1, 0.55, 0.1, C.timber);
    b.cube(xa, y + 0.45, zz, xb - xa, 0.07, 0.1, C.woodLight);
  }
  for (let x = minX + 0.5; x <= maxX + 0.5; x += 1.6) {
    for (const zz of [z0 + 0.1, z1 + 0.8]) b.box(x, (y - 0.2 + 5) / 2, zz, 0.16, y - 0.2 - 5, 0.16, C.timberDark);
  }
  for (let z = z0; z <= z1; z++) for (let x = minX - 1; x <= maxX + 1; x++) {
    if (world.inside(x, z)) world.setExtra(x, z, 1, 1, y);
  }
  world.reserve(minX - 2, z0, maxX - minX + 5, z1 - z0 + 1);
}

// —— 西边花田 ——
const LAV = [0x9a7fd8, 0x8c6fd0, 0xa58ae0, 0x8a6cc8];

function lavenderBush(b, cx, cz, g, rnd) {
  b.setGround(g);
  b.box(cx, g + 0.1, cz, 0.98, 0.2, 0.7, 0x86a274, 0, 0, 0, 0.05);
  const col = pick(rnd, LAV);
  b.box(cx, g + 0.3, cz, 0.94, 0.22, 0.62, col, 0, 0, 0, 0.05);
  b.box(cx + (rnd() - 0.5) * 0.2, g + 0.46, cz, 0.56, 0.14, 0.42, shade(col, 1.1), 0, 0, 0, 0.04);
  for (let k = 0; k < 3; k++) {
    b.box(cx + (rnd() - 0.5) * 0.62, g + 0.5 + rnd() * 0.06, cz + (rnd() - 0.5) * 0.4, 0.08, 0.16, 0.08, 0xc2a8f0, 0, 0, 0, 0.04);
  }
}

function wildflowers(b, x, z, g, rnd) {
  const cols = [0xffffff, 0xfff1a8, 0xffc4dc, 0xd8c8ff, 0xffe066];
  for (let k = 0; k < 4; k++) {
    const fx = x + (rnd() - 0.5) * 0.7, fz = z + (rnd() - 0.5) * 0.7;
    b.box(fx, g + 0.07, fz, 0.04, 0.14, 0.04, 0x86b85a, 0, 0, 0, 0);
    b.box(fx, g + 0.17, fz, 0.09, 0.06, 0.09, pick(rnd, cols), 0, 0, 0, 0.02);
  }
}

function birch(b, x, z, g, sc, rnd) {
  b.setGround(g);
  const th = 1.15 * sc;
  b.box(x, g + th / 2, z, 0.2 * sc, th, 0.2 * sc, 0xf0ece2, 0, 0, 0, 0.03);
  b.box(x, g + th * 0.35, z + 0.1 * sc + 0.005, 0.1, 0.05, 0.01, 0x3a3444, 0, 0, 0, 0);
  b.box(x + 0.1 * sc + 0.005, g + th * 0.65, z, 0.01, 0.05, 0.1, 0x3a3444, 0, 0, 0, 0);
  const col = pick(rnd, [0xa8d86a, 0xb5df78, 0x9fd062]);
  b.box(x, g + th + 0.42 * sc, z, 0.95 * sc, 0.84 * sc, 0.95 * sc, col, 0, 0, 0, 0.05);
  b.box(x + 0.1, g + th + 0.95 * sc, z - 0.05, 0.6 * sc, 0.38 * sc, 0.6 * sc, shade(col, 1.08), 0, 0, 0, 0.05);
}

function cypress(b, x, z, g, sc, rnd) {
  b.setGround(g);
  b.box(x, g + 0.15, z, 0.18, 0.3, 0.18, C.bark);
  const col = pick(rnd, [0x3e7a4c, 0x356d43, 0x447f50]);
  b.box(x, g + 0.3 + 1.1 * sc, z, 0.62 * sc, 2.2 * sc, 0.62 * sc, col, 0, 0, 0, 0.04);
  b.box(x, g + 0.3 + 2.5 * sc, z, 0.42 * sc, 0.6 * sc, 0.42 * sc, shade(col, 1.08), 0, 0, 0, 0.04);
  b.box(x, g + 0.3 + 2.95 * sc, z, 0.2 * sc, 0.3 * sc, 0.2 * sc, col, 0, 0, 0, 0.04);
}

function beehive(b, x, z, g) {
  b.setGround(g);
  b.box(x, g + 0.1, z, 0.5, 0.2, 0.45, C.timberDark);
  b.box(x, g + 0.4, z, 0.44, 0.4, 0.4, 0xf6efe0);
  b.box(x, g + 0.42, z, 0.46, 0.05, 0.42, 0xe8c24a);
  b.box(x, g + 0.64, z, 0.54, 0.08, 0.5, 0xd6683f);
  b.box(x, g + 0.3, z + 0.205, 0.14, 0.04, 0.02, 0x3a3444, 0, 0, 0, 0);
}

function lavenderCart(b, x, z, g, rnd) {
  b.setGround(g);
  b.box(x, g + 0.5, z, 1.6, 0.12, 0.8, C.wood);
  for (const sd of [-1, 1]) {
    b.box(x, g + 0.66, z + sd * 0.38, 1.6, 0.22, 0.06, C.woodLight);
    b.box(x + sd * 0.78, g + 0.66, z, 0.06, 0.22, 0.8, C.woodLight);
    b.box(x - 0.3, g + 0.3, z + sd * 0.46, 0.54, 0.54, 0.08, C.timberDark);
    b.box(x - 0.3, g + 0.3, z + sd * 0.46, 0.54, 0.54, 0.08, C.timberDark, 0, Math.PI / 4);
    b.box(x + 1.15, g + 0.48, z + sd * 0.25, 0.8, 0.06, 0.06, C.timber, 0, -0.25);
  }
  for (let i = 0; i < 6; i++) {
    const bx = x - 0.55 + (i % 3) * 0.38, bz = z - 0.15 + Math.floor(i / 3) * 0.3;
    b.box(bx, g + 0.68 + Math.floor(i / 3) * 0.08, bz, 0.26, 0.16, 0.5, pick(rnd, LAV), 0.2 * (rnd() - 0.5));
    b.box(bx, g + 0.66, bz + 0.3, 0.12, 0.1, 0.16, 0x6f9a5a);
  }
}

function scarecrow(b, x, z, g) {
  b.setGround(g);
  b.box(x, g + 0.75, z, 0.1, 1.5, 0.1, C.timber);
  b.box(x, g + 1.15, z, 1.1, 0.08, 0.08, C.timber);
  b.box(x, g + 1.05, z, 0.42, 0.5, 0.26, 0x6a8fd0);
  b.box(x, g + 0.82, z, 0.44, 0.06, 0.28, 0x7a4f30);
  b.box(x - 0.48, g + 1.15, z, 0.16, 0.16, 0.16, 0xe4c56a);
  b.box(x + 0.48, g + 1.15, z, 0.16, 0.16, 0.16, 0xe4c56a);
  b.box(x, g + 1.5, z, 0.32, 0.32, 0.3, 0xe7d3a8);
  b.box(x - 0.07, g + 1.53, z + 0.155, 0.05, 0.05, 0.02, 0x2d2a33, 0, 0, 0, 0);
  b.box(x + 0.07, g + 1.53, z + 0.155, 0.05, 0.05, 0.02, 0x2d2a33, 0, 0, 0, 0);
  b.box(x, g + 1.68, z, 0.6, 0.05, 0.6, C.hay);
  b.box(x, g + 1.78, z, 0.3, 0.16, 0.3, C.hay);
}

function picnic(b, x, z, g) {
  b.setGround(g);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) {
    b.box(x - 0.45 + i * 0.3, g + 0.015, z - 0.45 + j * 0.3, 0.3, 0.03, 0.3, (i + j) % 2 ? 0xd9534f : 0xf6efe4, 0, 0, 0, 0.02);
  }
  b.box(x + 0.25, g + 0.15, z - 0.2, 0.36, 0.24, 0.26, 0xb07a48);
  b.box(x + 0.25, g + 0.34, z - 0.2, 0.36, 0.04, 0.06, C.timber);
  b.box(x - 0.2, g + 0.06, z + 0.15, 0.12, 0.08, 0.12, 0xe0453a);
  b.box(x - 0.05, g + 0.06, z + 0.25, 0.12, 0.08, 0.12, 0xf0c34e);
}

function fieldSign(ctx, text, cx, cz, g) {
  const { b, dyn } = ctx;
  b.setGround(g);
  const w = 1.6, h = 0.5, y = g + 0.75;
  for (const sd of [-1, 1]) b.box(cx + sd * 0.6, (g + y + h / 2) / 2, cz - 0.08, 0.1, y + h / 2 - g, 0.1, C.timberDark);
  b.box(cx, y, cz - 0.06, w + 0.14, h + 0.14, 0.08, C.timberDark);
  const sign = signMesh(text, w, h, '#6a4fa8');
  sign.position.set(cx, y, cz - 0.015);
  dyn.group.add(sign);
}

function meadow(ctx) {
  const { b, world, rnd } = ctx;
  const g = GROUND;
  // 普罗旺斯风格的农舍
  house(ctx, -30, 32, 5, 3, { floors: 2, wall: 0xf3e2c4, wall1: 0xe2d0ae, roof: 0xd6683f, shutter: 0x8a8fd6, door: '-z' });
  for (let k = 0; k < 5; k++) beehive(b, -29.4 + k * 1.1, 36.6, g);
  world.block(-30, 36, 6, 1);
  lavenderCart(b, -21.4, 32.6, g, rnd);
  world.block(-23, 32, 3, 1);
  for (const [x, z] of [[-21.5, 29.3], [-17.5, 29.3], [-13.5, 29.3], [-9.5, 29.3], [-31.6, 31.4], [-31.6, 34.6], [-14.6, 31.6]]) {
    cypress(b, x, z, world.hAt(x, z), 0.9 + rnd() * 0.25, rnd);
    world.block(Math.floor(x), Math.floor(z), 1, 1);
  }
  scarecrow(b, -15.5, 8.5, g);
  world.block(-16, 8, 1, 1);
  picnic(b, -17.5, 35.5, g);
  world.reserve(-19, 34, 3, 3);
  fieldSign(ctx, '薰衣草田', -15.0, 27.6, g);
  world.reserve(-16, 27, 3, 1);
  haltPlatform(ctx);
}

// 花田站：只有一段木站台和站牌的小招呼站
function haltPlatform(ctx) {
  const { b, world, dyn } = ctx;
  const g = GROUND;
  b.setGround(g);
  const px0 = -31, len = 13, pz0 = 17.3, pd = 1.6;
  b.cube(px0, g, pz0, len, 0.42, pd, 0xc9bda6, 0.03);
  for (let k = 0; k < len * 2; k++) {
    b.cube(px0 + k * 0.5 + 0.02, g + 0.42, pz0 + 0.22, 0.46, 0.05, pd - 0.28, k % 2 ? 0xc49a62 : 0xd0a66c, 0.04);
  }
  b.cube(px0, g + 0.42, pz0, len, 0.06, 0.22, 0xeedc9c);
  world.setExtra(px0, 17, len, 2, g + 0.47);
  const pg = g + 0.47;
  // 小雨棚 + 长椅
  for (const x of [-26.6, -23.4]) b.box(x, pg + 0.95, 18.55, 0.12, 1.9, 0.12, C.timberDark);
  b.cube(-27.2, pg + 1.9, 17.9, 4.4, 0.12, 1.2, 0x7a5cb0);
  b.cube(-27.0, pg + 2.02, 18.1, 4.0, 0.12, 0.8, 0x9a7fd8);
  for (let k = 0; k < 11; k++) b.cube(-27.15 + k * 0.4, pg + 1.8, 17.86, 0.2, 0.1, 0.05, k % 2 ? 0xf3e6c8 : 0x7a5cb0);
  b.box(-25.0, pg + 0.3, 18.55, 1.2, 0.08, 0.32, C.wood);
  b.box(-25.0, pg + 0.52, 18.74, 1.2, 0.3, 0.06, C.wood);
  b.box(-25.5, pg + 0.14, 18.55, 0.08, 0.28, 0.28, C.metal);
  b.box(-24.5, pg + 0.14, 18.55, 0.08, 0.28, 0.28, C.metal);
  world.block(-26, 18, 2, 1);
  for (const x of [-30.4, -21.5]) lamp(b, x, 17.75, pg);
  // 几只装满花的木箱
  for (const [x, z] of [[-29.3, 18.45], [-28.8, 18.5]]) {
    crate(b, x, z, pg, 0.42);
    b.box(x, pg + 0.47, z, 0.36, 0.1, 0.36, 0x9a7fd8, 0, 0, 0, 0.05);
  }
  world.block(-30, 18, 2, 1);
  // 站牌
  const sx = -20.0, sz = 18.7;
  for (const sd of [-1, 1]) b.box(sx + sd * 0.7, pg + 0.65, sz - 0.08, 0.1, 1.3, 0.1, C.timberDark);
  b.box(sx, pg + 1.12, sz - 0.06, 1.74, 0.6, 0.08, C.timberDark);
  const sign = signMesh(STATION_NAMES.meadow, 1.6, 0.48, '#6a4fa8');
  sign.position.set(sx, pg + 1.12, sz - 0.015);
  dyn.group.add(sign);
  world.block(-21, 18, 1, 1);
}
