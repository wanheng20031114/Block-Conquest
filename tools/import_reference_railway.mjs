// Export the reference project's actual generated geometry with Three.js 0.170.0.
// Source snapshots stay byte-for-byte unchanged; only browser canvas signs are
// adapted in an ignored runtime copy. Their text is rebuilt by Godot Label3D.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { buildCampaignStations } from './railway_reference/campaign_stations.mjs';
import { adaptReferenceFlowers, prepareHydrangeaGround, buildHydrangeaGarden } from './railway_reference/hydrangea_garden.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const snapshots = path.join(root, 'tools/railway_reference/src');
const runtime = path.join(root, '.local/railway-import/src');
const output = path.join(root, 'assets/campaign/reference_railway');
const threeRoot = path.join(root, '.local/railway-import/node_modules/three');
const THREE = await import(pathToFileURL(path.join(threeRoot, 'build/three.module.js')));
const { GLTFExporter } = await import(pathToFileURL(path.join(threeRoot, 'examples/jsm/exporters/GLTFExporter.js')));

// GLTFExporter only needs these two Blob conversions, not a browser DOM.
globalThis.FileReader = class FileReader {
  readAsArrayBuffer(blob) {
    blob.arrayBuffer().then(result => { this.result = result; this.onloadend?.(); });
  }
  readAsDataURL(blob) {
    blob.arrayBuffer().then(result => {
      this.result = `data:${blob.type};base64,${Buffer.from(result).toString('base64')}`;
      this.onloadend?.();
    });
  }
};

await fs.mkdir(runtime, { recursive: true });
await fs.mkdir(output, { recursive: true });
await fs.writeFile(path.join(runtime, 'package.json'), '{"type":"module"}\n');
const sourceFiles = ['builder.js', 'config.js', 'mesher.js', 'noise.js', 'path.js', 'props.js', 'track.js', 'train.js', 'world.js'];
const sourceHashes = {};
const grassPalette = {
  GRASS: [0x93b675, 0x85a56b], FGRASS: [0x86a86f, 0x779961],
  HILLGRASS: [0x9dbd7b, 0x8cad6d], MEADOW: [0xb5cf97, 0xa4bd88],
};
const grassHighlights = { warm: [0xc6dc62, 0xb2c58c], paleWarm: [0xe0f0a8, 0xcadbb2] };
for (const name of sourceFiles) {
  const bytes = await fs.readFile(path.join(snapshots, name));
  sourceHashes[name] = crypto.createHash('sha256').update(bytes).digest('hex');
  let source = bytes.toString('utf8');
  if (name === 'mesher.js') {
    for (const [key, [original, replacement]] of Object.entries(grassHighlights)) {
      const expected = `const ${key} = linearColor(0x${original.toString(16)});`;
      if (source.split(expected).length !== 2) throw new Error(`Reference ${key} grass highlight changed; review the palette adapter.`);
      source = source.replace(expected, `const ${key} = linearColor(0x${replacement.toString(16)});`);
    }
  }
  if (name === 'props.js') {
    source = adaptReferenceFlowers(source);
    const begin = source.indexOf('function signMesh(text, w, h,');
    const end = source.indexOf('\nfunction townStation(ctx)', begin);
    if (begin < 0 || end < 0 || !source.slice(begin, end).includes("document.createElement('canvas')")) {
      throw new Error('Reference signMesh changed; review the explicit canvas adapter before exporting.');
    }
    source = source.slice(0, begin) + `function signMesh(text, w, h, bg = '#2f5a4f', fg = '#fff4d6') {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshStandardMaterial({ color: bg, roughness: 1, metalness: 0 }));
  m.name = 'sign_' + text;
  m.userData.referenceSign = { text, width: w, height: h, bg, fg };
  return m;
}
` + source.slice(end) + '\nexport { haltPlatform };\n';
  }
  await fs.writeFile(path.join(runtime, name), source);
}

const fromRuntime = name => import(pathToFileURL(path.join(runtime, name)));
const [{ TrackPath }, { World }, { meshTerrain, meshWater }, { buildProps, haltPlatform, C }, { buildTrack }, { Train }, config, { BoxBuilder }] = await Promise.all([
  fromRuntime('path.js'), fromRuntime('world.js'), fromRuntime('mesher.js'), fromRuntime('props.js'),
  fromRuntime('track.js'), fromRuntime('train.js'), fromRuntime('config.js'), fromRuntime('builder.js'),
]);
for (const [name, colors] of Object.entries(grassPalette)) config.MAT_COLORS[config.MAT[name]] = colors;
const railPath = new TrackPath();
const world = new World(railPath);
prepareHydrangeaGround(world, config);
const material = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0 });
material.name = 'ReferenceVoxelColors';
const waterMaterial = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, metalness: 0, transparent: true, opacity: 0.86 });
waterMaterial.name = 'ReferenceWaterColors';
const terrain = new THREE.Mesh(meshTerrain(world), material);
terrain.name = 'ReferenceTerrain';
const water = new THREE.Mesh(meshWater(world), waterMaterial);
water.name = 'ReferenceWater';
const campaign = buildCampaignStations({ THREE, BoxBuilder, World, haltPlatform, C, world, path: railPath, material });
const propScene = new THREE.Scene();
const props = buildProps(world, propScene, material);
const hydrangeas = buildHydrangeaGarden({ THREE, BoxBuilder, world, config, material });
props.mesh.name = 'ReferenceBuildingsTreesFlowers';
props.dyn.group.name = 'ReferenceDynamicProps';
props.dyn.flags.forEach((flag, index) => { flag.grp.name = `ReferenceFlag${index}`; });
props.dyn.blades.forEach((blade, index) => { blade.name = `ReferenceWindmillBlades${index}`; });
if (props.dyn.fire) props.dyn.fire.name = 'ReferenceCampfire';
const track = buildTrack(world, railPath, material);
track.name = 'ReferenceTrackBridges';
world.buildWalk();
const trainScene = new THREE.Scene();
const train = new Train(trainScene, railPath, world, material);

