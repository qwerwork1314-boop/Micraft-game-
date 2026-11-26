/* Blocklands — a procedurally generated voxel sandbox built on Three.js.
 * Plain script (no modules) so index.html also runs straight from file://.
 */
(function () {
'use strict';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const CS = 16;            // chunk size (x/z)
const H = 80;             // world height
const SEA = 24;           // sea level
const SAVE_KEY = 'blocklands-save-v1';
const DAY_LENGTH = 600;   // seconds for a full day
const REACH = 6;

const isTouch = ('ontouchstart' in window) || (window.matchMedia && matchMedia('(pointer: coarse)').matches);
const RENDER_DIST = isTouch ? 4 : 6;  // in chunks

// Block ids
const B = {
  AIR: 0, GRASS: 1, DIRT: 2, STONE: 3, COBBLE: 4, SAND: 5, LOG: 6, LEAVES: 7, PLANKS: 8,
  GLASS: 9, BRICK: 10, WATER: 11, SNOW: 12, COAL: 13, IRON: 14, BEDROCK: 15, GRAVEL: 16,
};

// Atlas tile indices
const T = {
  grassTop: 0, grassSide: 1, dirt: 2, stone: 3, cobble: 4, sand: 5, logSide: 6, logTop: 7,
  leaves: 8, planks: 9, glass: 10, brick: 11, water: 12, snow: 13, snowSide: 14, coal: 15,
  iron: 16, bedrock: 17, gravel: 18,
};

// kind: 0 opaque, 1 cutout (alpha-tested), 2 liquid
const BLOCKS = [];
function def(id, name, tiles, opts) {
  // tiles: single tile, or [top, side, bottom]
  const t = Array.isArray(tiles) ? tiles : [tiles, tiles, tiles];
  BLOCKS[id] = Object.assign({ id, name, top: t[0], side: t[1], bottom: t[2], kind: 0, solid: true, drop: id, breakable: true }, opts || {});
}
def(B.AIR, 'Air', 0, { solid: false, kind: -1 });
def(B.GRASS, 'Grass', [T.grassTop, T.grassSide, T.dirt], { drop: B.DIRT });
def(B.DIRT, 'Dirt', T.dirt);
def(B.STONE, 'Stone', T.stone, { drop: B.COBBLE });
def(B.COBBLE, 'Cobblestone', T.cobble);
def(B.SAND, 'Sand', T.sand);
def(B.LOG, 'Log', [T.logTop, T.logSide, T.logTop]);
def(B.LEAVES, 'Leaves', T.leaves, { kind: 1 });
def(B.PLANKS, 'Planks', T.planks);
def(B.GLASS, 'Glass', T.glass, { kind: 1 });
def(B.BRICK, 'Brick', T.brick);
def(B.WATER, 'Water', T.water, { kind: 2, solid: false, breakable: false });
def(B.SNOW, 'Snowy Grass', [T.snow, T.snowSide, T.dirt], { drop: B.DIRT });
def(B.COAL, 'Coal Ore', T.coal);
def(B.IRON, 'Iron Ore', T.iron);
def(B.BEDROCK, 'Bedrock', T.bedrock, { breakable: false });
def(B.GRAVEL, 'Gravel', T.gravel);

const isOpaque = (id) => id !== B.AIR && BLOCKS[id].kind === 0;
const isSolid = (id) => BLOCKS[id] && BLOCKS[id].solid;

const RECIPES = [
  { in: [[B.LOG, 1]], out: [B.PLANKS, 4] },
  { in: [[B.SAND, 2]], out: [B.GLASS, 2] },
  { in: [[B.COBBLE, 4]], out: [B.BRICK, 2] },
  { in: [[B.DIRT, 1], [B.COBBLE, 1]], out: [B.GRAVEL, 2] },
  { in: [[B.GRAVEL, 2]], out: [B.SAND, 2] },
];

// ---------------------------------------------------------------------------
// Seeded random + simplex noise
// ---------------------------------------------------------------------------
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeNoise(seed) {
  const rand = mulberry32(seed);
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  for (let i = 255; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); const t = p[i]; p[i] = p[j]; p[j] = t; }
  const perm = new Uint8Array(512);
  for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  const grad = [[1,1],[-1,1],[1,-1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]];
  const F2 = 0.5 * (Math.sqrt(3) - 1), G2 = (3 - Math.sqrt(3)) / 6;
  function noise2(xin, yin) {
    const s = (xin + yin) * F2;
    const i = Math.floor(xin + s), j = Math.floor(yin + s);
    const t = (i + j) * G2;
    const x0 = xin - (i - t), y0 = yin - (j - t);
    const i1 = x0 > y0 ? 1 : 0, j1 = x0 > y0 ? 0 : 1;
    const x1 = x0 - i1 + G2, y1 = y0 - j1 + G2;
    const x2 = x0 - 1 + 2 * G2, y2 = y0 - 1 + 2 * G2;
    const ii = i & 255, jj = j & 255;
    let n = 0;
    let t0 = 0.5 - x0 * x0 - y0 * y0;
    if (t0 > 0) { const g = grad[perm[ii + perm[jj]] & 7]; t0 *= t0; n += t0 * t0 * (g[0] * x0 + g[1] * y0); }
    let t1 = 0.5 - x1 * x1 - y1 * y1;
    if (t1 > 0) { const g = grad[perm[ii + i1 + perm[jj + j1]] & 7]; t1 *= t1; n += t1 * t1 * (g[0] * x1 + g[1] * y1); }
    let t2 = 0.5 - x2 * x2 - y2 * y2;
    if (t2 > 0) { const g = grad[perm[ii + 1 + perm[jj + 1]] & 7]; t2 *= t2; n += t2 * t2 * (g[0] * x2 + g[1] * y2); }
    return 70 * n; // ~[-1, 1]
  }
  function fbm(x, y, oct) {
    let a = 1, f = 1, sum = 0, norm = 0;
    for (let o = 0; o < oct; o++) { sum += a * noise2(x * f, y * f); norm += a; a *= 0.5; f *= 2; }
    return sum / norm;
  }
  return { noise2, fbm };
}

function hash3(x, y, z, seed) {
  let h = Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(z, 2147483647) + Math.imul(seed, 1274126177);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

// ---------------------------------------------------------------------------
// Procedural texture atlas
// ---------------------------------------------------------------------------
const TILE = 16, ATLAS_COLS = 8, ATLAS_ROWS = 3;
const atlasCanvas = document.createElement('canvas');
atlasCanvas.width = TILE * ATLAS_COLS;
atlasCanvas.height = TILE * ATLAS_ROWS;
const tileAvgColor = [];

(function buildAtlas() {
  const ctx = atlasCanvas.getContext('2d');
  const img = ctx.createImageData(atlasCanvas.width, atlasCanvas.height);
  const rnd = mulberry32(1337);
  const clamp = (v) => Math.max(0, Math.min(255, v | 0));
  function paint(tile, fn) {
    const ox = (tile % ATLAS_COLS) * TILE, oy = Math.floor(tile / ATLAS_COLS) * TILE;
    let r = 0, g = 0, b = 0, n = 0;
    for (let y = 0; y < TILE; y++) for (let x = 0; x < TILE; x++) {
      const c = fn(x, y, rnd());
      const i = ((oy + y) * atlasCanvas.width + ox + x) * 4;
      img.data[i] = clamp(c[0]); img.data[i + 1] = clamp(c[1]); img.data[i + 2] = clamp(c[2]);
      img.data[i + 3] = c.length > 3 ? c[3] : 255;
      if ((c.length > 3 ? c[3] : 255) > 0) { r += c[0]; g += c[1]; b += c[2]; n++; }
    }
    tileAvgColor[tile] = [r / n / 255, g / n / 255, b / n / 255];
  }
  const vary = (base, r, amt) => base.map((v) => v + (r - 0.5) * amt);
  const grass = (r) => vary([92, 160, 58], r, 40);
  const dirt = (r) => vary([134, 96, 67], r, 36);
  const stone = (r) => vary([128, 128, 130], r, 30);

  paint(T.grassTop, (x, y, r) => grass(r));
  paint(T.grassSide, (x, y, r) => (y < 3 || (y === 3 && r > 0.4) || (y === 4 && r > 0.8)) ? grass(r) : dirt(r));
  paint(T.dirt, (x, y, r) => dirt(r));
  paint(T.stone, (x, y, r) => r > 0.93 ? [100, 100, 104] : stone(r));
  paint(T.cobble, (x, y, r) => {
    const cx = (x + (Math.floor(y / 4) % 2) * 3) % 6, cy = y % 4;
    const edge = cx === 0 || cy === 0;
    return edge ? vary([78, 78, 82], r, 14) : vary([136, 136, 138], r, 34);
  });
  paint(T.sand, (x, y, r) => vary([222, 208, 150], r, 22));
  paint(T.logSide, (x, y, r) => {
    const stripe = (x % 4 === 0) || (x % 4 === 3 && r > 0.6);
    return stripe ? vary([82, 60, 34], r, 14) : vary([112, 84, 50], r, 20);
  });
  paint(T.logTop, (x, y, r) => {
    const d = Math.hypot(x - 7.5, y - 7.5);
    if (d > 6.8) return vary([96, 70, 40], r, 16);
    return Math.floor(d) % 2 === 0 ? vary([176, 142, 92], r, 14) : vary([150, 118, 72], r, 14);
  });
  paint(T.leaves, (x, y, r) => r < 0.16 ? [0, 0, 0, 0] : vary([56, 128, 40], r, 50));
  paint(T.planks, (x, y, r) => {
    const seam = y % 4 === 3 || (x === ((Math.floor(y / 4) * 7) % 16) && y % 4 !== 3);
    return seam ? vary([120, 88, 50], r, 10) : vary([176, 138, 84], r, 22);
  });
  paint(T.glass, (x, y, r) => {
    const border = x === 0 || y === 0 || x === 15 || y === 15;
    const shine = (x === y + 3 || x === y + 4) && x > 4 && x < 11;
    if (border) return [200, 230, 240, 255];
    if (shine) return [240, 250, 255, 200];
    return [0, 0, 0, 0];
  });
  paint(T.brick, (x, y, r) => {
    const row = Math.floor(y / 4), off = (row % 2) * 4;
    const mortar = y % 4 === 0 || (x + off) % 8 === 0;
    return mortar ? vary([196, 190, 180], r, 12) : vary([160, 70, 52], r, 26);
  });
  paint(T.water, (x, y, r) => vary([44, 104, 210], r, 24 + (Math.sin(x * 0.8 + y * 0.4) * 10)));
  paint(T.snow, (x, y, r) => vary([240, 244, 250], r, 14));
  paint(T.snowSide, (x, y, r) => (y < 3 || (y === 3 && r > 0.5)) ? vary([240, 244, 250], r, 14) : dirt(r));
  const ore = (color) => (x, y, r) => {
    const spot = hash3(Math.floor(x / 3), Math.floor(y / 3), color[0], 7) > 0.6 && r > 0.25;
    return spot ? vary(color, r, 30) : stone(r);
  };
  paint(T.coal, ore([40, 40, 40]));
  paint(T.iron, ore([214, 170, 130]));
  paint(T.bedrock, (x, y, r) => r > 0.5 ? vary([50, 50, 52], r, 20) : vary([96, 96, 98], r, 40));
  paint(T.gravel, (x, y, r) => r > 0.7 ? vary([90, 84, 80], r, 20) : vary([140, 132, 128], r, 40));
  ctx.putImageData(img, 0, 0);
})();

// Isometric item icons drawn from the atlas
const iconCache = {};
function blockIcon(id) {
  if (iconCache[id]) return iconCache[id];
  const c = document.createElement('canvas');
  c.width = c.height = 48;
  const ctx = c.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  const b = BLOCKS[id];
  const k = 22 / 16;
  const drawFace = (tile, m, shade) => {
    const l = document.createElement('canvas'); l.width = l.height = 48;
    const lc = l.getContext('2d'); lc.imageSmoothingEnabled = false;
    lc.setTransform(m[0], m[1], m[2], m[3], m[4], m[5]);
    const sx = (tile % ATLAS_COLS) * TILE, sy = Math.floor(tile / ATLAS_COLS) * TILE;
    lc.drawImage(atlasCanvas, sx, sy, TILE, TILE, 0, 0, TILE, TILE);
    if (shade) {
      lc.globalCompositeOperation = 'source-atop';
      lc.fillStyle = `rgba(0,0,0,${shade})`;
      lc.fillRect(0, 0, TILE, TILE);
    }
    ctx.drawImage(l, 0, 0);
  };
  drawFace(b.side, [k, k / 2, 0, k, 2, 13], 0.22);          // left
  drawFace(b.side, [k, -k / 2, 0, k, 24, 24], 0.42);        // right
  drawFace(b.top, [k, -k / 2, k, k / 2, 2, 13], 0);         // top
  iconCache[id] = c.toDataURL();
  return iconCache[id];
}

// ---------------------------------------------------------------------------
// Renderer / scene
// ---------------------------------------------------------------------------
let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: !isTouch, powerPreference: 'high-performance' });
} catch (e) {
  showError('WebGL is not available in this browser, so the game cannot start.');
  return;
}
renderer.setPixelRatio(Math.min(window.devicePixelRatio, isTouch ? 1.5 : 2));
renderer.setSize(window.innerWidth, window.innerHeight);
document.getElementById('game').appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.08, 1200);
camera.rotation.order = 'YXZ';
const fogFar = RENDER_DIST * CS;
scene.fog = new THREE.Fog(0x87ceeb, fogFar * 0.45, fogFar * 0.95);

