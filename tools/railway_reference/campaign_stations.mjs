// Three additional campaign stops reuse the reference's complete haltPlatform.
// This module places that exact source geometry along the original track.
export const CAMPAIGN_STATIONS = [
  { key: 'forest', name: '林间驿站', from: 94.628256, to: 106.628256, park_s: 100.628256 },
  { key: 'river', name: '河岸驿站', from: 114.628256, to: 124.128256, park_s: 122.628256 },
  { key: 'foothill', name: '山麓驿站', from: 136.5, to: 143.5, park_s: 145.833415 },
];

// Original long box faces need cross-sections before following a curve;
// otherwise a 13 m platform base would become a single chord across the bend.
// Interpolate only original attributes: no recoloring or replacement geometry.
function addCrossSections(THREE, original) {
  const positions = [], colors = [];
  const sourcePositions = original.getAttribute('position');
  const sourceColors = original.getAttribute('color');
  const vertex = index => [
    sourcePositions.getX(index), sourcePositions.getY(index), sourcePositions.getZ(index),
    sourceColors.getX(index), sourceColors.getY(index), sourceColors.getZ(index),
  ];
  const clip = (polygon, cut, keepLeft) => {
    const result = [];
    for (let index = 0; index < polygon.length; index++) {
      const a = polygon[index], b = polygon[(index + 1) % polygon.length];
      const insideA = keepLeft ? a[0] <= cut : a[0] >= cut;
      const insideB = keepLeft ? b[0] <= cut : b[0] >= cut;
      if (insideA) result.push(a);
      if (insideA !== insideB) {
        const t = (cut - a[0]) / (b[0] - a[0]);
        result.push(a.map((value, k) => value + (b[k] - value) * t));
      }
    }
    return result;
  };
  const writePolygon = polygon => {
    for (let index = 1; index + 1 < polygon.length; index++) {
      for (const item of [polygon[0], polygon[index], polygon[index + 1]]) {
        positions.push(...item.slice(0, 3));
        colors.push(...item.slice(3));
      }
    }
  };
  for (let index = 0; index < original.index.count; index += 3) {
    let remainder = [0, 1, 2].map(offset => vertex(original.index.getX(index + offset)));
    const minX = Math.min(...remainder.map(item => item[0]));
    const maxX = Math.max(...remainder.map(item => item[0]));
    for (let cut = Math.ceil((minX + 0.00001) / 0.4) * 0.4; cut < maxX - 0.00001; cut += 0.4) {
      writePolygon(clip(remainder, cut, true));
      remainder = clip(remainder, cut, false);
    }
    writePolygon(remainder);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  return geometry;
}

export function buildCampaignStations({ THREE, BoxBuilder, World, haltPlatform, C, world, path, material }) {
  const scene = new THREE.Scene();
  scene.name = 'ReferenceCampaignPlatforms';
  const stationData = [];
  for (const station of CAMPAIGN_STATIONS) {
    // Source haltPlatform performs its original occupancy changes on a real
    // isolated World. Actual placement is reserved on the main world below.
    const donor = new BoxBuilder(11);
    const donorSigns = new THREE.Group();
    haltPlatform({ b: donor, world: new World(path), dyn: { group: donorSigns } });
    const scaleAlongTrack = (station.to - station.from) / 13;
    const sourceToWorld = (x, y, z) => {
      const s = station.from + (x + 31) * scaleAlongTrack;
      const p = path.at(s);
      const side = z - 16.5;
      return new THREE.Vector3(p.x - p.dz * side, p.y + y - 8, p.z + p.dx * side);
    };
    const geometry = addCrossSections(THREE, donor.geometry());
    const positions = geometry.getAttribute('position');
    for (let index = 0; index < positions.count; index++) {
      const p = sourceToWorld(positions.getX(index), positions.getY(index), positions.getZ(index));
      positions.setXYZ(index, p.x, p.y, p.z);
    }
    positions.needsUpdate = true;
    geometry.computeVertexNormals();
    geometry.computeBoundingSphere();
    const platform = new THREE.Mesh(geometry, material);
    platform.name = `ReferencePlatform_${station.key}`;
    scene.add(platform);

    // Keep the original sign plane transform explicit so Godot can add native
    // Label3D text using the same position, orientation and effective width.
    donorSigns.updateMatrixWorld(true);
    for (const sign of [...donorSigns.children]) {
      const sourcePosition = sign.position.clone();
      const s = station.from + (sourcePosition.x + 31) * scaleAlongTrack;
      const p = path.at(s);
      sign.position.copy(sourceToWorld(sourcePosition.x, sourcePosition.y, sourcePosition.z));
      sign.rotation.y = Math.atan2(-p.dz, p.dx);
      sign.scale.x = scaleAlongTrack;
      sign.name = `sign_${station.name}`;
      sign.userData.referenceSign.text = station.name;
      scene.add(sign);
    }

    const supports = new BoxBuilder(19);
    for (let s = station.from + 0.6; s < station.to; s += 1.5) {
      const p = path.at(s);
      const yaw = Math.atan2(-p.dz, p.dx);
      for (const side of [1, 2.15]) {
        const x = p.x - p.dz * side;
        const z = p.z + p.dx * side;
        const ground = world.hAt(x, z);
        if (p.y > ground + 0.1) supports.box(x, (p.y + ground) / 2, z, 0.4, p.y - ground, 0.4, C.found, yaw);
      }
    }
    if (supports.vc > 0) {
      const piers = supports.mesh(material);
      piers.name = `ReferencePlatformPiers_${station.key}`;
      scene.add(piers);
    }

    // Reserve before original buildProps runs its vegetation pass. Existing
    // architecture is kept, and the original forest generator respects these
    // same occupancy cells when deciding where to add trees.
    for (let s = station.from - 0.5; s <= station.to + 0.5; s += 0.35) {
      const p = path.at(s);
      for (let side = 0.7; side <= 3.3; side += 0.35) {
        const x = Math.floor(p.x - p.dz * side);
        const z = Math.floor(p.z + p.dx * side);
        if (world.inside(x, z)) world.reserve(x, z, 1, 1);
      }
    }
    const park = path.at(station.park_s);
    const anchor = path.at((station.from + station.to) / 2);
    stationData.push({
      key: station.key, name: station.name, park_s: station.park_s,
      park: [park.x, park.y + 0.27, park.z],
      anchor: [anchor.x, anchor.y + 0.47, anchor.z],
      platform_s_range: [station.from, station.to],
      source_model: 'props.js:haltPlatform',
    });
  }
  return { scene, stations: stationData };
}
