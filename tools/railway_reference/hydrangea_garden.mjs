// Offline modeling for the requested hydrangea garden. Shared shrub meshes are
// saved as native Godot scenes; the game never builds these flowers at runtime.

export function adaptReferenceFlowers(source) {
  const signature = 'function lavenderBush(b, cx, cz, g, rnd) {';
  if (source.split(signature).length !== 2) throw new Error('Review the reference flower adapter: lavenderBush changed.');
  // Run the original authoring function to retain both original random streams,
  // then remove only its six flat boxes. All other scenery keeps its placement.
  source = source.replace(signature, `function lavenderBush(b, cx, cz, g, rnd) {
  const ends = [b.pos.length, b.nor.length, b.col.length, b.idx.length, b.vc];
  referenceLavenderBush(b, cx, cz, g, rnd);
  [b.pos.length, b.nor.length, b.col.length, b.idx.length, b.vc] = ends;
}
function referenceLavenderBush(b, cx, cz, g, rnd) {`);
  const sign = "fieldSign(ctx, '薰衣草田',";
  if (source.split(sign).length !== 2) throw new Error('Review the reference flower sign adapter.');
  return source.replace(sign, "fieldSign(ctx, '紫阳花海',");
}

function pathX(z) {
  return -23.8 + Math.sin((z - 3) * 0.42) * 0.65;
}

export function prepareHydrangeaGround(world, config) {
  for (const field of config.FIELDS) {
    for (let z = field.z0; z <= field.z1; z++) for (let x = field.x0; x <= field.x1; x++) {
      const tile = world.i(x, z);
      if (world.h[tile] !== config.GROUND || world.water[tile] || world.trackD[tile] < 2.8) continue;
      if (![config.MAT.SOIL, config.MAT.MEADOW].includes(world.top[tile])) continue;
      // Remove the alternating bare farm furrows, leaving one winding garden
      // path in each main bed. Existing railway/platform access stays intact.
      const walkway = field.x0 === -31 && Math.abs(x + 0.5 - pathX(z + 0.5)) < 0.55;
      const material = walkway ? config.MAT.PATH : config.MAT.MEADOW;
      world.top[tile] = material;
      world.setVox(x, config.GROUND - 1, z, material);
    }
  }
}

const PALETTES = [
  { name: 'blue', core: 0x6c84c8, petals: [0x819fdf, 0x9bb9ee, 0x7194d4, 0xb1c7ed] },
  { name: 'violet', core: 0x8874ba, petals: [0xaa94d7, 0xc0aae6, 0x927cc5, 0xcfbced] },
  { name: 'pink', core: 0xb77ea5, petals: [0xcf9abd, 0xe2b0cc, 0xbe88b1, 0xecc2d6] },
];

function random(seed) {
  return () => {
    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
    let n = Math.imul(seed ^ seed >>> 15, 1 | seed);
    n = n + Math.imul(n ^ n >>> 7, 61 | n) ^ n;
    return ((n ^ n >>> 14) >>> 0) / 4294967296;
  };
}