const atlasTex = new THREE.CanvasTexture(atlasCanvas);
atlasTex.magFilter = THREE.NearestFilter;
atlasTex.minFilter = THREE.NearestFilter;
atlasTex.generateMipmaps = false;
atlasTex.colorSpace = THREE.SRGBColorSpace;

const solidMat = new THREE.MeshBasicMaterial({ map: atlasTex, vertexColors: true, alphaTest: 0.5 });
const waterMat = new THREE.MeshBasicMaterial({ map: atlasTex, vertexColors: true, transparent: true, opacity: 0.72, depthWrite: false, side: THREE.DoubleSide });

// Sky objects: sun, moon, stars
const skyGroup = new THREE.Group();
scene.add(skyGroup);
function discTexture(draw) {
  const c = document.createElement('canvas'); c.width = c.height = 64;
  draw(c.getContext('2d'));
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.magFilter = THREE.NearestFilter;
  return t;
}
const sunTex = discTexture((g) => {
  g.fillStyle = 'rgba(255,220,120,0.35)'; g.fillRect(0, 0, 64, 64);
  g.fillStyle = '#fff6c8'; g.fillRect(12, 12, 40, 40);
});
const moonTex = discTexture((g) => {
  g.fillStyle = '#e8ecf4'; g.fillRect(14, 14, 36, 36);
  g.fillStyle = '#c4cad6'; g.fillRect(20, 20, 8, 8); g.fillRect(34, 32, 10, 8); g.fillRect(24, 38, 6, 6);
});
const skyMat = (tex) => new THREE.MeshBasicMaterial({ map: tex, transparent: true, fog: false, depthWrite: false });
const sun = new THREE.Mesh(new THREE.PlaneGeometry(60, 60), skyMat(sunTex));
const moon = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), skyMat(moonTex));
sun.renderOrder = moon.renderOrder = -1;
skyGroup.add(sun, moon);
const starGeo = new THREE.BufferGeometry();
{
  const pts = [], r = mulberry32(99);
  for (let i = 0; i < 900; i++) {
    const u = r() * 2 - 1, th = r() * Math.PI * 2, s = Math.sqrt(1 - u * u);
    pts.push(s * Math.cos(th) * 500, Math.abs(u) * 500, s * Math.sin(th) * 500);
  }
  starGeo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
}
const starMat = new THREE.PointsMaterial({ color: 0xffffff, size: 1.6, sizeAttenuation: false, transparent: true, fog: false, depthWrite: false });
const stars = new THREE.Points(starGeo, starMat);
stars.renderOrder = -2;
skyGroup.add(stars);

