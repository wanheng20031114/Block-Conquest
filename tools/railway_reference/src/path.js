// 铁路中心线：折线 + 圆角，按弧长参数化
import { WAYPOINTS, GROUND } from './config.js';
import { smoothstep } from './noise.js';

export class TrackPath {
  constructor(wp = WAYPOINTS, radius = 4) {
    const pts = [{ x: wp[0][0], z: wp[0][1] }];
    for (let i = 1; i < wp.length - 1; i++) {
      const [px, pz] = wp[i - 1], [cx, cz] = wp[i], [nx, nz] = wp[i + 1];
      const din = unit(cx - px, cz - pz), dout = unit(nx - cx, nz - cz);
      const sx = cx - din.x * radius, sz = cz - din.z * radius;
      pts.push({ x: sx, z: sz });
      const ccx = sx + dout.x * radius, ccz = sz + dout.z * radius;
      const N = 24;
      for (let k = 1; k <= N; k++) {
        const a = (k / N) * Math.PI / 2;
        pts.push({
          x: ccx - dout.x * radius * Math.cos(a) + din.x * radius * Math.sin(a),
          z: ccz - dout.z * radius * Math.cos(a) + din.z * radius * Math.sin(a),
        });
      }
    }
    pts.push({ x: wp[wp.length - 1][0], z: wp[wp.length - 1][1] });

    this.xs = new Float64Array(pts.length);
    this.zs = new Float64Array(pts.length);
    this.cum = new Float64Array(pts.length);
    for (let i = 0; i < pts.length; i++) {
      this.xs[i] = pts[i].x;
      this.zs[i] = pts[i].z;
      if (i > 0) this.cum[i] = this.cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z);
    }
    this.length = this.cum[pts.length - 1];

    // 爬坡区段：森林出口处开始抬升，到雪峰站前达到 +5
    this.climbA = this.sNear(75, 15.5);
    this.climbB = this.sNear(96, 19.5);
  }

  y(s) {
    return GROUND + 5 * smoothstep(this.climbA, this.climbB, s);
  }

  // 返回 s 处的位置与水平切线；超出两端时沿端点方向外推
  at(s, out = {}) {
    const n = this.xs.length;
    let i;
    if (s <= 0) i = 0;
    else if (s >= this.length) i = n - 2;
    else {
      let lo = 0, hi = n - 1;
      while (hi - lo > 1) {
        const mid = (lo + hi) >> 1;
        if (this.cum[mid] <= s) lo = mid; else hi = mid;
      }
      i = lo;
    }
    const seg = this.cum[i + 1] - this.cum[i] || 1e-6;
    const t = (s - this.cum[i]) / seg;
    const dx = (this.xs[i + 1] - this.xs[i]) / seg;
    const dz = (this.zs[i + 1] - this.zs[i]) / seg;
    out.x = this.xs[i] + (this.xs[i + 1] - this.xs[i]) * t;
    out.z = this.zs[i] + (this.zs[i + 1] - this.zs[i]) * t;
    out.dx = dx;
    out.dz = dz;
    out.y = this.y(s);
    return out;
  }

  // 找离 (x,z) 最近的弧长
  sNear(x, z) {
    let best = Infinity, bs = 0;
    for (let i = 0; i < this.xs.length - 1; i++) {
      const ax = this.xs[i], az = this.zs[i], bx = this.xs[i + 1], bz = this.zs[i + 1];
      const vx = bx - ax, vz = bz - az;
      const L2 = vx * vx + vz * vz || 1e-9;
      let t = ((x - ax) * vx + (z - az) * vz) / L2;
      t = Math.max(0, Math.min(1, t));
      const px = ax + vx * t, pz = az + vz * t;
      const d = (px - x) ** 2 + (pz - z) ** 2;
      if (d < best) { best = d; bs = this.cum[i] + t * Math.sqrt(L2); }
    }
    return bs;
  }
}

function unit(x, z) {
  const l = Math.hypot(x, z) || 1;
  return { x: x / l, z: z / l };
}