const signs = [];
propScene.updateMatrixWorld(true);
campaign.scene.updateMatrixWorld(true);
for (const scene of [propScene, campaign.scene]) scene.traverse(object => {
  if (!object.userData.referenceSign) return;
  const position = new THREE.Vector3();
  const rotation = new THREE.Quaternion();
  const scale = new THREE.Vector3();
  object.matrixWorld.decompose(position, rotation, scale);
  signs.push({ ...object.userData.referenceSign, name: object.name, position: position.toArray(), quaternion: rotation.toArray(), scale: scale.toArray() });
});
const round = value => Math.round(value * 1e6) / 1e6;
const pathSamples = [];
for (let s = -30; s <= railPath.length + 30; s += 0.2) {
  const point = railPath.at(s);
  pathSamples.push({ s: round(s), x: round(point.x), y: round(point.y + 0.27), z: round(point.z) });
}

function geometryStats(object) {
  let meshes = 0, vertices = 0, triangles = 0;
  object.traverse(child => {
    if (!child.isMesh) return;
    meshes++;
    vertices += child.geometry.attributes.position.count;
    triangles += (child.geometry.index?.count ?? child.geometry.attributes.position.count) / 3;
  });
  const bounds = new THREE.Box3().setFromObject(object);
  return { meshes, vertices, triangles, bounds: { min: bounds.min.toArray(), max: bounds.max.toArray() } };
}

const assets = {};
const convertedMaterials = new Map();
async function exportAsset(name, object) {
  object.traverse(child => {
    if (!child.isMesh || !child.material.isMeshLambertMaterial) return;
    const original = child.material;
    if (!convertedMaterials.has(original)) {
      convertedMaterials.set(original, new THREE.MeshStandardMaterial({
        color: original.color, vertexColors: original.vertexColors,
        flatShading: original.flatShading, roughness: 1, metalness: 0,
        opacity: original.opacity, transparent: original.transparent,
        side: original.side,
      }));
    }
    child.material = convertedMaterials.get(original);
  });
  object.updateMatrixWorld(true);
  const stats = geometryStats(object);
  const buffer = await new GLTFExporter().parseAsync(object, { binary: true, onlyVisible: false });
  const bytes = Buffer.from(buffer);
  await fs.writeFile(path.join(output, name + '.glb'), bytes);
  assets[name] = { file: name + '.glb', bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), ...stats };
  console.log(`${name}: ${stats.vertices} vertices, ${stats.triangles} triangles, ${(bytes.length / 1048576).toFixed(2)} MiB`);
}

await exportAsset('terrain', terrain);
await exportAsset('water', water);
await exportAsset('props', propScene);
await exportAsset('track', track);
await exportAsset('campaign_stations', campaign.scene);
await exportAsset('hydrangeas', hydrangeas.group);
const cars = [];
for (const [index, car] of train.cars.entries()) {
  const name = `car_${String(index).padStart(2, '0')}`;
  car.group.name = name;
  car.group.position.set(0, 0, 0);
  car.group.rotation.set(0, 0, 0);
  car.group.visible = true;
  car.wheels.forEach((wheel, wheelIndex) => { wheel.name = `Wheel${wheelIndex}`; });
  cars.push({ index, file: name + '.glb', offset: car.offset, length: car.len, wheel_radius: car.r, chimney: car.chimney?.toArray() ?? null });
  await exportAsset(name, car.group);
}

const manifest = {
  source_project: 'medieval-voxel-railway', source_license: 'ISC', source_files_sha256: sourceHashes,
  importer: 'tools/import_reference_railway.mjs', three_version: THREE.REVISION,
  godot_reference: 'https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html',
  geometry_policy: 'Original TrackPath, World, meshTerrain, meshWater, buildProps, buildTrack and Train generate the source scene. Three added platforms reuse haltPlatform. At the user request, the four western flat flower rows are replaced by separate modeled hydrangea shrubs and winding garden paths; the original random streams and other scenery are preserved. Canvas signs use colored planes plus Label3D metadata. Four terrain grass materials use a muted sage palette; trees, roofs, stone, water and train colors remain original. No vertex color color-space conversion.',
  hydrangea_garden: hydrangeas.metadata,
  grass_palette: Object.fromEntries(Object.entries(grassPalette).map(([name, colors]) => [name, colors.map(color => '#' + color.toString(16).padStart(6, '0'))])),
  grass_highlights: Object.fromEntries(Object.entries(grassHighlights).map(([name, [, color]]) => [name, '#' + color.toString(16).padStart(6, '0')])),
  coordinates: { up: '+Y', train_forward: '+X', world_width: config.WT, world_depth: config.D, x_min: config.X0, x_max: config.X1, terrain_ground_y: config.GROUND, train_rail_y_offset: 0.27 },
  path: { length: railPath.length, sample_step: 0.2, samples: pathSamples },
  original_stops: train.stops,
  additional_stations: campaign.stations,
  train: { length: train.length, cars },
  signs,
  dynamics: { flags: props.dyn.flags.length, windmills: props.dyn.blades.length, chimneys: props.dyn.chimneys.map(point => point.toArray()) },
  assets,
};
await fs.writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Exported ${Object.keys(assets).length} original geometry assets; ${signs.length} signs; ${pathSamples.length} path samples.`);