// Clouds: a flat, blocky layer that drifts
const cloudTex = (() => {
  const c = document.createElement('canvas'); c.width = c.height = 64;
  const g = c.getContext('2d'); const n = makeNoise(4242);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    // seamlessly tileable: blend four offset samples
    const f = (px, py) => n.fbm(px / 14, py / 14, 3);
    const u = x / 64, w = y / 64;
    const v = f(x, y) * (1 - u) * (1 - w) + f(x - 64, y) * u * (1 - w) + f(x, y - 64) * (1 - u) * w + f(x - 64, y - 64) * u * w;
    if (v > 0.08) { g.fillStyle = '#fff'; g.fillRect(x, y, 1, 1); }
  }
  const t = new THREE.CanvasTexture(c);
  t.magFilter = THREE.NearestFilter; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(6, 6);
  return t;
})();
const cloudMat = new THREE.MeshBasicMaterial({ map: cloudTex, transparent: true, opacity: 0.8, depthWrite: false, side: THREE.DoubleSide, alphaTest: 0.1 });
const clouds = new THREE.Mesh(new THREE.PlaneGeometry(1536, 1536), cloudMat);
clouds.rotation.x = -Math.PI / 2;
clouds.position.y = H + 14;
scene.add(clouds);

// Block selection outline
const highlight = new THREE.LineSegments(
  new THREE.EdgesGeometry(new THREE.BoxGeometry(1.004, 1.004, 1.004)),
  new THREE.LineBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.6 })
);
highlight.visible = false;
scene.add(highlight);

// ---------------------------------------------------------------------------
// World
// ---------------------------------------------------------------------------
let seed, noise, edits;            // edits: Map<chunkKey, Map<index, blockId>>
const chunks = new Map();          // key -> { cx, cz, data, mesh, water, dirty }
const ckey = (cx, cz) => cx + ',' + cz;
const idx = (x, y, z) => x + z * CS + y * CS * CS;

function terrainHeight(wx, wz) {
  const base = noise.fbm(wx * 0.005, wz * 0.005, 4);
  const hills = noise.fbm(wx * 0.02 + 300, wz * 0.02 - 300, 3);
  const m = Math.max(0, noise.fbm(wx * 0.0028 - 900, wz * 0.0028 + 900, 3) + 0.1);
  const mountains = m * m * 70;
  let h = SEA + 2 + base * 12 + hills * 4 + mountains;
  return Math.max(2, Math.min(H - 12, Math.floor(h)));
}
function treeChance(wx, wz) {
  const forest = noise.fbm(wx * 0.012 + 50, wz * 0.012 + 50, 2);
  return 0.003 + Math.max(0, forest) * 0.05;
}

function generateChunk(cx, cz) {
  const data = new Uint8Array(CS * CS * H);
  const x0 = cx * CS, z0 = cz * CS;
  const heights = new Int16Array(CS * CS);
  for (let z = 0; z < CS; z++) for (let x = 0; x < CS; x++) {
    const wx = x0 + x, wz = z0 + z;
    const h = terrainHeight(wx, wz);
    heights[x + z * CS] = h;
    const beach = h <= SEA + 1;
    const snowy = h > SEA + 34;
    const rocky = h > SEA + 26 && !snowy;
    for (let y = 0; y < H; y++) {
      let id = B.AIR;
      if (y === 0) id = B.BEDROCK;
      else if (y === 1 && hash3(wx, y, wz, seed) < 0.5) id = B.BEDROCK;
      else if (y < h - 3) {
        id = B.STONE;
        const r = hash3(wx, y, wz, seed + 1);
        if (r < 0.012 && y < h - 5) id = B.COAL;
        else if (r < 0.017 && y < SEA - 4) id = B.IRON;
        else if (r > 0.994) id = B.GRAVEL;
      } else if (y < h) id = beach ? B.SAND : rocky ? B.STONE : B.DIRT;
      else if (y === h) id = beach ? (h < SEA - 2 ? B.GRAVEL : B.SAND) : snowy ? B.SNOW : rocky ? B.STONE : B.GRASS;
      else if (y <= SEA) id = B.WATER;
      data[idx(x, y, z)] = id;
    }
  }
  // Trees (may overlap from neighbouring columns, so scan a margin around the chunk)
  for (let wz = z0 - 2; wz < z0 + CS + 2; wz++) for (let wx = x0 - 2; wx < x0 + CS + 2; wx++) {
    if (hash3(wx, 0, wz, seed + 7) >= treeChance(wx, wz)) continue;
    const h = terrainHeight(wx, wz);
    if (h <= SEA + 1 || h > SEA + 26) continue;
    const trunk = 4 + Math.floor(hash3(wx, 1, wz, seed + 9) * 3);
    const top = h + trunk;
    for (let y = h + 1; y <= top + 1; y++) {
      const dy = y - top;
      const rad = dy >= 0 ? 1 : 2;
      for (let dz = -rad; dz <= rad; dz++) for (let dx = -rad; dx <= rad; dx++) {
        const lx = wx + dx - x0, lz = wz + dz - z0;
        if (lx < 0 || lz < 0 || lx >= CS || lz >= CS || y >= H) continue;
        const isTrunk = dx === 0 && dz === 0 && y <= top;
        if (isTrunk) { data[idx(lx, y, lz)] = B.LOG; continue; }
        if (y < top - 2) continue;
        if (rad === 2 && Math.abs(dx) === 2 && Math.abs(dz) === 2 && hash3(wx + dx, y, wz + dz, seed) < 0.6) continue;
        if (dy === 1 && Math.abs(dx) + Math.abs(dz) > 1) continue;
        const i = idx(lx, y, lz);
        if (data[i] === B.AIR) data[i] = B.LEAVES;
      }
    }
    // grass under trunk becomes dirt
    const lx = wx - x0, lz = wz - z0;
    if (lx >= 0 && lz >= 0 && lx < CS && lz < CS) data[idx(lx, h, lz)] = B.DIRT;
  }
  // Apply player edits
  const e = edits.get(ckey(cx, cz));
  if (e) e.forEach((id, i) => { data[i] = id; });
  return data;
}

function getBlock(wx, wy, wz) {
  if (wy < 0) return B.BEDROCK;
  if (wy >= H) return B.AIR;
  const cx = Math.floor(wx / CS), cz = Math.floor(wz / CS);
  const c = chunks.get(ckey(cx, cz));
  if (!c) return B.AIR;
  return c.data[idx(wx - cx * CS, wy, wz - cz * CS)];
}

