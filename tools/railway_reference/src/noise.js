// 确定性随机数与噪声（同一种子每次生成同样的世界）
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hash2(x, z, s = 0) {
  let h = Math.imul(x | 0, 374761393) ^ Math.imul(z | 0, 668265263) ^ Math.imul((s | 0) + 1, 1274126177);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

export function hash3(x, y, z) {
  return hash2(x * 7 + y * 131, z * 3 - y * 17, y * 59 + 3);
}

const fade = (t) => t * t * (3 - 2 * t);

export function noise2(x, z, s = 0) {
  const xi = Math.floor(x), zi = Math.floor(z);
  const xf = x - xi, zf = z - zi;
  const a = hash2(xi, zi, s), b = hash2(xi + 1, zi, s);
  const c = hash2(xi, zi + 1, s), d = hash2(xi + 1, zi + 1, s);
  const u = fade(xf), v = fade(zf);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

export function fbm2(x, z, s = 0, oct = 3) {
  let sum = 0, amp = 1, f = 1, norm = 0;
  for (let i = 0; i < oct; i++) {
    sum += amp * noise2(x * f, z * f, s + i * 17);
    norm += amp;
    amp *= 0.5;
    f *= 2;
  }
  return sum / norm;
}

export function smoothstep(a, b, x) {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, t) => a + (b - a) * t;
