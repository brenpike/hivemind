/**
 * Hivemind website swarm engine.
 *
 * Single-file script: no imports, no exports. Drives the decorative particle
 * swarm on the #swarm canvas, the xenoglyph text decode on .xg and .xs
 * elements, and the per-section formations declared with [data-formation].
 * All DOM access happens inside init(); the module top level only declares
 * constants and pure helpers.
 */

type Formation = 'hero' | 'agents' | 'workflow' | 'install' | 'ambient';

type Rgb = readonly [number, number, number];

interface GlyphDef {
  readonly d: string;
  readonly dots: ReadonlyArray<readonly [number, number]>;
}

interface GlyphSvg {
  svg: SVGSVGElement;
  use: SVGUseElement;
}

interface ViewRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface PointerState {
  x: number;
  y: number;
  on: boolean;
  down: boolean;
  locked: boolean;
  moved: boolean;
  t0: number;
  x0: number;
  y0: number;
  hold: number;
}

interface GlyphCell {
  span: HTMLSpanElement;
  use: SVGUseElement;
  at: number;
  ok: number;
}

interface DecodeRecord {
  el: HTMLElement;
  glyph: boolean;
  color: string;
  d0: number;
  vis: boolean;
  started: boolean;
  running: boolean;
  ov: HTMLSpanElement | null;
  glyphCells: GlyphCell[];
  scrambleCells: HTMLSpanElement[];
  base: string[];
  range: Range | null;
  lineTop: number;
  lineHalf: number;
}

interface DecodeTask {
  rec: DecodeRecord;
  cells: GlyphCell[];
  spans: HTMLSpanElement[];
  base: string[];
  elapsed: number;
  acc: number;
  front: number;
  end: number;
  dur: number;
}

type NavigatorWithMemory = Navigator & { deviceMemory?: number };

type ContextWithSpacing = CanvasRenderingContext2D & { letterSpacing: string };

const TAU = Math.PI * 2;
const VIOLET = 0;
const CYAN = 1;
const EMBER = 2;
const HOT = 3;
const FLARE = 4;
const RGB: ReadonlyArray<Rgb> = [[139, 92, 255], [41, 231, 255], [255, 122, 69], [244, 241, 255], [255, 122, 69]];
const LABELS: ReadonlyArray<string> = ['OVERLORD', 'CEREBRATE', 'DRONE', 'CHANGELING', 'LOCAL-REVIEWER', 'GITHUB-REVIEWER'];
const CLUSTER_COL: ReadonlyArray<readonly [number, number]> = [
  [HOT, VIOLET], [CYAN, CYAN], [VIOLET, VIOLET], [CYAN, VIOLET], [EMBER, EMBER], [EMBER, HOT],
];
const MONO = 'ui-monospace, Menlo, Consolas, monospace';
const MAXN = 2600;
const CELL = 28;
const GM = 120;
const SVGNS = 'http://www.w3.org/2000/svg';
const POOL = 'ΑΒΓΔΖΘΛΞΠΣΦΨΩαβγδζθλξπσφψωБГДЖЗИЛПФЦЧШЩЭЮЯбгджзилпфцчшэюя─│┌┐└┘├┤┬┴┼═║╔╗╚╝╬';

/** The 24 xenoglyphs on a 20 by 20 grid; feeds both the SVG symbol defs and the canvas paths. */
const GLYPHS: ReadonlyArray<GlyphDef> = [
  { d: 'M3 3H17V17', dots: [[10, 10]] },
  { d: 'M3 17L10 3L17 17M3 10H17', dots: [] },
  { d: 'M3 3V17H17M10 3V10', dots: [] },
  { d: 'M3 3L10 10L17 3M10 10V17', dots: [] },
  { d: 'M3 10L10 3L17 10L10 17Z', dots: [[10, 10]] },
  { d: 'M3 3L17 17M17 3L10 10', dots: [] },
  { d: 'M10 3V17M3 10H10M17 10V17', dots: [] },
  { d: 'M3 3H17M10 10H17M3 17H10', dots: [] },
  { d: 'M17 3H3V17M10 10L17 17', dots: [] },
  { d: 'M3 17L17 3M3 3V10', dots: [] },
  { d: 'M10 3L3 10L10 17L17 10', dots: [[17, 3]] },
  { d: 'M3 3H10V10H17V17', dots: [] },
  { d: 'M3 10V3H17V10', dots: [[10, 17]] },
  { d: 'M3 17V3L17 17', dots: [[17, 3]] },
  { d: 'M10 3V17M3 10H17', dots: [[3, 3]] },
  { d: 'M3 3L17 10L3 17', dots: [[17, 17]] },
  { d: 'M17 3L3 17M3 3L10 10', dots: [] },
  { d: 'M3 10H10V3H17M10 17H17', dots: [] },
  { d: 'M3 3V10H10V17H17', dots: [[17, 3]] },
  { d: 'M3 17V10L10 3L17 10V17M10 10V17', dots: [] },
  { d: 'M3 3H17M10 3V17M3 17H17', dots: [] },
  { d: 'M17 3V17H3M3 10H10', dots: [] },
  { d: 'M3 3L10 17L17 3', dots: [[10, 3]] },
  { d: 'M3 10L17 3M3 17L17 10', dots: [[10, 10]] },
];
const NG = GLYPHS.length;

/** Clamps a value into the inclusive range [lo, hi]. */
function clamp(value: number, lo: number, hi: number): number {
  return value < lo ? lo : (value > hi ? hi : value);
}

/** Returns a random integer in [0, limit). */
function randomInt(limit: number): number {
  return (Math.random() * limit) | 0;
}

/** Returns a random scramble character from the decode pool. */
function randomPoolChar(): string {
  return POOL.charAt(randomInt(POOL.length));
}

/** Maps a [data-formation] element to its formation; unknown values map to ambient. */
function readFormation(section: Element): Formation {
  const value = section.getAttribute('data-formation');
  return value === 'hero' || value === 'agents' || value === 'workflow' || value === 'install' ? value : 'ambient';
}

/** Reads the canvas data-density attribute as a float clamped to [0.2, 1]; defaults to 1. */
function readDensity(canvas: HTMLCanvasElement): number {
  const raw = parseFloat(canvas.getAttribute('data-density') || '');
  return isNaN(raw) ? 1 : clamp(raw, 0.2, 1);
}

/** Returns the section itself when it matches the selector, else its first matching descendant. */
function findInSection(section: Element, selector: string): Element | null {
  return section.matches(selector) ? section : section.querySelector(selector);
}

/** Builds one radial glow sprite; returns null when a 2d context is unavailable. */
function makeSprite(rgbValue: Rgb, core: number): HTMLCanvasElement | null {
  const sprite = document.createElement('canvas');
  sprite.width = sprite.height = 64;
  const sctx = sprite.getContext('2d');
  if (!sctx) return null;
  const grad = sctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  const rgb = rgbValue[0] + ',' + rgbValue[1] + ',' + rgbValue[2];
  grad.addColorStop(0, 'rgba(255,255,255,' + core + ')');
  grad.addColorStop(0.12, 'rgba(' + rgb + ',0.95)');
  grad.addColorStop(0.34, 'rgba(' + rgb + ',0.3)');
  grad.addColorStop(0.68, 'rgba(' + rgb + ',0.06)');
  grad.addColorStop(1, 'rgba(' + rgb + ',0)');
  sctx.fillStyle = grad;
  sctx.fillRect(0, 0, 64, 64);
  return sprite;
}

/** Builds the full sprite set, one per color index; returns null if any sprite fails. */
function buildSprites(): HTMLCanvasElement[] | null {
  const sprites: HTMLCanvasElement[] = [];
  for (let si = 0; si < RGB.length; si++) {
    const sprite = makeSprite(RGB[si], si === FLARE ? 1 : 0.8);
    if (!sprite) return null;
    sprites.push(sprite);
  }
  return sprites;
}

/** Creates an inline svg that references glyph symbol #g{glyphIdx}. */
function createGlyphSvg(cls: string, glyphIdx: number): GlyphSvg {
  const svg = document.createElementNS(SVGNS, 'svg');
  const use = document.createElementNS(SVGNS, 'use');
  svg.setAttribute('class', cls);
  svg.setAttribute('viewBox', '0 0 20 20');
  svg.setAttribute('focusable', 'false');
  use.setAttribute('href', '#g' + glyphIdx);
  svg.appendChild(use);
  return { svg, use };
}

/** Builds the <symbol id="gN"> element for one glyph definition. */
function buildGlyphSymbol(glyphIdx: number): SVGSymbolElement {
  const def = GLYPHS[glyphIdx];
  const symbol = document.createElementNS(SVGNS, 'symbol');
  symbol.setAttribute('id', 'g' + glyphIdx);
  symbol.setAttribute('viewBox', '0 0 20 20');
  const path = document.createElementNS(SVGNS, 'path');
  path.setAttribute('d', def.d);
  symbol.appendChild(path);
  for (let di = 0; di < def.dots.length; di++) {
    const dot = document.createElementNS(SVGNS, 'circle');
    dot.setAttribute('cx', String(def.dots[di][0]));
    dot.setAttribute('cy', String(def.dots[di][1]));
    dot.setAttribute('r', '1.8');
    dot.setAttribute('fill', 'currentColor');
    dot.setAttribute('stroke', 'none');
    symbol.appendChild(dot);
  }
  return symbol;
}