function setBlock(wx, wy, wz, id) {
  if (wy < 0 || wy >= H) return false;
  const cx = Math.floor(wx / CS), cz = Math.floor(wz / CS);
  const key = ckey(cx, cz);
  const c = chunks.get(key);
  if (!c) return false;
  const lx = wx - cx * CS, lz = wz - cz * CS;
  const i = idx(lx, wy, lz);
  c.data[i] = id;
  if (!edits.has(key)) edits.set(key, new Map());
  edits.get(key).set(i, id);
  markDirty(cx, cz);
  if (lx === 0) markDirty(cx - 1, cz);
  if (lx === CS - 1) markDirty(cx + 1, cz);
  if (lz === 0) markDirty(cx, cz - 1);
  if (lz === CS - 1) markDirty(cx, cz + 1);
  saveDirty = true;
  return true;
}
function markDirty(cx, cz) { const c = chunks.get(ckey(cx, cz)); if (c) c.dirty = true; }

// --- Meshing ---------------------------------------------------------------
// Each face: normal, 4 corners (BL, BR, TR, TL as seen from outside), tile slot
const FACES = [
  { n: [1, 0, 0],  c: [[1,0,1],[1,0,0],[1,1,0],[1,1,1]], t: 'side',   shade: 0.80 },
  { n: [-1, 0, 0], c: [[0,0,0],[0,0,1],[0,1,1],[0,1,0]], t: 'side',   shade: 0.80 },
  { n: [0, 1, 0],  c: [[0,1,1],[1,1,1],[1,1,0],[0,1,0]], t: 'top',    shade: 1.00 },
  { n: [0, -1, 0], c: [[0,0,0],[1,0,0],[1,0,1],[0,0,1]], t: 'bottom', shade: 0.50 },
  { n: [0, 0, 1],  c: [[0,0,1],[1,0,1],[1,1,1],[0,1,1]], t: 'side',   shade: 0.65 },
  { n: [0, 0, -1], c: [[1,0,0],[0,0,0],[0,1,0],[1,1,0]], t: 'side',   shade: 0.65 },
];
const AO_LEVELS = [0.45, 0.62, 0.8, 1.0];
const UVS = [[0, 0], [1, 0], [1, 1], [0, 1]];

function faceVisible(self, nb) {
  if (nb === B.AIR) return true;
  if (self === B.WATER) return nb !== B.WATER && !isOpaque(nb);
  if (nb === B.WATER) return true;
  const k = BLOCKS[nb].kind;
  if (k === 1) return !(self === B.GLASS && nb === B.GLASS);
  return false;
}