function shrubGeometry(THREE, BoxBuilder, palette, variation, detailed) {
  const b = new BoxBuilder(830 + variation);
  const rnd = random(900 + variation);
  b.setGround(0);
  // Broad, tapered opposite leaves, with a visible central vein. Their deep
  // green silhouette separates each flowering shrub from the meadow grass.
  for (let i = 0; i < 12; i++) {
    const angle = i * 2.399963 + variation * 0.7;
    const length = 0.46 + rnd() * 0.12;
    const radius = 0.30 + rnd() * 0.11;
    const x = Math.cos(angle) * radius, z = Math.sin(angle) * radius;
    const y = 0.42 + (i % 3) * 0.14;
    const leaf = i % 3 === 0 ? 0x598455 : (i % 3 === 1 ? 0x477548 : 0x3b6842);
    b.box(x, y, z, length, 0.075, 0.32, leaf, -angle, 0.22, 0, 0.04);
    b.box(x + Math.cos(angle) * length * 0.42, y + 0.035, z + Math.sin(angle) * length * 0.42,
      length * 0.35, 0.065, 0.18, leaf, -angle, 0.18, 0, 0.04);
    b.box(x, y + 0.045, z, length * 0.85, 0.022, 0.022, 0x759966, -angle, 0.22, 0, 0.01);
  }
  const heads = [
    [-0.29, 0.88 + variation * 0.035, 0.14, 0.34],
    [0.29, 1.01 - variation * 0.025, 0.07, 0.36],
    [-0.04, 1.16 + variation * 0.02, -0.27, 0.38],
  ];
  for (const [cx, cy, cz, radius] of heads) {
    b.box(cx, cy * 0.36, cz, 0.045, cy * 0.72, 0.045, 0x4b7345, 0, 0, 0, 0.02);
    // Voxel sphere, built as short rows inside the florets. A square plate
    // would protrude at the corners and make the entire bloom read as a box.
    const cell = radius * (detailed ? 0.14 : 0.32), coreRadius = radius * 0.78;
    const steps = Math.floor(coreRadius / cell);
    for (let iy = -steps; iy <= steps; iy++) for (let iz = -steps; iz <= steps; iz++) {
      const remainder = coreRadius * coreRadius - (iy * iy + iz * iz) * cell * cell;
      if (remainder < 0) continue;
      const span = Math.floor(Math.sqrt(remainder) / cell);
      b.box(cx, cy + iy * cell, cz + iz * cell, (span * 2 + 1) * cell,
        cell, cell, palette.core, 0, 0, 0, 0.025);
    }
    const count = detailed ? 47 : 29;
    const floretScale = detailed ? 0.82 : 1.0;
    for (let i = 0; i < count; i++) {
      const ny = -0.28 + (i + 0.5) / count * 1.26;
      const angle = i * 2.399963 + variation * 0.4;
      const horizontal = Math.sqrt(1 - ny * ny);
      const normal = new THREE.Vector3(Math.cos(angle) * horizontal, ny, Math.sin(angle) * horizontal);
      const rotation = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), normal);
      const e = new THREE.Euler().setFromQuaternion(rotation, 'YZX');
      const center = new THREE.Vector3(cx, cy, cz).addScaledVector(normal, radius * 0.92);
      const color = palette.petals[(i + variation) % palette.petals.length];
      // Four broad sepals per floret; the tiny pale center is most visible on
      // the upper hemisphere when zoomed in, like a real mophead hydrangea.
      for (let petal = 0; petal < 4; petal++) {
        const petalAngle = petal * Math.PI / 2;
        const grains = detailed
          ? [[0, -1], [-1, 0], [0, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]
          : [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]];
        const grainSize = (detailed ? 0.027 : 0.039) * floretScale;
        for (const [gx, gz] of grains) {
          const px = gx * grainSize * 1.04;
          const pz = 0.043 * floretScale + gz * grainSize * 1.04;
          // Individual grains form a gently cupped, scalloped sepal. There is
          // no single square slab under the flower's petal silhouette.
          const rise = (Math.abs(gx) * 0.006 + Math.max(0, gz) * 0.009) * floretScale;
          const offset = new THREE.Vector3(px * Math.cos(petalAngle) - pz * Math.sin(petalAngle), rise,
            px * Math.sin(petalAngle) + pz * Math.cos(petalAngle)).applyQuaternion(rotation).add(center);
          const tint = (i + petal + Math.round(gx + gz) + 8) % 5 === 0
            ? palette.petals[(i + variation + 1) % palette.petals.length] : color;
          b.box(offset.x, offset.y, offset.z, grainSize, 0.024 * floretScale,
            grainSize, tint, e.y, e.z, e.x, 0.045);
        }
      }
      const eye = center.clone().addScaledVector(normal, 0.022);
      b.box(eye.x, eye.y, eye.z, 0.022, 0.025, 0.022, 0xe0dfbd, e.y, e.z, e.x, 0);
    }
  }
  return b.geometry();
}