/** Appends the hidden glyph symbol defs to body unless #g0 already exists. Idempotent. */
function ensureGlyphDefs(): void {
  if (document.getElementById('g0')) return;
  const svg = document.createElementNS(SVGNS, 'svg');
  svg.setAttribute('class', 'gdefs');
  svg.setAttribute('width', '0');
  svg.setAttribute('height', '0');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  const defs = document.createElementNS(SVGNS, 'defs');
  for (let gi = 0; gi < NG; gi++) defs.appendChild(buildGlyphSymbol(gi));
  svg.appendChild(defs);
  document.body.appendChild(svg);
}

/** Boots the swarm engine against the current document. */
function init(): void {
  const root = document.documentElement;
  root.classList.add('swarm-ready');
  const swarmNode = document.getElementById('swarm');
  const swarmCanvas = swarmNode instanceof HTMLCanvasElement ? swarmNode : null;
  const maybeCtx = swarmCanvas && typeof swarmCanvas.getContext === 'function'
    ? swarmCanvas.getContext('2d', { alpha: false })
    : null;
  const maybeSprites = maybeCtx && typeof window.requestAnimationFrame === 'function' ? buildSprites() : null;
  if (!swarmCanvas || !maybeCtx || !maybeSprites) {
    root.classList.remove('swarm-live');
    return;
  }
  const canvas: HTMLCanvasElement = swarmCanvas;
  const ctx: CanvasRenderingContext2D = maybeCtx;
  const sprites: HTMLCanvasElement[] = maybeSprites;
  ensureGlyphDefs();

  const heroWord = document.getElementById('hero-title');
  const stage = document.getElementById('agent-stage');
  const header = document.querySelector('.site-head');
  const cards = document.querySelectorAll<HTMLElement>('[data-cluster]');
  const sections = document.querySelectorAll('[data-formation]');
  const heroSection = document.querySelector('[data-formation="hero"]');
  const passive: AddEventListenerOptions = { passive: true };
  const nowMs: () => number = window.performance && typeof window.performance.now === 'function'
    ? () => window.performance.now()
    : () => Date.now();
  const density = readDensity(canvas);

  const px = new Float32Array(MAXN), py = new Float32Array(MAXN);
  const vx = new Float32Array(MAXN), vy = new Float32Array(MAXN);
  const tx = new Float32Array(MAXN), ty = new Float32Array(MAXN), tw = new Float32Array(MAXN);
  const r1 = new Float32Array(MAXN), r2 = new Float32Array(MAXN), r3 = new Float32Array(MAXN);
  const r4 = new Float32Array(MAXN), r5 = new Float32Array(MAXN), su = new Float32Array(MAXN);
  const sz = new Float32Array(MAXN);
  const col = new Uint8Array(MAXN), lit = new Uint8Array(MAXN);
  const cellOf = new Int32Array(MAXN), order = new Int32Array(MAXN);
  let cellStart = new Int32Array(2), cellFill = new Int32Array(1);
  let cols = 1, rows = 1;

  let count = 0, viewW = 0, viewH = 0, dpr = 1, smallView = false, perfScale = 1;
  let mode: Formation = heroSection ? readFormation(heroSection) : 'ambient';
  let activeSection: Element | null = heroSection;
  let flowEl: Element | null = null;
  let beatEls: ArrayLike<Element> = [];
  let orbitEl: Element | null = null;
  let modeT = 0, clock = 0, lastTs = 0, rafId = 0, isLive = false;
  let heroPts = new Float32Array(0), heroK = 0, heroW = 0, heroH = 0, heroCx = 0, heroCy = 0, heroStep = 6;
  let flowNodes: number[] = [], flowW = 0, flowH = 0, spineX = 26, amp = 10;
  let fLo = 0, fSpan = 1, fOx = 0, fTop = 0, flowAlpha = 0, wiggle = 0, nodeDist = 1e9;
  const cx = new Float32Array(6), cy = new Float32Array(6), cr = new Float32Array(6);
  const qx = new Float32Array(6), qy = new Float32Array(6), litAmt = new Float32Array(6);
  let litCluster = -1, graphAlpha = 0, bezX = 0, bezY = 0;
  const pointer: PointerState = { x: -9999, y: -9999, on: false, down: false, locked: false, moved: false, t0: 0, x0: 0, y0: 0, hold: 0 };
  let perfAcc = 0, perfFrames = 0, perfWindow = 0, booted = false;

  const hasP2D = typeof Path2D === 'function';
  const hasIO = typeof IntersectionObserver === 'function';
  const glyphPaths: Array<Path2D | null> = GLYPHS.map((def) => (hasP2D ? new Path2D(def.d) : null));
  const glyphPts: Array<Float32Array | null> = GLYPHS.map(() => null);

  const firstNode = heroWord ? heroWord.firstChild : null;
  const word = firstNode && firstNode.nodeType === 3 ? (firstNode.nodeValue || '') : 'Hivemind';
  let letterCount = 0, glyphOK = false, glyphSize = 0, glyphTop = 0;
  const lx0 = new Float32Array(16), lx1 = new Float32Array(16), glyphLeft = new Float32Array(16);
  let heroL = new Uint8Array(0), heroJ = new Uint16Array(0);
  let seqOn = false, seqT = 0, swapT = 0, seqUsed = false;
  const morph = new Float32Array(16), resAt = new Float32Array(16), gIdx = new Uint8Array(16), lOk = new Uint8Array(16);
  let wmOv: HTMLSpanElement | null = null;
  let wmG: SVGSVGElement[] = [], wmU: SVGUseElement[] = [], wmT: HTMLSpanElement[] = [];

  let labT = 99, labFs = 0;
  let labW: number[][] = [], labTot: number[] = [];

  const recs: DecodeRecord[] = [];
  const byEl = new WeakMap<Element, DecodeRecord>();
  const decodeTasks: DecodeTask[] = [];
  let decodeReady = false;
  let resizeTimer = 0;

  /** Strokes glyph glyphIdx into target at (originX, originY), scaled to size pixels. */
  function traceGlyph(target: CanvasRenderingContext2D, glyphIdx: number, originX: number, originY: number,
    size: number, lineWidth: number, dotRadius: number): void {
    const path = glyphPaths[glyphIdx];
    if (!path) return;
    target.save();
    target.translate(originX, originY);
    target.scale(size / 20, size / 20);
    target.lineWidth = lineWidth;
    target.lineCap = 'square';
    target.lineJoin = 'miter';
    target.stroke(path);
    const dots = GLYPHS[glyphIdx].dots;
    for (let q = 0; q < dots.length; q++) {
      target.beginPath();
      target.arc(dots[q][0], dots[q][1], dotRadius, 0, TAU);
      target.fill();
    }
    target.restore();
  }

  /** Returns the particle count for the current viewport, hardware, perf scale and page density. */
  function computeCount(): number {
    const area = viewW * viewH;
    let target: number;
    if (viewW < 640) target = clamp(area / (375 * 812) * 650, 500, 800);
    else if (viewW < 1024) target = clamp(area / (820 * 1100) * 1300, 900, 1600);
    else target = clamp(area / (1440 * 900) * 2200, 1800, 2500);
    const cores = navigator.hardwareConcurrency || 8;
    const memory = (navigator as NavigatorWithMemory).deviceMemory;
    if (cores <= 4) target *= 0.5;
    if (cores <= 2 || (memory && memory <= 2)) target = 300;
    return Math.round(clamp(target * perfScale * density, 300, MAXN));
  }

  /** Resizes the canvas, tolerating mobile URL-bar height jitter, and rebuilds the spatial hash. */
  function resize(): void {
    const wid = root.clientWidth || window.innerWidth;
    const hgt = window.innerHeight;
    const nextDpr = Math.min(window.devicePixelRatio || 1, wid < 640 ? 1.5 : 2);
    if (wid !== viewW || hgt > viewH || hgt < viewH - 140 || nextDpr !== dpr || !viewH) {
      viewW = wid; viewH = hgt; dpr = nextDpr;
      canvas.width = Math.round(viewW * dpr);
      canvas.height = Math.round(viewH * dpr);
      canvas.style.width = viewW + 'px';
      canvas.style.height = viewH + 'px';
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.fillStyle = '#05040d';
      ctx.fillRect(0, 0, viewW, viewH);
    }
    smallView = viewW < 640;
    cols = Math.ceil((viewW + GM * 2) / CELL);
    rows = Math.ceil((viewH + GM * 2) / CELL);
    cellStart = new Int32Array(cols * rows + 1);
    cellFill = new Int32Array(cols * rows);
    count = computeCount();
    heroW = 0; flowW = 0;
    if (!isLive && booted) renderStatic();
  }

  /** Seeds per-particle random traits, positions and velocities. */
  function seedParticles(): void {
    for (let i = 0; i < MAXN; i++) {
      r1[i] = Math.random(); r2[i] = Math.random(); r3[i] = Math.random();
      r4[i] = Math.random(); r5[i] = Math.random(); su[i] = Math.random();
      sz[i] = 5 + r3[i] * 6 + (r5[i] > 0.975 ? 7 : 0);
      px[i] = Math.random() * (viewW || 800);
      py[i] = Math.random() * (viewH || 600);
      const angle = Math.random() * TAU;
      vx[i] = Math.cos(angle) * 80; vy[i] = Math.sin(angle) * 80;
    }
  }

  /** Samples the wordmark letters into hero target points and lays out the glyph sequence. */
  function rasterHero(heroEl: HTMLElement, rect: DOMRect): void {
    heroW = rect.width; heroH = rect.height; heroK = 0;
    const wid = Math.ceil(rect.width), hgt = Math.ceil(rect.height);
    if (wid < 8 || hgt < 8) return;
    const scratch = document.createElement('canvas');
    scratch.width = wid; scratch.height = hgt;
    const sctx = scratch.getContext('2d');
    if (!sctx) return;
    const style = window.getComputedStyle(heroEl);
    sctx.font = style.fontStyle + ' ' + style.fontWeight + ' ' + style.fontSize + ' ' + style.fontFamily;
    sctx.fillStyle = '#fff';
    sctx.textBaseline = 'alphabetic';
    const textNode = heroEl.firstChild;
    let letters = 0;
    const probe = document.createElement('span');
    probe.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
    heroEl.insertBefore(probe, textNode ? textNode.nextSibling : null);
    const baseline = probe.getBoundingClientRect().bottom - rect.top;
    heroEl.removeChild(probe);
    if (textNode && textNode.nodeType === 3 && typeof document.createRange === 'function') {
      const range = document.createRange(), text = textNode.textContent || '';
      for (let k = 0; k < text.length && letters < 16; k++) {
        if (text.charAt(k) <= ' ') continue;
        range.setStart(textNode, k); range.setEnd(textNode, k + 1);
        const box = range.getBoundingClientRect();
        if (!box.width) continue;
        sctx.fillText(text.charAt(k).toUpperCase(), box.left - rect.left, baseline);
        lx0[letters] = box.left - rect.left; lx1[letters] = box.right - rect.left; letters++;
      }
    }
    if (!letters) {
      sctx.textAlign = 'center'; sctx.textBaseline = 'middle';
      sctx.fillText(word.toUpperCase(), wid / 2, hgt / 2);
      lx0[0] = 0; lx1[0] = wid; letters = 1;
    }
    letterCount = letters;
    const pixels = sctx.getImageData(0, 0, wid, hgt).data;
    let filled = 0;
    for (let y = 0; y < hgt; y += 2) for (let x = 0; x < wid; x += 2) if (pixels[(y * wid + x) * 4 + 3] > 128) filled++;
    if (!filled) return;
    const need = Math.max(120, count * 0.86);
    const step = Math.max(2, Math.sqrt(filled * 4 / need));
    heroStep = step;
    const pts: number[] = [], lets: number[] = [];
    let row = 0, minY = hgt, maxY = 0;
    for (let y = step * 0.5; y < hgt; y += step, row++) {
      for (let x = (row & 1) ? step * 0.5 : 0; x < wid; x += step) {
        const xi = x | 0, yi = y | 0;
        if (pixels[(yi * wid + xi) * 4 + 3] > 128) {
          let letterIdx = 0;
          while (letterIdx < letters - 1 && x >= (lx1[letterIdx] + lx0[letterIdx + 1]) * 0.5) letterIdx++;
          pts.push(x, y); lets.push(letterIdx);
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    const ptCount = lets.length;
    for (let i = ptCount - 1; i > 0; i--) {
      const swapIdx = (Math.random() * (i + 1)) | 0;
      let tmp = pts[i * 2]; pts[i * 2] = pts[swapIdx * 2]; pts[swapIdx * 2] = tmp;
      tmp = pts[i * 2 + 1]; pts[i * 2 + 1] = pts[swapIdx * 2 + 1]; pts[swapIdx * 2 + 1] = tmp;
      tmp = lets[i]; lets[i] = lets[swapIdx]; lets[swapIdx] = tmp;
    }
    const perLetter = new Uint16Array(16);
    heroPts = new Float32Array(pts);
    heroL = new Uint8Array(lets);
    heroJ = new Uint16Array(ptCount);
    for (let i = 0; i < ptCount; i++) heroJ[i] = perLetter[heroL[i]]++;
    heroK = ptCount;
    layoutGlyphs(wid, minY, maxY, step);
  }

  /** Places one glyph per letter, evenly spaced across the word, sampled at the swarm's spacing. */
  function layoutGlyphs(wid: number, minY: number, maxY: number, step: number): void {
    glyphOK = false;
    if (!hasP2D || letterCount < 2 || maxY <= minY) return;
    const slot = wid / letterCount, size = Math.min((maxY - minY) / 0.7 * 0.98, slot * 1.12);
    glyphSize = size; glyphTop = (minY + maxY) * 0.5 - size * 0.5;
    for (let k = 0; k < letterCount; k++) glyphLeft[k] = (k + 0.5) * slot - size * 0.5;
    const side = Math.ceil(size) + 4, scratch = document.createElement('canvas');
    scratch.width = scratch.height = side;
    const sctx = scratch.getContext('2d');
    if (!sctx) return;
    sctx.fillStyle = sctx.strokeStyle = '#fff';
    for (let gi = 0; gi < NG; gi++) {
      sctx.clearRect(0, 0, side, side);
      traceGlyph(sctx, gi, 2, 2, size, 3.6, 2.6);
      const pixels = sctx.getImageData(0, 0, side, side).data, pts: number[] = [];
      let row = 0;
      for (let y = step * 0.5; y < side; y += step, row++) {
        for (let x = (row & 1) ? step * 0.5 : 0; x < side; x += step) {
          if (pixels[((y | 0) * side + (x | 0)) * 4 + 3] > 128) pts.push(x - 2, y - 2);
        }
      }
      for (let i = (pts.length >> 1) - 1; i > 0; i--) {
        const swapIdx = (Math.random() * (i + 1)) | 0;
        let tmp = pts[i * 2]; pts[i * 2] = pts[swapIdx * 2]; pts[swapIdx * 2] = tmp;
        tmp = pts[i * 2 + 1]; pts[i * 2 + 1] = pts[swapIdx * 2 + 1]; pts[swapIdx * 2 + 1] = tmp;
      }
      if (pts.length < 2) return;
      glyphPts[gi] = new Float32Array(pts);
    }
    glyphOK = true;
    placeGlyphs();
  }

  /** Positions the wordmark overlay glyph svgs over their letter slots. */
  function placeGlyphs(): void {
    for (let k = 0; k < wmG.length && k < letterCount; k++) {
      wmG[k].style.cssText = 'left:' + glyphLeft[k].toFixed(1) + 'px;top:' + glyphTop.toFixed(1) + 'px;width:'
        + glyphSize.toFixed(1) + 'px;height:' + glyphSize.toFixed(1) + 'px';
    }
  }

  /** Starts the wordmark sequence: alien script first, English as the particles lock in. */
  function startSequence(hold: number): void {
    if (!hasP2D || !heroWord) return;
    endSequence();
    seqOn = true; seqUsed = true; seqT = 0; swapT = 0;
    const overlay = document.createElement('span');
    overlay.className = 'wm-ov';
    overlay.setAttribute('aria-hidden', 'true');
    wmG = []; wmU = []; wmT = [];
    for (let j = 0; j < word.length; j++) {
      const ch = word.charAt(j);
      if (ch <= ' ') { overlay.appendChild(document.createTextNode(ch)); continue; }
      const letter = document.createElement('span');
      letter.className = 'wm-l';
      letter.textContent = ch;
      overlay.appendChild(letter); wmT.push(letter);
    }
    for (let k = 0; k < 16; k++) {
      morph[k] = 0; lOk[k] = 0; gIdx[k] = randomInt(NG);
      resAt[k] = hold + k * 0.16 + Math.random() * 0.07;
    }
    for (let k = 0; k < wmT.length; k++) {
      const glyph = createGlyphSvg('gly wm-gl' + (k & 1 ? ' c1' : ''), gIdx[k]);
      overlay.appendChild(glyph.svg); wmG.push(glyph.svg); wmU.push(glyph.use);
    }
    heroWord.appendChild(overlay);
    heroWord.classList.add('wm-enc');
    wmOv = overlay;
    if (glyphSize) placeGlyphs();
  }

  /** Ends the wordmark sequence and removes its overlay. */
  function endSequence(): void {
    seqOn = false;
    for (let k = 0; k < 16; k++) morph[k] = 1;
    if (wmOv && wmOv.parentNode) wmOv.parentNode.removeChild(wmOv);
    wmOv = null; wmG = []; wmU = []; wmT = [];
    if (heroWord) heroWord.classList.remove('wm-enc');
  }

  /** Advances the wordmark sequence by dt seconds. */
  function stepSequence(dt: number): void {
    if (!seqOn) return;
    if (heroK && !glyphOK) { endSequence(); return; }
    seqT += dt; swapT += dt;
    const swap = swapT > 0.5, letters = Math.min(letterCount, wmT.length);
    let busy = false;
    if (swap) swapT = 0;
    for (let k = 0; k < letters; k++) {
      const progress = clamp((seqT - resAt[k]) / 0.55, 0, 1);
      morph[k] = progress;
      if (progress < 1) busy = true;
      if (progress <= 0) {
        if (swap && Math.random() < 0.35) { gIdx[k] = randomInt(NG); wmU[k].setAttribute('href', '#g' + gIdx[k]); }
      } else if (!lOk[k]) {
        lOk[k] = 1;
        wmG[k].classList.add('off');
      } else if (lOk[k] === 1 && progress > 0.35) {
        lOk[k] = 2;
        wmT[k].classList.add('ok');
      }
    }
    if (!busy && letters && seqT > resAt[letters - 1] + 1.5) endSequence();
  }

  /** Hero formation: particles fill the wordmark, morphing out of the glyph sequence. */
  function computeHeroTargets(dt: number): void {
    if (!heroWord) { freeAll(); return; }
    const rect = heroWord.getBoundingClientRect();
    if (Math.abs(rect.width - heroW) > 1 || Math.abs(rect.height - heroH) > 1) rasterHero(heroWord, rect);
    heroCx = rect.left + rect.width * 0.5; heroCy = rect.top + rect.height * 0.5;
    stepSequence(dt);
    const encoding = seqOn && glyphOK, jitter = heroStep * 0.5;
    for (let i = 0; i < count; i++) {
      if (r1[i] < (smallView ? 0.08 : 0.14) || !heroK) { tw[i] = 0; col[i] = r2[i] < 0.55 ? VIOLET : CYAN; lit[i] = 0; continue; }
      const ptIdx = i % heroK;
      let targetX = heroPts[ptIdx * 2], targetY = heroPts[ptIdx * 2 + 1], colorIdx = -1;
      if (encoding) {
        const letterIdx = heroL[ptIdx], morphAmt = morph[letterIdx], pts = glyphPts[gIdx[letterIdx]];
        if (morphAmt < 1 && pts) {
          const off = (heroJ[ptIdx] % (pts.length >> 1)) * 2;
          const gx = glyphLeft[letterIdx] + pts[off] + (r2[i] - 0.5) * jitter;
          const gy = glyphTop + pts[off + 1] + (r3[i] - 0.5) * jitter;
          const ease = morphAmt * morphAmt * (3 - 2 * morphAmt);
          targetX = gx + (targetX - gx) * ease; targetY = gy + (targetY - gy) * ease;
          colorIdx = morphAmt > 0 ? (r2[i] < 0.5 ? EMBER : HOT) : (r2[i] < 0.6 ? VIOLET : CYAN);
        }
      }
      tx[i] = rect.left + targetX + Math.sin(clock * 1.3 + r2[i] * 40) * 1.1;
      ty[i] = rect.top + targetY + Math.cos(clock * 1.1 + r3[i] * 40) * 1.1;
      tw[i] = 1;
      col[i] = colorIdx >= 0 ? colorIdx : (r2[i] < 0.42 ? HOT : (r2[i] < 0.86 ? VIOLET : CYAN));
      lit[i] = 0;
    }
  }

  /** Maps a particle's seed value to one of the six agent clusters. */
  function pickCluster(seedValue: number): number {
    if (seedValue < 0.25) return 0;
    const idx = (1 + (seedValue - 0.25) / 0.15) | 0;
    return idx > 5 ? 5 : idx;
  }

  /** Lays out the hub and five spoke clusters inside rect at time tm. */
  function layoutClusters(rect: ViewRect, tm: number): void {
    const span = Math.min(rect.width, rect.height);
    const mx = rect.left + rect.width * 0.5, my = rect.top + rect.height * 0.5;
    const ring = span * 0.36;
    cx[0] = mx + Math.sin(tm * 0.3) * span * 0.006; cy[0] = my; cr[0] = span * 0.115;
    for (let k = 1; k < 6; k++) {
      const angle = -Math.PI / 2 + (k - 1) * TAU / 5 + Math.sin(tm * 0.12) * 0.04;
      const radius = ring + Math.sin(tm * 0.5 + k * 1.7) * span * 0.012;
      cx[k] = mx + Math.cos(angle) * radius; cy[k] = my + Math.sin(angle) * radius; cr[k] = span * 0.075;
      const dx = cx[k] - cx[0], dy = cy[k] - cy[0], bend = Math.sin(tm * 0.45 + k * 2.1) * 0.12 + 0.06;
      qx[k] = (cx[0] + cx[k]) * 0.5 - dy * bend;
      qy[k] = (cy[0] + cy[k]) * 0.5 + dx * bend;
    }
  }

  /** Samples the hub-to-spoke bezier k at parameter phase into bezX and bezY. */
  function sampleBezier(k: number, phase: number): void {
    const tt = 0.08 + phase * 0.84;
    const inv = 1 - tt;
    bezX = inv * inv * cx[0] + 2 * inv * tt * qx[k] + tt * tt * cx[k];
    bezY = inv * inv * cy[0] + 2 * inv * tt * qy[k] + tt * tt * cy[k];
  }

  /** Writes particle i's agent-formation target and color at time tm. */
  function placeAgentPoint(i: number, tm: number): void {
    const cl = pickCluster(r1[i]);
    col[i] = CLUSTER_COL[cl][(i & 3) === 0 ? 1 : 0];
    lit[i] = litAmt[cl] > 0.5 && r4[i] < 0.6 ? 1 : 0;
    if (r2[i] < 0.11 && cl > 0) {
      let phase = (tm * (0.07 + r3[i] * 0.09) + r4[i]) % 1;
      if (i & 1) phase = 1 - phase;
      sampleBezier(cl, phase);
      tx[i] = bezX; ty[i] = bezY;
      col[i] = (i & 1) ? EMBER : CYAN;
      return;
    }
    const spin = (0.18 + (1 - r3[i]) * 0.45) * (cl & 1 ? -1 : 1);
    const ang = r4[i] * TAU + tm * spin;
    const rad = cr[cl] * (0.18 + Math.sqrt(r3[i]) * 0.92) * (1 + litAmt[cl] * 0.28 + Math.sin(tm * 2 + r1[i] * 30) * 0.05);
    tx[i] = cx[cl] + Math.cos(ang) * rad;
    ty[i] = cy[cl] + Math.sin(ang) * rad * 0.92;
  }

  /** Agents formation: six clusters, hub plus spokes, around #agent-stage. */
  function computeAgentTargets(dt: number): void {
    const rect: ViewRect = stage ? stage.getBoundingClientRect() : { left: 0, top: 0, width: viewW, height: viewH };
    layoutClusters(rect, clock);
    for (let k = 0; k < 6; k++) litAmt[k] += ((k === litCluster ? 1 : 0) - litAmt[k]) * Math.min(1, dt * 6);
    for (let i = 0; i < count; i++) {
      if (r5[i] < 0.07) { tw[i] = 0; col[i] = r2[i] < 0.5 ? VIOLET : CYAN; lit[i] = 0; continue; }
      placeAgentPoint(i, clock);
      tw[i] = 1;
    }
  }

  /** Caches the spine geometry and beat node offsets of the active .flow element. */
  function layoutFlow(flow: Element, rect: DOMRect): void {
    flowW = rect.width; flowH = rect.height;
    const padLeft = parseFloat(window.getComputedStyle(flow).paddingLeft) || 52;
    spineX = padLeft * 0.5;
    amp = Math.min(padLeft * 0.3, 26);
    flowNodes = [];
    for (let i = 0; i < beatEls.length; i++) flowNodes.push(beatEls[i].getBoundingClientRect().top - rect.top + 34);
  }

  /** Samples the spine wiggle and nearest beat distance at local y offset ly. */
  function sampleFlow(ly: number): void {
    const nodeCount = flowNodes.length;
    nodeDist = 1e9;
    for (let k = 0; k < nodeCount; k++) { const dist = Math.abs(ly - flowNodes[k]); if (dist < nodeDist) nodeDist = dist; }
    if (!nodeCount) { wiggle = Math.sin(ly * 0.012) * amp * 0.6; return; }
    if (ly < flowNodes[0]) { wiggle = Math.sin((ly - flowNodes[0]) * 0.012) * amp * 0.6; return; }
    if (ly >= flowNodes[nodeCount - 1]) { wiggle = Math.sin((ly - flowNodes[nodeCount - 1]) * 0.012) * amp * 0.6; return; }
    for (let k = 0; k < nodeCount - 1; k++) {
      if (ly < flowNodes[k + 1]) {
        wiggle = Math.sin((ly - flowNodes[k]) / (flowNodes[k + 1] - flowNodes[k]) * Math.PI) * amp * (k & 1 ? 1 : -1);
        return;
      }
    }
    wiggle = 0;
  }

  /** Workflow formation: stream along the spine through the active section's beats. */
  function computeFlowTargets(dt: number): void {
    if (!flowEl) { freeAll(); return; }
    const rect = flowEl.getBoundingClientRect();
    if (Math.abs(rect.width - flowW) > 1 || Math.abs(rect.height - flowH) > 1) layoutFlow(flowEl, rect);
    const lo = Math.max(rect.top, -40);
    let hi = Math.min(rect.bottom, viewH + 40);
    if (hi - lo < 80) hi = lo + 80;
    const span = hi - lo, ox = rect.left + spineX, lane = smallView ? 7 : 12;
    fLo = lo; fSpan = span; fOx = ox; fTop = rect.top;
    for (let i = 0; i < count; i++) {
      if (r1[i] < 0.12) { tw[i] = 0; col[i] = r2[i] < 0.5 ? VIOLET : CYAN; lit[i] = 0; continue; }
      let yPos = lo + su[i] * span;
      sampleFlow(yPos - rect.top);
      const speed = (60 + r2[i] * 90) * (0.2 + 0.8 * Math.min(1, nodeDist / 70));
      su[i] += speed * dt / span;
      if (su[i] >= 1) {
        su[i] -= 1;
        px[i] = ox + (r3[i] - 0.5) * 8; py[i] = lo - 6; vx[i] = 0; vy[i] = speed;
        yPos = lo; sampleFlow(yPos - rect.top);
      }
      const lat = (r3[i] + r4[i] - 1) * lane * (1 + 0.35 * Math.sin(clock * 2 + yPos * 0.02));
      tx[i] = ox + wiggle + lat; ty[i] = yPos; tw[i] = 1;
      col[i] = nodeDist < 15 ? (r4[i] < 0.5 ? EMBER : HOT) : (r2[i] < 0.62 ? CYAN : VIOLET);
      lit[i] = 0;
    }
  }

  /** Install formation: orbit the active section's [data-orbit] element. */
  function computeOrbitTargets(): void {
    if (!orbitEl) { freeAll(); return; }
    const rect = orbitEl.getBoundingClientRect();
    const mx = rect.left + rect.width * 0.5, my = rect.top + rect.height * 0.5, hw = rect.width * 0.5, hh = rect.height * 0.5;
    const ex0 = smallView ? 14 : 28, shellX = smallView ? 10 : 22, shellY = smallView ? 9 : 18;
    for (let i = 0; i < count; i++) {
      if (r1[i] < 0.1) { tw[i] = 0; col[i] = r2[i] < 0.5 ? VIOLET : CYAN; lit[i] = 0; continue; }
      const shell = i & 3;
      const rx = hw + ex0 + shell * shellX + r2[i] * shellX * 0.8;
      const ry = hh + ex0 * 0.8 + shell * shellY + r2[i] * shellY * 0.7;
      const omega = (0.2 + 0.1 * (3 - shell)) * (shell & 1 ? -1 : 1) * (0.85 + r3[i] * 0.3);
      const theta = r4[i] * TAU + clock * omega;
      const tilt = (shell - 1.5) * 0.06 + Math.sin(clock * 0.1) * 0.03;
      const ex = Math.cos(theta) * rx, ey = Math.sin(theta) * ry, ct = Math.cos(tilt), st = Math.sin(tilt);
      tx[i] = mx + ex * ct - ey * st; ty[i] = my + ex * st + ey * ct; tw[i] = 1;
      col[i] = shell === 3 ? (r5[i] < 0.3 ? EMBER : HOT) : (shell === 1 ? VIOLET : CYAN);
      lit[i] = 0;
    }
  }

  /** Ambient formation: every particle drifts free. */
  function freeAll(): void {
    for (let i = 0; i < count; i++) { tw[i] = 0; col[i] = r2[i] < 0.5 ? VIOLET : CYAN; lit[i] = 0; }
  }

  /** Computes formation targets, then blends in press-hold convergence on the pointer. */
  function computeTargets(dt: number): void {
    if (mode === 'hero') computeHeroTargets(dt);
    else if (mode === 'agents') computeAgentTargets(dt);
    else if (mode === 'workflow') computeFlowTargets(dt);
    else if (mode === 'install') computeOrbitTargets();
    else freeAll();
    const hold = pointer.hold;
    if (hold > 0.002) {
      const reach = smallView ? 70 : 115;
      for (let i = 0; i < count; i++) {
        const angle = r4[i] * TAU + clock * (1.1 + r3[i]) * (i & 1 ? 1 : -1);
        const rad = 6 + r2[i] * r2[i] * reach;
        const gx = pointer.x + Math.cos(angle) * rad, gy = pointer.y + Math.sin(angle) * rad;
        if (tw[i] > 0) { tx[i] += (gx - tx[i]) * hold; ty[i] += (gy - ty[i]) * hold; }
        else { tx[i] = gx; ty[i] = gy; }
        tw[i] += (1 - tw[i]) * hold;
      }
    }
  }

  /** Buckets particles into the spatial hash (counting sort by cell). */
  function buildGrid(): void {
    const nCells = cols * rows;
    for (let cell = 0; cell <= nCells; cell++) cellStart[cell] = 0;
    for (let i = 0; i < count; i++) {
      let gx = ((px[i] + GM) / CELL) | 0, gy = ((py[i] + GM) / CELL) | 0;
      if (gx < 0) gx = 0; else if (gx >= cols) gx = cols - 1;
      if (gy < 0) gy = 0; else if (gy >= rows) gy = rows - 1;
      const cell = gy * cols + gx;
      cellOf[i] = cell; cellStart[cell + 1]++;
    }
    for (let cell = 0; cell < nCells; cell++) cellStart[cell + 1] += cellStart[cell];
    for (let cell = 0; cell < nCells; cell++) cellFill[cell] = cellStart[cell];
    for (let i = 0; i < count; i++) { const cell = cellOf[i]; order[cellFill[cell]++] = i; }
  }

  /** Integrates boids flocking, target arrival, swirl and pointer flee for dt seconds. */
  function simulate(dt: number): void {
    const ramp = Math.min(1, modeT / 1.6);
    let form = Math.max(0.12, ramp * ramp * (3 - 2 * ramp));
    form = Math.max(form, pointer.hold);
    const maxS = smallView ? 320 : 400;
    let sepR = smallView ? 7.5 : 9;
    if (mode === 'hero' && pointer.hold < 0.5) sepR = Math.min(sepR, heroStep * 0.85);
    const sepR2 = sepR * sepR, nbR2 = 26 * 26;
    const flee = pointer.on && pointer.hold < 0.4, fr = smallView ? 90 : 125, fr2 = fr * fr;
    const swirl = mode === 'hero' ? (1 - form) : 0;
    const drag0 = Math.exp(-dt * 0.35);
    for (let i = 0; i < count; i++) {
      const posX = px[i], posY = py[i];
      let ux = vx[i], uy = vy[i], ax = 0, ay = 0;
      const cell = cellOf[i], ccx = cell % cols, ccy = (cell / cols) | 0;
      let sx = 0, sy = 0, alx = 0, aly = 0, chx = 0, chy = 0, neighbors = 0;
      outer:
      for (let gy = ccy - 1; gy <= ccy + 1; gy++) {
        if (gy < 0 || gy >= rows) continue;
        for (let gx = ccx - 1; gx <= ccx + 1; gx++) {
          if (gx < 0 || gx >= cols) continue;
          const cc = gy * cols + gx, end = cellStart[cc + 1];
          for (let j = cellStart[cc]; j < end; j++) {
            const other = order[j];
            if (other === i) continue;
            const dx = posX - px[other], dy = posY - py[other], d2 = dx * dx + dy * dy;
            if (d2 < nbR2 && d2 > 0.0001) {
              neighbors++; alx += vx[other]; aly += vy[other]; chx += px[other]; chy += py[other];
              if (d2 < sepR2) { const inv = 1 / d2; sx += dx * inv; sy += dy * inv; }
              if (neighbors >= 10) break outer;
            }
          }
        }
      }
      const weight = tw[i];
      let near = 0;
      if (weight > 0) {
        const ddx = tx[i] - posX, ddy = ty[i] - posY, dist = Math.sqrt(ddx * ddx + ddy * ddy) + 0.0001;
        const des = Math.min(maxS * 1.2, dist * 3.4);
        const gain = 7 * weight * form;
        ax += (ddx / dist * des - ux) * gain; ay += (ddy / dist * des - uy) * gain;
        near = Math.max(0, 1 - dist / 90) * weight * form;
      }
      const flock = 1 - 0.85 * near;
      if (neighbors) {
        const ic = 1 / neighbors;
        ax += (alx * ic - ux) * 1.1 * flock + (chx * ic - posX) * 1.6 * flock;
        ay += (aly * ic - uy) * 1.1 * flock + (chy * ic - posY) * 1.6 * flock;
      }
      const sep = near > 0.5 ? 700 : 2400;
      ax += sx * sep; ay += sy * sep;
      if (weight < 1) {
        const wa = r4[i] * TAU + clock * (0.5 + r3[i]) + Math.sin(clock * 0.3 + r5[i] * 9) * 2;
        const ww = 150 * (1 - weight);
        ax += Math.cos(wa) * ww; ay += Math.sin(wa) * ww;
        if (posX < -30) ax += (-30 - posX) * 5; else if (posX > viewW + 30) ax -= (posX - viewW - 30) * 5;
        if (posY < -30) ay += (-30 - posY) * 5; else if (posY > viewH + 30) ay -= (posY - viewH - 30) * 5;
      }
      if (swirl > 0) {
        const hx = posX - heroCx, hy = posY - heroCy, hd = Math.sqrt(hx * hx + hy * hy) + 1;
        ax += (-hy / hd) * 560 * swirl - hx / hd * 60 * swirl;
        ay += (hx / hd) * 560 * swirl - hy / hd * 60 * swirl;
      }
      let lim = maxS;
      if (flee) {
        const fx = posX - pointer.x, fy = posY - pointer.y, f2 = fx * fx + fy * fy;
        if (f2 < fr2) {
          const fd = Math.sqrt(f2) + 0.001, fk = 1 - fd / fr, fs = fk * fk * 7000;
          ax += fx / fd * fs; ay += fy / fd * fs; lim = maxS * 1.9;
        }
      }
      ux += ax * dt; uy += ay * dt;
      const speed = Math.sqrt(ux * ux + uy * uy);
      if (speed > lim) { ux *= lim / speed; uy *= lim / speed; }
      const drag = near > 0 ? Math.exp(-dt * (0.35 + 2.2 * near)) : drag0;
      ux *= drag; uy *= drag;
      vx[i] = ux; vy[i] = uy;
      px[i] = posX + ux * dt; py[i] = posY + uy * dt;
    }
  }

  /** Draws the hub-and-spoke graph edges and their travelling pulses. */
  function drawGraph(alpha: number, tm: number, pulses: number): void {
    ctx.lineWidth = 1;
    for (let k = 1; k < 6; k++) {
      const la = alpha * (0.14 + litAmt[k] * 0.42 + litAmt[0] * 0.2);
      ctx.strokeStyle = 'rgba(41,231,255,' + la.toFixed(3) + ')';
      ctx.beginPath();
      ctx.moveTo(cx[0], cy[0]);
      ctx.quadraticCurveTo(qx[k], qy[k], cx[k], cy[k]);
      ctx.stroke();
      const np = pulses + (litAmt[k] > 0.5 || litAmt[0] > 0.5 ? 2 : 0);
      for (let p = 0; p < np; p++) {
        let phase = (tm * (0.24 + (p & 1) * 0.07) + p / np + k * 0.137) % 1;
        if (p & 1) phase = 1 - phase;
        sampleBezier(k, phase);
        const size = (smallView ? 16 : 22) * alpha * (0.75 + 0.5 * Math.sin(phase * Math.PI));
        ctx.drawImage(sprites[FLARE], bezX - size * 0.5, bezY - size * 0.5, size, size);
      }
    }
  }

  /** Draws cluster labels that decode from glyphs as each formation arrives. */
  function drawLabels(alpha: number): void {
    ctx.globalCompositeOperation = 'source-over';
    const fs = smallView ? 9 : 10, ls = smallView ? 1.5 : 2.5;
    ctx.font = '600 ' + fs + 'px ' + MONO;
    if ('letterSpacing' in ctx) (ctx as ContextWithSpacing).letterSpacing = '0px';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    if (labFs !== fs) {
      labFs = fs; labW = []; labTot = [];
      for (let k = 0; k < 6; k++) {
        const widths: number[] = [];
        let total = -ls;
        for (let j = 0; j < LABELS[k].length; j++) { widths.push(ctx.measureText(LABELS[k].charAt(j)).width); total += widths[j] + ls; }
        labW.push(widths); labTot.push(total);
      }
    }
    const flick = (labT * 7) | 0, gs = fs * 0.9;
    ctx.lineWidth = 1;
    for (let k = 0; k < 6; k++) {
      const txt = LABELS[k], len = txt.length, labelAlpha = alpha * (0.6 + litAmt[k] * 0.4);
      const done = clamp((labT - 0.75 - k * 0.14) / (len * 0.05), 0, 1) * len;
      let penX = cx[k] - labTot[k] * 0.5;
      const penY = cy[k] + cr[k] * 1.2 + 6;
      for (let j = 0; j < len; j++) {
        const cw = labW[k][j];
        if (done >= len || j < done - 1) {
          ctx.fillStyle = 'rgba(206,200,245,' + labelAlpha.toFixed(3) + ')';
          ctx.fillText(txt.charAt(j), penX, penY);
        } else if (j < done + 1) {
          ctx.fillStyle = 'rgba(255,176,143,' + alpha.toFixed(3) + ')';
          ctx.fillText(txt.charAt(j), penX, penY);
        } else if (hasP2D) {
          ctx.strokeStyle = ctx.fillStyle = (j + k) & 1
            ? 'rgba(41,231,255,' + (labelAlpha * 0.85).toFixed(3) + ')'
            : 'rgba(139,92,255,' + labelAlpha.toFixed(3) + ')';
          traceGlyph(ctx, (j * 7 + k * 5 + flick) % NG, penX + cw * 0.5 - gs * 0.5, penY - 0.5, gs, 2.6, 1.6);
        }
        penX += cw + ls;
      }
    }
  }

  /** Renders one live frame: trail fade, graph, particles, spine head and labels. */
  function draw(dt: number): void {
    const fade = 1 - Math.pow(0.74, dt * 60);
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = 'rgba(5,4,13,' + fade.toFixed(3) + ')';
    ctx.fillRect(0, 0, viewW, viewH);
    ctx.globalCompositeOperation = 'lighter';
    if (graphAlpha > 0.01) drawGraph(graphAlpha, clock, 2);
    const scale = mode === 'hero' ? (smallView ? 0.6 : 0.9) : (smallView ? 0.8 : 1);
    for (let i = 0; i < count; i++) {
      const posX = px[i], posY = py[i];
      if (posX < -20 || posY < -20 || posX > viewW + 20 || posY > viewH + 20) continue;
      const size = sz[i] * scale * (lit[i] ? 1.6 : 1);
      ctx.drawImage(sprites[lit[i] && (i & 3) === 0 ? HOT : col[i]], posX - size * 0.5, posY - size * 0.5, size, size);
    }
    if (flowAlpha > 0.01) {
      const headY = fLo + ((clock * 0.11) % 1) * fSpan;
      sampleFlow(headY - fTop);
      const headSize = (smallView ? 30 : 44) * flowAlpha;
      ctx.drawImage(sprites[FLARE], fOx + wiggle - headSize * 0.5, headY - headSize * 0.5, headSize, headSize);
    }
    if (graphAlpha > 0.01) drawLabels(graphAlpha);
  }

  /**
   * Renders the static presentation (reduced motion): the agent graph and its clusters.
   * Pages without #agent-stage get the graph at alpha 0.4 over the full viewport and no labels.
   */
  function renderStatic(): void {
    if (!viewW) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = '#05040d';
    ctx.fillRect(0, 0, viewW, viewH);
    let rect: ViewRect = { left: 0, top: 0, width: viewW, height: viewH };
    if (viewW >= 1024 && stage) {
      const sr = stage.getBoundingClientRect(), hh = header ? header.getBoundingClientRect().height : 0;
      rect = { left: sr.left, top: hh, width: sr.width, height: viewH - hh };
    }
    layoutClusters(rect, 0);
    ctx.globalCompositeOperation = 'lighter';
    drawGraph(stage ? 0.85 : 0.4, 0.35, 2);
    const limit = Math.min(count, smallView ? 450 : 1200), sc = smallView ? 0.75 : 0.9;
    for (let i = 0; i < limit; i++) {
      if (r5[i] < 0.07) continue;
      placeAgentPoint(i, 0);
      const size = sz[i] * sc * (lit[i] ? 1.5 : 1);
      ctx.drawImage(sprites[lit[i] && (i & 3) === 0 ? HOT : col[i]], tx[i] - size * 0.5, ty[i] - size * 0.5, size, size);
    }
    if (stage) drawLabels(0.9);
  }

  /** Animation frame: advances clocks, hold, targets, physics, render, decode and the perf watchdog. */
  function runFrame(ts: number): void {
    rafId = 0;
    if (!isLive || document.hidden) return;
    if (!lastTs) lastTs = ts;
    let dt = (ts - lastTs) / 1000;
    lastTs = ts;
    if (dt > 0.05) dt = 0.05;
    if (dt > 0) {
      const startMs = nowMs();
      clock += dt; modeT += dt; labT += dt;
      const holding = pointer.down && (pointer.locked || (!pointer.moved && nowMs() - pointer.t0 > 420));
      if (holding) pointer.locked = true;
      pointer.hold += ((holding ? 1 : 0) - pointer.hold) * Math.min(1, dt * (holding ? 2.6 : 3.5));
      graphAlpha += ((mode === 'agents' ? 1 : 0) - graphAlpha) * Math.min(1, dt * 3);
      flowAlpha += ((mode === 'workflow' ? 1 : 0) - flowAlpha) * Math.min(1, dt * 3);
      computeTargets(dt);
      buildGrid();
      simulate(dt);
      draw(dt);
      const workMs = nowMs() - startMs;
      stepDecodeTasks(dt);
      if (clock > 1.5) {
        perfAcc += workMs; perfFrames++; perfWindow += dt;
        if (perfWindow > 2.5) {
          if (perfAcc / perfFrames > 12 && count > 300) { perfScale *= 0.75; count = computeCount(); heroW = 0; }
          perfAcc = 0; perfFrames = 0; perfWindow = 0;
        }
      }
    }
    rafId = window.requestAnimationFrame(runFrame);
  }

  /** Requests the next frame when live, visible and not already scheduled. */
  function scheduleFrame(): void {
    if (!rafId && isLive && !document.hidden) rafId = window.requestAnimationFrame(runFrame);
  }

  /** Enters live motion. */
  function startSwarm(): void {
    if (isLive) return;
    isLive = true; lastTs = 0;
    root.classList.add('swarm-live');
    heroW = 0;
    initDecode();
    if (!seqUsed) startSequence(1.5);
    scheduleFrame();
  }

  /** Leaves live motion and paints the static presentation. */
  function stopSwarm(): void {
    isLive = false;
    if (rafId) { window.cancelAnimationFrame(rafId); rafId = 0; }
    root.classList.remove('swarm-live');
    finishDecode();
    endSequence();
    labT = 99;
    renderStatic();
  }

  /** Resolves the active section's workflow (.flow, .beat) and install ([data-orbit]) targets. */
  function resolveSectionTargets(section: Element | null): void {
    flowEl = section ? findInSection(section, '.flow') : null;
    beatEls = flowEl ? flowEl.querySelectorAll('.beat') : [];
    orbitEl = section ? findInSection(section, '[data-orbit]') : null;
  }

  /** Switches the formation to section; a different element always restarts the formation. */
  function activateSection(section: Element | null): void {
    if (!section || section === activeSection) return;
    activeSection = section;
    mode = readFormation(section);
    modeT = 0;
    heroW = 0; flowW = 0;
    resolveSectionTargets(section);
    if (mode !== 'hero' && seqOn) endSequence();
    if (mode === 'agents') labT = 0;
  }

  /** IntersectionObserver callback for [data-formation] sections crossing the viewport midline. */
  function handleSectionEntries(entries: IntersectionObserverEntry[]): void {
    for (let e = 0; e < entries.length; e++) {
      if (entries[e].isIntersecting) activateSection(entries[e].target);
    }
  }

  /** Scroll fallback when IntersectionObserver is unavailable: picks the section under the midline. */
  function handleScrollFallback(): void {
    const mid = (window.innerHeight || viewH) * 0.5;
    for (let s = 0; s < sections.length; s++) {
      const box = sections[s].getBoundingClientRect();
      if (box.top <= mid && box.bottom >= mid) { activateSection(sections[s]); break; }
    }
  }

  /** Tracks the pointer as the swarm's predator and detects drag versus hold. */
  function handlePointerMove(evt: PointerEvent): void {
    pointer.x = evt.clientX; pointer.y = evt.clientY;
    if (evt.pointerType === 'mouse' || pointer.down) pointer.on = true;
    if (pointer.down && !pointer.moved) {
      const dx = evt.clientX - pointer.x0, dy = evt.clientY - pointer.y0;
      if (dx * dx + dy * dy > 144) pointer.moved = true;
    }
  }

  /** Starts a potential press-hold convergence. */
  function handlePointerDown(evt: PointerEvent): void {
    if (evt.isPrimary === false) return;
    pointer.down = true; pointer.moved = false; pointer.locked = false;
    pointer.t0 = nowMs(); pointer.x0 = evt.clientX; pointer.y0 = evt.clientY;
    handlePointerMove(evt);
  }

  /** Releases the press; touch pointers stop scattering on release. */
  function handlePointerUp(evt: PointerEvent): void {
    pointer.down = false; pointer.locked = false;
    if (evt.pointerType !== 'mouse') pointer.on = false;
  }

  /** Cancels all pointer influence. */
  function handlePointerCancel(): void {
    pointer.down = false; pointer.locked = false; pointer.on = false;
  }

  /** Lights cluster k (or none for -1) on cards and the canvas. */
  function setLitCluster(k: number): void {
    litCluster = k;
    for (let c = 0; c < cards.length; c++) cards[c].classList.toggle('is-lit', Number(cards[c].getAttribute('data-cluster')) === k);
    if (!isLive) {
      for (let q = 0; q < 6; q++) litAmt[q] = q === k ? 1 : 0;
      renderStatic();
    }
  }

  /** Binds hover (mouse) and tap toggle (touch, pen) lighting to one [data-cluster] card. */
  function bindCard(card: HTMLElement): void {
    const k = Number(card.getAttribute('data-cluster'));
    card.addEventListener('pointerenter', (evt) => { if (evt.pointerType === 'mouse') setLitCluster(k); }, passive);
    card.addEventListener('pointerleave', (evt) => { if (evt.pointerType === 'mouse' && litCluster === k) setLitCluster(-1); }, passive);
    card.addEventListener('pointerup', (evt) => { if (evt.pointerType !== 'mouse') setLitCluster(litCluster === k ? -1 : k); }, passive);
  }

  /** Mirrors the real line breaks so sub-pixel drift can never rewrap the overlay. */
  function mirrorLineBreak(rec: DecodeRecord, range: Range, textNode: Node, offset: number, dst: Node): void {
    range.setStart(textNode, offset); range.setEnd(textNode, offset + 1);
    const rects = range.getClientRects(), top = rects.length ? rects[0].top : rec.lineTop;
    if (rec.lineTop > -1e8 && top > rec.lineTop + rec.lineHalf) dst.appendChild(document.createElement('br'));
    rec.lineTop = top;
    if (rects.length) rec.lineHalf = rects[0].height * 0.5;
  }

  /** Appends one decode cell per non-space character of textNode into dst. */
  function appendTextCells(textNode: Node, dst: Node, rec: DecodeRecord): void {
    const text = textNode.nodeValue || '';
    let pendingSpace = '';
    for (let j = 0; j < text.length; j++) {
      const ch = text.charAt(j);
      if (ch <= ' ') { pendingSpace += ch; continue; }
      if (pendingSpace) { dst.appendChild(document.createTextNode(pendingSpace)); pendingSpace = ''; }
      if (rec.range) mirrorLineBreak(rec, rec.range, textNode, j, dst);
      const cell = document.createElement('span'), alt = Math.random() < 0.4 ? ' c1' : '';
      cell.textContent = ch;
      if (rec.glyph) {
        const glyph = createGlyphSvg('gly', randomInt(NG));
        cell.className = 'gc' + alt;
        cell.appendChild(glyph.svg);
        rec.glyphCells.push({ span: cell, use: glyph.use, at: 0, ok: 0 });
      } else {
        cell.className = 'cc' + alt;
        cell.setAttribute('data-c', randomPoolChar());
        rec.scrambleCells.push(cell); rec.base.push(cell.className);
      }
      dst.appendChild(cell);
    }
    if (pendingSpace) dst.appendChild(document.createTextNode(pendingSpace));
  }

  /** Recursively mirrors src into dst as decode cells; cloned elements drop their id. */
  function buildDecodeCells(src: Node, dst: Node, rec: DecodeRecord): void {
    for (let child = src.firstChild; child; child = child.nextSibling) {
      if (child.nodeType === 3) {
        appendTextCells(child, dst, rec);
      } else if (child.nodeType === 1) {
        const clone = child.cloneNode(false) as Element;
        clone.removeAttribute('id');
        dst.appendChild(clone);
        buildDecodeCells(child, clone, rec);
      }
    }
  }

  /** Mounts the aria-hidden decode overlay on rec.el. */
  function mountDecode(rec: DecodeRecord): void {
    if (rec.ov) return;
    rec.glyphCells = []; rec.scrambleCells = []; rec.base = []; rec.lineTop = -1e9; rec.lineHalf = 6;
    rec.range = typeof document.createRange === 'function' ? document.createRange() : null;
    if (rec.range && typeof rec.range.getClientRects !== 'function') rec.range = null;
    const overlay = document.createElement('span');
    overlay.className = 'dx-ov';
    overlay.setAttribute('aria-hidden', 'true');
    overlay.style.setProperty('--dx-c', rec.color);
    buildDecodeCells(rec.el, overlay, rec);
    rec.el.appendChild(overlay);
    rec.ov = overlay;
    rec.el.classList.add('dx-on');
    rec.el.classList.remove('dx-wait');
  }

  /** Removes the decode overlay and reveals the real text. */
  function unmountDecode(rec: DecodeRecord): void {
    rec.running = false;
    if (rec.ov && rec.ov.parentNode) rec.ov.parentNode.removeChild(rec.ov);
    rec.ov = null; rec.glyphCells = []; rec.scrambleCells = []; rec.base = [];
    rec.el.classList.remove('dx-on');
    rec.el.classList.remove('dx-wait');
  }

  /** Mounts rec and queues a decode task lasting dur ms after delay ms. */
  function runDecode(rec: DecodeRecord, dur: number, delay: number): void {
    mountDecode(rec);
    rec.running = rec.started = true;
    const cells = rec.glyphCells;
    let end = dur;
    if (rec.glyph) {
      const per = dur / Math.max(cells.length, 1);
      for (let j = 0; j < cells.length; j++) { cells[j].at = j * per + Math.random() * per * 2.2; if (cells[j].at > end) end = cells[j].at; }
    }
    decodeTasks.push({ rec, cells, spans: rec.scrambleCells, base: rec.base, elapsed: -delay, acc: 0, front: 0, end, dur });
  }

  /** Advances a glyph-heading decode; returns true when finished. */
  function stepGlyphTask(task: DecodeTask, tick: boolean): boolean {
    for (let q = 0; q < task.cells.length; q++) {
      const cell = task.cells[q];
      if (cell.ok) continue;
      if (task.elapsed >= cell.at) { cell.ok = 1; cell.span.className = 'gc ok'; }
      else if (tick && Math.random() < 0.6) cell.use.setAttribute('href', '#g' + randomInt(NG));
    }
    if (task.elapsed >= task.end + 560) { unmountDecode(task.rec); return true; }
    return false;
  }

  /** Advances a body-text scramble decode; returns true when finished. */
  function stepScrambleTask(task: DecodeTask, tick: boolean): boolean {
    const spans = task.spans, total = spans.length;
    const progress = Math.min(task.elapsed / task.dur, 1);
    const front = progress >= 1 ? total : Math.floor(total * progress * (2 - progress));
    if (front > task.front) {
      for (let q = task.front; q < front; q++) spans[q].className = 'cc ok';
      for (let q = front; q < front + 3 && q < total; q++) spans[q].className = task.base[q] + ' fr';
      task.front = front;
    }
    if (tick) for (let q = front + 3; q < total; q++) if (Math.random() < 0.4) spans[q].setAttribute('data-c', randomPoolChar());
    if (progress >= 1) { unmountDecode(task.rec); return true; }
    return false;
  }

  /** Advances one decode task by dt seconds; only visible records progress. Returns true when done. */
  function stepDecodeTask(task: DecodeTask, dt: number): boolean {
    if (!task.rec.running) return true;
    if (!task.rec.vis) return false;
    task.elapsed += dt * 1000;
    if (task.elapsed < 0) return false;
    task.acc += dt * 1000;
    const tick = task.acc >= 55;
    if (tick) task.acc = 0;
    return task.rec.glyph ? stepGlyphTask(task, tick) : stepScrambleTask(task, tick);
  }

  /** Starts rec's first decode with a stagger delay; hero-section text waits an extra 450 ms. */
  function beginDecode(rec: DecodeRecord, delay: number): void {
    if (rec.started || !isLive) return;
    const len = (rec.el.textContent || '').length;
    runDecode(rec, rec.glyph ? clamp(480 + len * 30, 600, 1500) : clamp(len * 7, 700, 1700), delay + rec.d0);
  }

  /** Steps every queued decode task (rAF batched), dropping finished ones. */
  function stepDecodeTasks(dt: number): void {
    for (let j = decodeTasks.length - 1; j >= 0; j--) if (stepDecodeTask(decodeTasks[j], dt)) decodeTasks.splice(j, 1);
  }

  /** Builds the decode record for one .xg or .xs element. */
  function createDecodeRecord(el: HTMLElement): DecodeRecord {
    return {
      el, glyph: el.classList.contains('xg'), color: window.getComputedStyle(el).color,
      d0: el.closest('[data-formation="hero"]') ? 450 : 0, vis: false, started: false, running: false,
      ov: null, glyphCells: [], scrambleCells: [], base: [], range: null, lineTop: -1e9, lineHalf: 6,
    };
  }

  /** IntersectionObserver callback: tracks visibility and starts decodes as text scrolls in. */
  function handleDecodeEntries(entries: IntersectionObserverEntry[]): void {
    let stagger = 0;
    for (let q = 0; q < entries.length; q++) {
      const rec = byEl.get(entries[q].target);
      if (!rec) continue;
      rec.vis = entries[q].isIntersecting;
      if (rec.vis && !rec.started) beginDecode(rec, Math.min(stagger++, 6) * 110);
    }
  }

  /** Registers every .xg and .xs element for decode, once, when IntersectionObserver exists. */
  function initDecode(): void {
    if (decodeReady || !hasIO) return;
    decodeReady = true;
    const els = document.querySelectorAll<HTMLElement>('.xg, .xs');
    for (let e = 0; e < els.length; e++) {
      const rec = createDecodeRecord(els[e]);
      recs.push(rec); byEl.set(rec.el, rec);
    }
    for (let e = 0; e < recs.length; e++) { recs[e].el.classList.add('dx'); recs[e].el.classList.add('dx-wait'); }
    const decodeObserver = new IntersectionObserver(handleDecodeEntries, { rootMargin: '0px' });
    for (let e = 0; e < recs.length; e++) decodeObserver.observe(recs[e].el);
  }

  /** Completes every decode immediately and clears the task queue. */
  function finishDecode(): void {
    for (let e = 0; e < recs.length; e++) { recs[e].started = true; unmountDecode(recs[e]); }
    decodeTasks.length = 0;
  }

  /** Tap a heading for a brief re-encode; tap the wordmark to replay its glyph sequence. */
  function handleReencodeClick(evt: MouseEvent): void {
    if (!isLive) return;
    const target = evt.target;
    const heading = target instanceof Element ? target.closest('.xg, .wordmark') : null;
    if (!heading) return;
    if (heading === heroWord) { if (!seqOn && glyphOK && mode === 'hero') startSequence(0.8); return; }
    const rec = byEl.get(heading);
    if (!rec || rec.running || !rec.started) return;
    rec.vis = true;
    runDecode(rec, clamp(260 + (heading.textContent || '').length * 22, 420, 900), 0);
  }

  /** Debounces resize by 120 ms. */
  function handleResizeEvent(): void {
    window.clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(resize, 120);
  }

  /** Pauses the loop while the document is hidden. */
  function handleVisibility(): void {
    if (document.hidden) { if (rafId) { window.cancelAnimationFrame(rafId); rafId = 0; } }
    else { lastTs = 0; scheduleFrame(); }
  }

  const motionQuery: MediaQueryList | null = typeof window.matchMedia === 'function'
    ? window.matchMedia('(prefers-reduced-motion: reduce)')
    : null;

  /** Applies the current reduced-motion preference; a missing matchMedia means motion on. */
  function applyMotion(): void {
    if (motionQuery && motionQuery.matches) stopSwarm();
    else startSwarm();
  }

  resolveSectionTargets(activeSection);
  if (hasIO) {
    const sectionObserver = new IntersectionObserver(handleSectionEntries, { rootMargin: '-48% 0px -48% 0px', threshold: 0 });
    for (let s = 0; s < sections.length; s++) sectionObserver.observe(sections[s]);
  } else {
    window.addEventListener('scroll', handleScrollFallback, passive);
  }

  window.addEventListener('pointermove', handlePointerMove, passive);
  window.addEventListener('pointerdown', handlePointerDown, passive);
  window.addEventListener('pointerup', handlePointerUp, passive);
  window.addEventListener('pointercancel', handlePointerCancel, passive);
  root.addEventListener('pointerleave', (evt) => { if (evt.pointerType === 'mouse') handlePointerCancel(); }, passive);
  window.addEventListener('blur', handlePointerCancel, passive);
  for (let ci = 0; ci < cards.length; ci++) bindCard(cards[ci]);
  document.addEventListener('click', handleReencodeClick);
  window.addEventListener('resize', handleResizeEvent, passive);
  document.addEventListener('visibilitychange', handleVisibility);

  resize();
  seedParticles();
  booted = true;
  applyMotion();
  if (motionQuery) {
    if (typeof motionQuery.addEventListener === 'function') motionQuery.addEventListener('change', applyMotion);
    else if (typeof motionQuery.addListener === 'function') motionQuery.addListener(applyMotion);
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