function buildChunkMesh(c) {
  const x0 = c.cx * CS, z0 = c.cz * CS;
  const out = [{ pos: [], uv: [], col: [], ind: [] }, { pos: [], uv: [], col: [], ind: [] }];
  const eps = 0.5 / (TILE * ATLAS_COLS) * 0.02;
  const tw = 1 / ATLAS_COLS, th = 1 / ATLAS_ROWS;
  // Local accessor that reads neighbours from adjacent chunks quickly
  const get = (x, y, z) => {
    if (y < 0) return B.BEDROCK;
    if (y >= H) return B.AIR;
    if (x >= 0 && x < CS && z >= 0 && z < CS) return c.data[idx(x, y, z)];
    return getBlock(x0 + x, y, z0 + z);
  };
  for (let y = 0; y < H; y++) for (let z = 0; z < CS; z++) for (let x = 0; x < CS; x++) {
    const id = c.data[idx(x, y, z)];
    if (id === B.AIR) continue;
    const blk = BLOCKS[id];
    const target = blk.kind === 2 ? out[1] : out[0];
    const waterTop = id === B.WATER && get(x, y + 1, z) !== B.WATER;
    for (let f = 0; f < 6; f++) {
      const F = FACES[f];
      const nx = x + F.n[0], ny = y + F.n[1], nz = z + F.n[2];
      const nb = get(nx, ny, nz);
      if (!faceVisible(id, nb)) continue;
      const tile = blk[F.t];
      const u0 = (tile % ATLAS_COLS) * tw, v0 = 1 - (Math.floor(tile / ATLAS_COLS) + 1) * th;
      const base = target.pos.length / 3;
      // tangent axes for AO
      const na = F.n[0] !== 0 ? 0 : F.n[1] !== 0 ? 1 : 2;
      const ta = na === 0 ? 1 : 0, tb = na === 2 ? 1 : 2;
      const ao = [0, 0, 0, 0];
      for (let v = 0; v < 4; v++) {
        const cc = F.c[v];
        let light = 3;
        if (blk.kind !== 2) {
          const p = [nx, ny, nz];
          const s1 = cc[ta] ? 1 : -1, s2 = cc[tb] ? 1 : -1;
          const a = p.slice(); a[ta] += s1;
          const b = p.slice(); b[tb] += s2;
          const d = p.slice(); d[ta] += s1; d[tb] += s2;
          const side1 = isOpaque(get(a[0], a[1], a[2])) ? 1 : 0;
          const side2 = isOpaque(get(b[0], b[1], b[2])) ? 1 : 0;
          const corner = isOpaque(get(d[0], d[1], d[2])) ? 1 : 0;
          light = side1 && side2 ? 0 : 3 - (side1 + side2 + corner);
        }
        ao[v] = light;
        let vy = y + cc[1];
        if (waterTop && cc[1] === 1) vy -= 0.12;
        target.pos.push(x0 + x + cc[0], vy, z0 + z + cc[2]);
        target.uv.push(u0 + (UVS[v][0] ? tw - eps : eps), v0 + (UVS[v][1] ? th - eps : eps));
        const br = F.shade * AO_LEVELS[light];
        target.col.push(br, br, br);
      }
      if (ao[0] + ao[2] < ao[1] + ao[3]) target.ind.push(base + 1, base + 2, base + 3, base + 1, base + 3, base);
      else target.ind.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
  }
  const make = (o, mat, old) => {
    if (old) { scene.remove(old); old.geometry.dispose(); }
    if (!o.ind.length) return null;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(o.pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(o.uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(o.col, 3));
    g.setIndex(o.ind);
    g.computeBoundingSphere();
    const m = new THREE.Mesh(g, mat);
    m.matrixAutoUpdate = false;
    scene.add(m);
    return m;
  };
  c.mesh = make(out[0], solidMat, c.mesh);
  c.water = make(out[1], waterMat, c.water);
  if (c.water) c.water.renderOrder = 1;
  c.dirty = false;
  c.built = true;
}

function disposeChunk(c) {
  for (const m of [c.mesh, c.water]) if (m) { scene.remove(m); m.geometry.dispose(); }
}

function updateChunks(budgetMs) {
  const pcx = Math.floor(player.pos.x / CS), pcz = Math.floor(player.pos.z / CS);
  const start = performance.now();
  // 1. unload far chunks
  for (const [k, c] of chunks) {
    if (Math.abs(c.cx - pcx) > RENDER_DIST + 2 || Math.abs(c.cz - pcz) > RENDER_DIST + 2) {
      disposeChunk(c); chunks.delete(k);
    }
  }
  // 2. collect needed chunks nearest-first
  const want = [];
  const R = RENDER_DIST + 1;
  for (let dz = -R; dz <= R; dz++) for (let dx = -R; dx <= R; dx++) {
    if (dx * dx + dz * dz > R * R + 1) continue;
    want.push([pcx + dx, pcz + dz, dx * dx + dz * dz]);
  }
  want.sort((a, b) => a[2] - b[2]);
  for (const [cx, cz] of want) {
    if (performance.now() - start > budgetMs) return;
    const k = ckey(cx, cz);
    if (!chunks.has(k)) chunks.set(k, { cx, cz, data: generateChunk(cx, cz), mesh: null, water: null, dirty: true, built: false });
  }
  // 3. build meshes inside render distance when neighbours exist
  const RR = RENDER_DIST;
  for (const [cx, cz, d] of want) {
    if (d > RR * RR + 1) continue;
    const c = chunks.get(ckey(cx, cz));
    if (!c || !c.dirty) continue;
    if (!chunks.has(ckey(cx + 1, cz)) || !chunks.has(ckey(cx - 1, cz)) || !chunks.has(ckey(cx, cz + 1)) || !chunks.has(ckey(cx, cz - 1))) continue;
    // Edited chunks near the player are rebuilt immediately, others obey the budget
    if (c.built && performance.now() - start > budgetMs + 8) return;
    if (!c.built && performance.now() - start > budgetMs) return;
    buildChunkMesh(c);
  }
}

// ---------------------------------------------------------------------------
// Player
// ---------------------------------------------------------------------------
const player = {
  pos: new THREE.Vector3(0, 60, 0), vel: new THREE.Vector3(),
  yaw: 0, pitch: 0, onGround: false, flying: false, inWater: false,
  w: 0.3, h: 1.8, eye: 1.62,
};

function collides(px, py, pz) {
  const minX = Math.floor(px - player.w), maxX = Math.floor(px + player.w);
  const minY = Math.floor(py), maxY = Math.floor(py + player.h);
  const minZ = Math.floor(pz - player.w), maxZ = Math.floor(pz + player.w);
  for (let y = minY; y <= maxY; y++) for (let z = minZ; z <= maxZ; z++) for (let x = minX; x <= maxX; x++) {
    if (isSolid(getBlock(x, y, z))) return true;
  }
  return false;
}

function moveAxis(axis, amount) {
  if (amount === 0) return false;
  const p = player.pos;
  p[axis] += amount;
  if (!collides(p.x, p.y, p.z)) return false;
  // binary-ish resolution: snap to the block boundary
  const e = 0.001;
  if (axis === 'y') {
    if (amount > 0) p.y = Math.floor(p.y + player.h) - player.h - e;
    else p.y = Math.floor(p.y) + 1 + e;
  } else {
    if (amount > 0) p[axis] = Math.floor(p[axis] + player.w) - player.w - e;
    else p[axis] = Math.floor(p[axis] - player.w) + 1 + player.w + e;
  }
  if (collides(p.x, p.y, p.z)) p[axis] -= amount; // fallback: undo
  return true;
}

function findSpawn() {
  for (let r = 0; r < 400; r += 4) {
    for (let a = 0; a < 8; a++) {
      const x = Math.round(Math.cos(a / 8 * Math.PI * 2) * r), z = Math.round(Math.sin(a / 8 * Math.PI * 2) * r);
      const h = terrainHeight(x, z);
      if (h <= SEA + 1 || h >= SEA + 20) continue;
      let ok = true;
      for (let b = -3; b <= 3 && ok; b++) for (let a = -3; a <= 3 && ok; a++) {
        if (Math.abs(a) <= 2 && Math.abs(b) <= 2 && terrainHeight(x + a, z + b) !== h) ok = false;
        if (hash3(x + a, 0, z + b, seed + 7) < treeChance(x + a, z + b)) ok = false;
      }
      if (ok) return new THREE.Vector3(x + 0.5, h + 1.01, z + 0.5);
    }
  }
  return new THREE.Vector3(0.5, terrainHeight(0, 0) + 2, 0.5);
}

// ---------------------------------------------------------------------------
// Inventory
// ---------------------------------------------------------------------------
const MAX_STACK = 64;
let slots = new Array(36).fill(null);  // 0-8 hotbar, 9-35 backpack
let selected = 0;

function addItem(id, n) {
  for (let i = 0; i < 36 && n > 0; i++) {
    const s = slots[i];
    if (s && s.id === id && s.count < MAX_STACK) { const m = Math.min(n, MAX_STACK - s.count); s.count += m; n -= m; }
  }
  for (let i = 0; i < 36 && n > 0; i++) {
    if (!slots[i]) { const m = Math.min(n, MAX_STACK); slots[i] = { id, count: m }; n -= m; }
  }
  refreshInventoryUI();
  return n === 0;
}
function countItem(id) { return slots.reduce((a, s) => a + (s && s.id === id ? s.count : 0), 0); }
function removeItem(id, n) {
  for (let i = 35; i >= 0 && n > 0; i--) {
    const s = slots[i];
    if (s && s.id === id) { const m = Math.min(n, s.count); s.count -= m; n -= m; if (!s.count) slots[i] = null; }
  }
  refreshInventoryUI();
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const hud = $('hud'), menu = $('menu'), invEl = $('inventory'), touchEl = $('touch');
let pickedSlot = -1;
let toastTimer = 0;

function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 1400);
}

function slotEl(i, cls) {
  const d = document.createElement('div');
  d.className = 'slot ' + (cls || '');
  d.dataset.i = i;
  const s = slots[i];
  if (s) {
    const img = document.createElement('img'); img.src = blockIcon(s.id); img.alt = BLOCKS[s.id].name; img.title = BLOCKS[s.id].name;
    d.appendChild(img);
    if (s.count > 1) { const c = document.createElement('span'); c.className = 'count'; c.textContent = s.count; d.appendChild(c); }
  }
  return d;
}

function refreshHotbar() {
  const hb = $('hotbar'); hb.innerHTML = '';
  for (let i = 0; i < 9; i++) {
    const d = slotEl(i, i === selected ? 'active' : '');
    d.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); selectSlot(i); });
    hb.appendChild(d);
  }
}
function selectSlot(i) {
  selected = (i + 9) % 9; refreshHotbar();
  const s = slots[selected]; if (s) toast(BLOCKS[s.id].name);
}

function refreshInventoryUI() {
  refreshHotbar();
  if (invEl.classList.contains('hidden')) return;
  const grid = $('invGrid'), hb = $('invHotbar');
  grid.innerHTML = ''; hb.innerHTML = '';
  const onClick = (i) => () => {
    if (pickedSlot < 0) { if (slots[i]) pickedSlot = i; }
    else if (pickedSlot === i) pickedSlot = -1;
    else {
      const a = slots[pickedSlot], b = slots[i];
      if (a && b && a.id === b.id) {
        const m = Math.min(a.count, MAX_STACK - b.count); b.count += m; a.count -= m;
        if (!a.count) slots[pickedSlot] = null;
      } else { slots[pickedSlot] = b; slots[i] = a; }
      pickedSlot = -1; saveDirty = true;
    }
    refreshInventoryUI();
  };
  for (let i = 9; i < 36; i++) { const d = slotEl(i, i === pickedSlot ? 'picked' : ''); d.onclick = onClick(i); grid.appendChild(d); }
  for (let i = 0; i < 9; i++) { const d = slotEl(i, (i === pickedSlot ? 'picked ' : '') + (i === selected ? 'active' : '')); d.onclick = onClick(i); hb.appendChild(d); }
  const rec = $('recipes'); rec.innerHTML = '';
  RECIPES.forEach((r) => {
    const btn = document.createElement('button'); btn.className = 'recipe';
    const ok = r.in.every(([id, n]) => countItem(id) >= n);
    btn.disabled = !ok;
    const parts = r.in.map(([id, n]) => `<img src="${blockIcon(id)}" alt="">${n}`).join(' + ');
    btn.innerHTML = `${parts} &rarr; <img src="${blockIcon(r.out[0])}" alt="">${r.out[1]} ${BLOCKS[r.out[0]].name}`;
    btn.onclick = () => {
      if (!r.in.every(([id, n]) => countItem(id) >= n)) return;
      r.in.forEach(([id, n]) => removeItem(id, n));
      addItem(r.out[0], r.out[1]); saveDirty = true;
    };
    rec.appendChild(btn);
  });
}