export function buildHydrangeaGarden({ THREE, BoxBuilder, world, config, material }) {
  const group = new THREE.Group();
  group.name = 'HydrangeaGarden';
  const variants = PALETTES.map(p => [0, 1, 2].map(v => ({
    near: shrubGeometry(THREE, BoxBuilder, p, v, true),
    far: shrubGeometry(THREE, BoxBuilder, p, v, false),
  })));
  // Color variants have identical shapes. Share their immutable geometry
  // attributes so GLTFExporter stores each shape once, plus separate colors.
  for (let palette = 1; palette < PALETTES.length; palette++) {
    for (let variant = 0; variant < 3; variant++) for (const level of ['near', 'far']) {
      const geometry = variants[palette][variant][level], shape = variants[0][variant][level];
      geometry.setAttribute('position', shape.getAttribute('position'));
      geometry.setAttribute('normal', shape.getAttribute('normal'));
      geometry.setIndex(shape.getIndex());
    }
  }
  const rnd = random(1012026);
  const plants = [];
  for (const [fieldIndex, field] of config.FIELDS.entries()) {
    let row = 0;
    for (let z = field.z0 + 0.85; z < field.z1 + 0.3; z += 1.27, row++) {
      // A slow density wave creates connected small groups instead of a
      // uniform nursery grid while the two garden paths remain open.
      for (let x = field.x0 + 0.85 + (row % 2) * 0.61; x < field.x1 + 0.3; x += 1.28 + Math.sin(z * 0.75) * 0.11) {
        const px = x + (rnd() - 0.5) * 0.22, pz = z + (rnd() - 0.5) * 0.20;
        if (field.x0 === -31 && Math.abs(px - pathX(pz)) < 1.0) continue;
        const scale = 0.96 + rnd() * 0.14;
        const radius = 0.77 * scale;
        let clear = true;
        for (const [dx, dz] of [[0, 0], [-radius, 0], [radius, 0], [0, -radius], [0, radius]]) {
          const t = world.i(Math.floor(px + dx), Math.floor(pz + dz));
          if (world.solid[t] || world.water[t] || world.h[t] !== config.GROUND || world.trackD[t] < 1.9) clear = false;
        }
        if (!clear) continue;
        const gradient = (px - field.x0) / (field.x1 - field.x0) + Math.sin(pz * 0.6) * 0.12;
        const paletteIndex = gradient > 0.78 && fieldIndex % 2 === 1 ? 2 : (gradient > 0.42 ? 1 : 0);
        const variant = Math.floor(rnd() * 3);
        const shrub = new THREE.Group();
        shrub.name = `Hydrangea_${PALETTES[paletteIndex].name}_${plants.length}`;
        shrub.position.set(px, config.GROUND, pz);
        shrub.rotation.y = rnd() * Math.PI * 2;
        shrub.scale.setScalar(scale);
        for (const [detail, name] of [['near', 'DetailedFlowers'], ['far', 'DistantFlowers']]) {
          const mesh = new THREE.Mesh(variants[paletteIndex][variant][detail], material);
          mesh.name = name;
          shrub.add(mesh);
        }
        group.add(shrub);
        plants.push({ x: px, z: pz, scale, palette: PALETTES[paletteIndex].name });
      }
    }
  }
  return { group, metadata: { species: 'Hydrangea macrophylla', plant_count: plants.length,
    heads_per_plant: 3, model_variants: 9, florets_per_detailed_head: 47,
    grains_per_detailed_sepal: 7, native_detail_switch_distance: 35,
    source: 'tools/railway_reference/hydrangea_garden.mjs',
    fields: config.FIELDS, plants } };
}
