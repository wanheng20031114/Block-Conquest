// 铁轨：道砟、枕木、钢轨，过河处换成木栈桥
import { BoxBuilder } from './builder.js';
import { C } from './props.js';

export function buildTrack(world, path, mat) {
  const b = new BoxBuilder(23);
  const sA = world.sPortalL - 3, sB = world.sPortalR + 3;
  const p = {}, q = {};
  const isWater = (x, z) => {
    const tx = Math.floor(x), tz = Math.floor(z);
    if (!world.inside(tx, tz)) return false;
    return world.water[world.i(tx, tz)] === 1;
  };

  // 道砟 / 桥面
  const step = 0.5;
  let k = 0;
  for (let s = sA; s < sB; s += step, k++) {
    path.at(s + step / 2, p);
    path.at(s, q);
    const yaw = Math.atan2(-p.dz, p.dx);
    const pitch = Math.atan2(path.y(s + step) - path.y(s), step);
    const water = isWater(p.x, p.z) || isWater(p.x + p.dz * 0.7, p.z - p.dx * 0.7) || isWater(p.x - p.dz * 0.7, p.z + p.dx * 0.7);
    if (water) {
      b.setGround(null);
      b.box(p.x, p.y, p.z, step + 0.02, 0.16, 2.0, k % 2 ? 0xa06d3f : 0xb07a48, yaw, pitch, 0, 0.04);
      for (const sd of [-1, 1]) {
        b.box(p.x + p.dz * sd * 0.98, p.y - 0.12, p.z - p.dx * sd * 0.98, step + 0.02, 0.22, 0.14, C.timberDark, yaw, pitch);
        if (k % 2 === 0) b.box(p.x + p.dz * sd * 1.02, p.y + 0.3, p.z - p.dx * sd * 1.02, 0.1, 0.6, 0.1, C.timber);
      }
      b.box(p.x + p.dz * 1.02, p.y + 0.56, p.z - p.dx * 1.02, step + 0.02, 0.07, 0.09, C.woodLight, yaw);
      b.box(p.x - p.dz * 1.02, p.y + 0.56, p.z + p.dx * 1.02, step + 0.02, 0.07, 0.09, C.woodLight, yaw);
      if (k % 3 === 0) {
        const bed = 5;
        for (const sd of [-0.8, 0.8]) {
          const h = p.y - 0.1 - bed;
          b.box(p.x + p.dz * sd, bed + h / 2, p.z - p.dx * sd, 0.18, h, 0.18, C.timberDark);
        }
        b.box(p.x, (p.y + bed) / 2, p.z, 0.1, (p.y - bed) * 1.1, 0.1, C.timber, yaw + Math.PI / 2, 0, 0.75);
      }
      // 桥面可行走
      for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) {
        const tx = Math.floor(p.x) + dx, tz = Math.floor(p.z) + dz;
        if (!world.inside(tx, tz)) continue;
        const t = world.i(tx, tz);
        if (Math.hypot(tx + 0.5 - p.x, tz + 0.5 - p.z) < 1.15) world.extra[t] = Math.max(world.extra[t], p.y + 0.12);
      }
    } else {
      const base = world.hAt(p.x, p.z) - 0.04;
      const top = p.y + 0.08;
      const hgt = Math.max(0.12, top - base);
      b.setGround(base);
      b.box(p.x, top - hgt / 2, p.z, step + 0.04, hgt, 1.5, k % 2 ? 0xb9ad9b : 0xb1a592, yaw, pitch, 0, 0.05);
      if (hgt > 0.3) {
        // 路堤两侧斜坡
        for (const sd of [-1, 1]) {
          b.box(p.x + p.dz * sd * 0.92, base + (hgt - 0.15) / 2, p.z - p.dx * sd * 0.92, step + 0.04, hgt - 0.15, 0.4, 0xa89c8a, yaw, pitch, 0, 0.05);
        }
      }
    }
  }

  // 枕木
  b.setGround(null);
  let n = 0;
  for (let s = sA; s < sB; s += 0.55, n++) {
    path.at(s, p);
    const yaw = Math.atan2(-p.dz, p.dx);
    b.box(p.x, p.y + 0.12, p.z, 0.28, 0.09, 1.28, n % 3 === 0 ? 0x7d5236 : 0x8c5d3c, yaw, 0, 0, 0.06);
  }

  // 钢轨（分段拼接）
  const railStep = 0.5;
  for (const sd of [-0.42, 0.42]) {
    for (let s = sA; s < sB; s += railStep) {
      path.at(s, p);
      path.at(s + railStep, q);
      const ax = p.x + p.dz * sd, az = p.z - p.dx * sd;
      const bx = q.x + q.dz * sd, bz = q.z - q.dx * sd;
      const dx = bx - ax, dz = bz - az, dy = q.y - p.y;
      const hl = Math.hypot(dx, dz);
      const yaw = Math.atan2(-dz, dx);
      const pitch = Math.atan2(dy, hl);
      const cy = (p.y + q.y) / 2 + 0.21;
      b.box((ax + bx) / 2, cy - 0.03, (az + bz) / 2, Math.hypot(hl, dy) + 0.02, 0.06, 0.14, 0x6f6b78, yaw, pitch, 0, 0);
      b.box((ax + bx) / 2, cy + 0.02, (az + bz) / 2, Math.hypot(hl, dy) + 0.02, 0.07, 0.08, 0xd2d7e0, yaw, pitch, 0, 0);
    }
  }

  // 可以踩着铁轨走
  for (let t = 0; t < world.trackD.length; t++) {
    if (world.trackD[t] < 0.9 && !world.water[t]) {
      world.extra[t] = Math.max(world.extra[t], world.trackY[t] + 0.12);
    }
  }

  return b.mesh(mat);
}