let state = 'menu'; // 'menu' | 'play' | 'inventory'
function openInventory() {
  state = 'inventory'; pickedSlot = -1;
  invEl.classList.remove('hidden');
  if (document.pointerLockElement) document.exitPointerLock();
  refreshInventoryUI();
}
function closeInventory() {
  invEl.classList.add('hidden');
  resumePlay();
}
function showMenu(paused) {
  state = 'menu';
  menu.classList.remove('hidden');
  hud.classList.add('hidden');
  touchEl.classList.add('hidden');
  $('playBtn').textContent = paused ? 'Resume' : 'Play';
  $('menuSub').textContent = paused ? 'Paused' : 'A procedurally generated voxel sandbox';
  $('seedLabel').textContent = 'World seed: ' + seed;
  save();
}
function resumePlay() {
  state = 'play';
  menu.classList.add('hidden');
  invEl.classList.add('hidden');
  hud.classList.remove('hidden');
  if (isTouch) touchEl.classList.remove('hidden');
  else renderer.domElement.requestPointerLock && renderer.domElement.requestPointerLock();
  clock.getDelta();
}
function showError(msg) {
  const e = document.getElementById('error');
  e.innerHTML = `<div class="panel"><h2>Can't start</h2><p>${msg}</p></div>`;
  e.classList.remove('hidden');
  document.getElementById('menu').classList.add('hidden');
}
if (isTouch) document.body.classList.add('touch');

$('playBtn').onclick = () => resumePlay();
$('newBtn').onclick = () => {
  if (!confirm('Start a new world? Your current world will be replaced.')) return;
  newWorld(Math.floor(Math.random() * 1e9));
  resumePlay();
};
$('invClose').onclick = () => closeInventory();
invEl.addEventListener('pointerdown', (e) => { if (e.target === invEl) closeInventory(); });

// ---------------------------------------------------------------------------
// Input: keyboard & mouse
// ---------------------------------------------------------------------------
const keys = {};
const input = { fwd: 0, strafe: 0, jump: false, down: false, sprint: false };

document.addEventListener('keydown', (e) => {
  if (e.code === 'KeyE') {
    if (state === 'play') openInventory(); else if (state === 'inventory') closeInventory();
    return;
  }
  if (e.code === 'Escape' && state === 'inventory') { closeInventory(); return; }
  if (state !== 'play') return;
  keys[e.code] = true;
  if (e.code === 'KeyF') toggleFly();
  if (e.code === 'KeyT') { timeOfDay = (timeOfDay + 0.125) % 1; toast('Time skipped'); }
  if (e.code.startsWith('Digit')) { const n = +e.code.slice(5); if (n >= 1 && n <= 9) selectSlot(n - 1); }
  if (e.code === 'Space') e.preventDefault();
});
document.addEventListener('keyup', (e) => { keys[e.code] = false; });
window.addEventListener('blur', () => { for (const k in keys) keys[k] = false; });

document.addEventListener('pointerlockchange', () => {
  if (!document.pointerLockElement && state === 'play' && !isTouch) showMenu(true);
});
document.addEventListener('mousemove', (e) => {
  if (state !== 'play' || !document.pointerLockElement) return;
  look(e.movementX * 0.0022, e.movementY * 0.0022);
});
renderer.domElement.addEventListener('mousedown', (e) => {
  if (state !== 'play' || isTouch) return;
  if (!document.pointerLockElement) { renderer.domElement.requestPointerLock(); return; }
  if (e.button === 0) breakBlock();
  else if (e.button === 2) placeBlock();
});
renderer.domElement.addEventListener('contextmenu', (e) => e.preventDefault());
window.addEventListener('wheel', (e) => { if (state === 'play') selectSlot(selected + (e.deltaY > 0 ? 1 : -1)); }, { passive: true });

function look(dx, dy) {
  player.yaw -= dx;
  player.pitch = Math.max(-Math.PI / 2 + 0.01, Math.min(Math.PI / 2 - 0.01, player.pitch - dy));
}
function toggleFly() {
  player.flying = !player.flying; player.vel.y = 0;
  $('tFly').classList.toggle('on', player.flying);
  toast(player.flying ? 'Flying on' : 'Flying off');
}

// ---------------------------------------------------------------------------
// Input: touch
// ---------------------------------------------------------------------------
const touch = { joyId: null, joyX: 0, joyY: 0, lookId: null, lastX: 0, lastY: 0, mx: 0, my: 0, jump: false, down: false };
const joyBase = $('joyBase'), joyKnob = $('joyKnob');
const JOY_R = 50;

function bindHold(el, onDown, onUp) {
  el.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); el.classList.add('pressed'); onDown && onDown(); }, { passive: false });
  const up = (e) => { e.preventDefault(); el.classList.remove('pressed'); onUp && onUp(); };
  el.addEventListener('touchend', up, { passive: false });
  el.addEventListener('touchcancel', up, { passive: false });
}
let breakTimer = null;
bindHold($('tJump'), () => { touch.jump = true; }, () => { touch.jump = false; });
bindHold($('tDown'), () => { touch.down = true; }, () => { touch.down = false; });
bindHold($('tBreak'), () => { breakBlock(); clearInterval(breakTimer); breakTimer = setInterval(breakBlock, 280); }, () => clearInterval(breakTimer));
bindHold($('tPlace'), () => placeBlock());
bindHold($('tFly'), () => toggleFly());
bindHold($('tInv'), () => openInventory());
bindHold($('tPause'), () => showMenu(true));

touchEl.addEventListener('touchstart', (e) => {
  e.preventDefault();
  for (const t of e.changedTouches) {
    if (t.clientX < window.innerWidth * 0.45 && touch.joyId === null) {
      touch.joyId = t.identifier; touch.joyX = t.clientX; touch.joyY = t.clientY;
      joyBase.style.display = 'block';
      joyBase.style.left = (t.clientX - 60) + 'px'; joyBase.style.top = (t.clientY - 60) + 'px';
      joyKnob.style.transform = 'translate(0,0)';
      touch.mx = touch.my = 0;
    } else if (touch.lookId === null) {
      touch.lookId = t.identifier; touch.lastX = t.clientX; touch.lastY = t.clientY;
    }
  }
}, { passive: false });
touchEl.addEventListener('touchmove', (e) => {
  e.preventDefault();
  for (const t of e.changedTouches) {
    if (t.identifier === touch.joyId) {
      let dx = t.clientX - touch.joyX, dy = t.clientY - touch.joyY;
      const len = Math.hypot(dx, dy);
      if (len > JOY_R) { dx *= JOY_R / len; dy *= JOY_R / len; }
      joyKnob.style.transform = `translate(${dx}px,${dy}px)`;
      touch.mx = dx / JOY_R; touch.my = dy / JOY_R;
    } else if (t.identifier === touch.lookId) {
      look((t.clientX - touch.lastX) * 0.006, (t.clientY - touch.lastY) * 0.006);
      touch.lastX = t.clientX; touch.lastY = t.clientY;
    }
  }
}, { passive: false });
const touchEnd = (e) => {
  for (const t of e.changedTouches) {
    if (t.identifier === touch.joyId) { touch.joyId = null; touch.mx = touch.my = 0; joyBase.style.display = 'none'; }
    if (t.identifier === touch.lookId) touch.lookId = null;
  }
};
touchEl.addEventListener('touchend', touchEnd);
touchEl.addEventListener('touchcancel', touchEnd);
document.addEventListener('gesturestart', (e) => e.preventDefault());

// ---------------------------------------------------------------------------
// Block interaction
// ---------------------------------------------------------------------------
const tmpDir = new THREE.Vector3();
function raycast() {
  camera.getWorldDirection(tmpDir);
  const o = camera.position;
  let x = Math.floor(o.x), y = Math.floor(o.y), z = Math.floor(o.z);
  const dx = tmpDir.x, dy = tmpDir.y, dz = tmpDir.z;
  const sx = Math.sign(dx), sy = Math.sign(dy), sz = Math.sign(dz);
  const tdx = dx !== 0 ? Math.abs(1 / dx) : Infinity, tdy = dy !== 0 ? Math.abs(1 / dy) : Infinity, tdz = dz !== 0 ? Math.abs(1 / dz) : Infinity;
  let tmx = dx > 0 ? (x + 1 - o.x) * tdx : dx < 0 ? (o.x - x) * tdx : Infinity;
  let tmy = dy > 0 ? (y + 1 - o.y) * tdy : dy < 0 ? (o.y - y) * tdy : Infinity;
  let tmz = dz > 0 ? (z + 1 - o.z) * tdz : dz < 0 ? (o.z - z) * tdz : Infinity;
  let n = [0, 0, 0], t = 0;
  while (t <= REACH) {
    const id = getBlock(x, y, z);
    if (id !== B.AIR && id !== B.WATER) return { x, y, z, id, n };
    if (tmx < tmy && tmx < tmz) { x += sx; t = tmx; tmx += tdx; n = [-sx, 0, 0]; }
    else if (tmy < tmz) { y += sy; t = tmy; tmy += tdy; n = [0, -sy, 0]; }
    else { z += sz; t = tmz; tmz += tdz; n = [0, 0, -sz]; }
  }
  return null;
}

function breakBlock() {
  if (state !== 'play') return;
  const hit = raycast();
  if (!hit) return;
  const b = BLOCKS[hit.id];
  if (!b.breakable) { toast(b.name + ' cannot be broken'); return; }
  // water flows into the hole if adjacent (simple: fill if any horizontal/above neighbour is water)
  const nearWater = [[1,0,0],[-1,0,0],[0,0,1],[0,0,-1],[0,1,0]].some(([a, bb, c]) => getBlock(hit.x + a, hit.y + bb, hit.z + c) === B.WATER);
  setBlock(hit.x, hit.y, hit.z, nearWater ? B.WATER : B.AIR);
  spawnParticles(hit.x, hit.y, hit.z, b.side);
  if (b.drop !== B.LEAVES || Math.random() < 0.5) addItem(b.drop, 1);
}

function placeBlock() {
  if (state !== 'play') return;
  const s = slots[selected];
  if (!s) { toast('Nothing selected'); return; }
  const hit = raycast();
  if (!hit) return;
  const x = hit.x + hit.n[0], y = hit.y + hit.n[1], z = hit.z + hit.n[2];
  if (y < 0 || y >= H) return;
  const cur = getBlock(x, y, z);
  if (cur !== B.AIR && cur !== B.WATER) return;
  // don't place inside the player
  const p = player.pos;
  if (isSolid(s.id) && x + 1 > p.x - player.w && x < p.x + player.w && z + 1 > p.z - player.w && z < p.z + player.w && y + 1 > p.y && y < p.y + player.h) return;
  if (setBlock(x, y, z, s.id)) {
    s.count--; if (!s.count) slots[selected] = null;
    refreshInventoryUI();
  }
}

// Break particles
const particles = [];
const particleGeo = new THREE.BoxGeometry(0.12, 0.12, 0.12);
const particleMats = {};
function spawnParticles(x, y, z, tile) {
  if (!particleMats[tile]) {
    const c = tileAvgColor[tile];
    particleMats[tile] = new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(c[0], c[1], c[2], THREE.SRGBColorSpace) });
  }
  for (let i = 0; i < 10; i++) {
    const m = new THREE.Mesh(particleGeo, particleMats[tile]);
    m.position.set(x + 0.2 + Math.random() * 0.6, y + 0.2 + Math.random() * 0.6, z + 0.2 + Math.random() * 0.6);
    m.userData.v = new THREE.Vector3((Math.random() - 0.5) * 3, Math.random() * 3 + 1, (Math.random() - 0.5) * 3);
    m.userData.life = 0.5 + Math.random() * 0.4;
    scene.add(m); particles.push(m);
  }
}
function updateParticles(dt) {
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.userData.life -= dt;
    p.userData.v.y -= 18 * dt;
    p.position.addScaledVector(p.userData.v, dt);
    p.scale.setScalar(Math.max(0.01, p.userData.life * 1.6));
    if (p.userData.life <= 0) { scene.remove(p); particles.splice(i, 1); }
  }
}

// ---------------------------------------------------------------------------
// Day / night
// ---------------------------------------------------------------------------
let timeOfDay = 0.3; // 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
const cDay = new THREE.Color(0x87ceeb), cNight = new THREE.Color(0x070b1d), cDusk = new THREE.Color(0xf08a4b);
const skyColor = new THREE.Color();
function updateSky(dt) {
  timeOfDay = (timeOfDay + dt / DAY_LENGTH) % 1;
  const ang = (timeOfDay - 0.25) * Math.PI * 2;  // sun angle above horizon
  const sunH = Math.sin(ang);
  const day = THREE.MathUtils.smoothstep(sunH, -0.18, 0.25);
  skyColor.copy(cNight).lerp(cDay, day);
  const dusk = Math.max(0, 1 - Math.abs(sunH) / 0.28) * 0.55;
  skyColor.lerp(cDusk, dusk);
  // underwater tint
  const eyeBlock = getBlock(Math.floor(camera.position.x), Math.floor(camera.position.y), Math.floor(camera.position.z));
  const under = eyeBlock === B.WATER;
  if (under) {
    skyColor.setRGB(0.05, 0.18, 0.42).multiplyScalar(0.3 + 0.7 * day);
    scene.fog.near = 1; scene.fog.far = 24;
  } else { scene.fog.near = fogFar * 0.45; scene.fog.far = fogFar * 0.95; }
  renderer.setClearColor(skyColor);
  scene.fog.color.copy(skyColor);
  const light = 0.18 + 0.82 * day;
  solidMat.color.setScalar(light);
  waterMat.color.setScalar(light);
  cloudMat.color.setScalar(0.25 + 0.75 * day);
  starMat.opacity = 1 - day;
  skyGroup.position.copy(camera.position);
  const dir = new THREE.Vector3(Math.cos(ang), Math.sin(ang), 0.25).normalize();
  sun.position.copy(dir).multiplyScalar(400); sun.lookAt(camera.position);
  moon.position.copy(dir).multiplyScalar(-400); moon.lookAt(camera.position);
  stars.rotation.z = ang;
  const snap = (v) => v - (((v % 256) + 256) % 256);
  clouds.position.x = snap(camera.position.x);
  clouds.position.z = snap(camera.position.z);
  cloudTex.offset.x += dt * 0.0008;
}

// ---------------------------------------------------------------------------
// Save / load
// ---------------------------------------------------------------------------
let saveDirty = false;
function save() {
  try {
    const e = {};
    edits.forEach((m, k) => { e[k] = Array.from(m.entries()); });
    localStorage.setItem(SAVE_KEY, JSON.stringify({
      seed, edits: e, slots, selected, time: timeOfDay, flying: player.flying,
      pos: [player.pos.x, player.pos.y, player.pos.z], yaw: player.yaw, pitch: player.pitch,
    }));
    saveDirty = false;
  } catch (err) { /* storage unavailable — game still works, just not persisted */ }
}
function load() {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (err) { return null; }
}
function starterKit() {
  slots = new Array(36).fill(null);
  [[B.PLANKS, 32], [B.GLASS, 16], [B.BRICK, 16], [B.COBBLE, 16], [B.LOG, 8]].forEach(([id, n]) => addItem(id, n));
}
function newWorld(s) {
  for (const c of chunks.values()) disposeChunk(c);
  chunks.clear();
  seed = s; noise = makeNoise(seed); edits = new Map();
  player.pos.copy(findSpawn()); player.vel.set(0, 0, 0); player.yaw = 0; player.pitch = 0; player.flying = false;
  timeOfDay = 0.3; selected = 0;
  starterKit();
  save();
}
(function init() {
  const s = load();
  if (s && typeof s.seed === 'number') {
    seed = s.seed; noise = makeNoise(seed); edits = new Map();
    Object.keys(s.edits || {}).forEach((k) => edits.set(k, new Map(s.edits[k])));
    slots = Array.isArray(s.slots) && s.slots.length === 36 ? s.slots : new Array(36).fill(null);
    selected = s.selected || 0; timeOfDay = s.time || 0.3; player.flying = !!s.flying;
    if (s.pos) player.pos.set(s.pos[0], s.pos[1], s.pos[2]); else player.pos.copy(findSpawn());
    player.yaw = s.yaw || 0; player.pitch = s.pitch || 0;
  } else newWorld(Math.floor(Math.random() * 1e9));
  $('tFly').classList.toggle('on', player.flying);
  $('seedLabel').textContent = 'World seed: ' + seed;
  refreshHotbar();
})();
setInterval(() => { if (saveDirty) save(); }, 5000);
window.addEventListener('pagehide', save);
document.addEventListener('visibilitychange', () => { if (document.hidden) { save(); if (state === 'play' && isTouch) showMenu(true); } });

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------
const clock = new THREE.Clock();
const fwd = new THREE.Vector3(), right = new THREE.Vector3(), wish = new THREE.Vector3();
let fpsAcc = 0, fpsFrames = 0, fps = 0;

function updatePlayer(dt) {
  // Gather input
  let mf = 0, ms = 0;
  if (keys.KeyW || keys.ArrowUp) mf += 1;
  if (keys.KeyS || keys.ArrowDown) mf -= 1;
  if (keys.KeyD || keys.ArrowRight) ms += 1;
  if (keys.KeyA || keys.ArrowLeft) ms -= 1;
  mf -= touch.my; ms += touch.mx;
  const jump = keys.Space || touch.jump;
  const down = keys.ShiftLeft || keys.ShiftRight || touch.down;
  const sprint = keys.ControlLeft || keys.ControlRight || Math.hypot(touch.mx, touch.my) > 0.95;

  fwd.set(-Math.sin(player.yaw), 0, -Math.cos(player.yaw));
  right.set(Math.cos(player.yaw), 0, -Math.sin(player.yaw));
  wish.set(0, 0, 0).addScaledVector(fwd, mf).addScaledVector(right, ms);
  if (wish.lengthSq() > 1) wish.normalize();

  const feet = getBlock(Math.floor(player.pos.x), Math.floor(player.pos.y + 0.4), Math.floor(player.pos.z));
  player.inWater = feet === B.WATER;
  let speed = player.flying ? (sprint ? 16 : 10) : sprint ? 5.8 : 4.3;
  if (player.inWater && !player.flying) speed *= 0.55;
  if (down && !player.flying && player.onGround) speed *= 0.4;

  // Horizontal velocity with a little acceleration smoothing
  const accel = player.onGround || player.flying ? 14 : 4;
  const k = Math.min(1, accel * dt);
  player.vel.x += (wish.x * speed - player.vel.x) * k;
  player.vel.z += (wish.z * speed - player.vel.z) * k;

  if (player.flying) {
    const vy = (jump ? 1 : 0) - (down ? 1 : 0);
    player.vel.y += (vy * 9 - player.vel.y) * Math.min(1, 10 * dt);
  } else if (player.inWater) {
    player.vel.y -= 9 * dt;
    if (jump) player.vel.y += 22 * dt;
    player.vel.y = Math.max(-3, Math.min(3.5, player.vel.y));
  } else {
    player.vel.y -= 28 * dt;
    if (player.vel.y < -50) player.vel.y = -50;
    if (jump && player.onGround) player.vel.y = 8.6;
  }

  const hx = moveAxis('x', player.vel.x * dt);
  if (hx) player.vel.x = 0;
  const hz = moveAxis('z', player.vel.z * dt);
  if (hz) player.vel.z = 0;
  const wasFalling = player.vel.y < 0;
  const hy = moveAxis('y', player.vel.y * dt);
  player.onGround = hy && wasFalling;
  if (hy) player.vel.y = 0;
  if (player.onGround && player.flying && down) { player.flying = false; $('tFly').classList.remove('on'); }

  // Auto-jump for touch players walking into a one-block step
  if (isTouch && (hx || hz) && player.onGround && !player.flying && wish.lengthSq() > 0.1) {
    const ax = Math.floor(player.pos.x + wish.x * 0.6), az = Math.floor(player.pos.z + wish.z * 0.6);
    const by = Math.floor(player.pos.y);
    if (isSolid(getBlock(ax, by, az)) && !isSolid(getBlock(ax, by + 1, az)) && !isSolid(getBlock(ax, by + 2, az))) player.vel.y = 8.6;
  }

  if (player.pos.y < -30) { player.pos.copy(findSpawn()); player.vel.set(0, 0, 0); toast('You fell out of the world'); }
}

function frame() {
  requestAnimationFrame(frame);
  const dt = Math.min(clock.getDelta(), 0.05);
  const playing = state === 'play';

  // Don't simulate physics until the chunk under the player exists
  const here = chunks.get(ckey(Math.floor(player.pos.x / CS), Math.floor(player.pos.z / CS)));
  if (playing && here && here.built) {
    // Never start a frame stuck inside blocks (e.g. after loading or a world change)
    let guard = 0;
    while (collides(player.pos.x, player.pos.y, player.pos.z) && guard++ < H) player.pos.y = Math.floor(player.pos.y) + 1.001;
    // sub-step for stability
    const steps = Math.ceil(dt / 0.017);
    for (let i = 0; i < steps; i++) updatePlayer(dt / steps);
  }
  updateChunks(playing ? 6 : 14);

  camera.position.set(player.pos.x, player.pos.y + player.eye, player.pos.z);
  camera.rotation.set(player.pitch, player.yaw, 0);
  updateSky(playing ? dt : 0);
  updateParticles(dt);

  const hit = playing ? raycast() : null;
  if (hit) { highlight.visible = true; highlight.position.set(hit.x + 0.5, hit.y + 0.5, hit.z + 0.5); }
  else highlight.visible = false;

  fpsAcc += dt; fpsFrames++;
  if (fpsAcc > 0.5) { fps = Math.round(fpsFrames / fpsAcc); fpsAcc = 0; fpsFrames = 0; }
  if (playing) {
    const hours = Math.floor(timeOfDay * 24), mins = Math.floor((timeOfDay * 24 - hours) * 60);
    $('info').textContent =
      `${fps} fps  ${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}\n` +
      `XYZ ${player.pos.x.toFixed(1)} ${player.pos.y.toFixed(1)} ${player.pos.z.toFixed(1)}` +
      (player.flying ? '  [fly]' : '') + (hit ? `\n${BLOCKS[hit.id].name}` : '');
  }
  renderer.render(scene, camera);
}

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

showMenu(false);
frame();

// Exposed for debugging / automated tests
window.__icon = blockIcon;
window.__game = { player, getBlock, setBlock, chunks, slots: () => slots, state: () => state, resumePlay, breakBlock, placeBlock, raycast, setTime: (t) => { timeOfDay = t; } };
})();
