import { vi } from 'vitest';

// ---------------------------------------------------------------------------
// Harness for booting the COMPILED Swarm Glyph engine (web/scripts/main.js) against
// a jsdom DOM with controllable fakes for the browser APIs main.ts touches.
//
// Decision: fakes are HAND-ROLLED (not jsdom-testing-mocks / vitest-canvas-mock).
// The suites need precise, per-test control: toggle matchMedia legacy vs modern,
// fire IntersectionObserver entries manually on a chosen observer, delete IO to hit
// the absent branch, drive rAF frames with explicit timestamps, and assert 2d-context
// CALL occurrence. A hand-rolled surface exposes all of that directly; third-party libs
// would hide it behind their own conventions.
// ---------------------------------------------------------------------------

// Path relative to this helper. main.ts has no exports and self-boots on evaluation,
// so importing this file runs init() against the current DOM.
const COMPILED_MAIN = '../../scripts/main.js';

// ---------------------------------------------------------------------------
// matchMedia fake
// ---------------------------------------------------------------------------

export interface FakeMediaQueryList {
  matches: boolean;
  media: string;
  onchange: null;
  // Modern listeners (omitted entirely when `legacy` is set).
  addEventListener?: (type: string, listener: (e: MediaQueryListEvent) => void) => void;
  removeEventListener?: (type: string, listener: (e: MediaQueryListEvent) => void) => void;
  dispatchEvent?: (event: Event) => boolean;
  // Legacy WebKit listeners (always present so the deprecated path can be exercised).
  addListener: (listener: (e: MediaQueryListEvent) => void) => void;
  removeListener: (listener: (e: MediaQueryListEvent) => void) => void;
  // Test-only: drive a live preference change to all registered listeners.
  _fireChange: (matches: boolean) => void;
}

export interface MatchMediaOptions {
  // Initial value of MediaQueryList.matches (i.e. prefers-reduced-motion state).
  matches?: boolean;
  // When true, the MediaQueryList omits addEventListener and exposes only the
  // deprecated addListener, exercising main.ts's legacy WebKit fallback path.
  legacy?: boolean;
}

// Install window.matchMedia. Call BEFORE bootMain: init() reads matchMedia once while
// booting and holds the returned MediaQueryList. Returns that MediaQueryList so a test
// can call `_fireChange` to drive live preference changes. Leaving matchMedia absent is
// a supported engine path (motion on).
export function installMatchMedia(opts: MatchMediaOptions = {}): FakeMediaQueryList {
  const matches = opts.matches ?? false;
  const legacy = opts.legacy ?? false;
  const changeListeners = new Set<(e: MediaQueryListEvent) => void>();

  const mql: FakeMediaQueryList = {
    matches,
    media: '(prefers-reduced-motion: reduce)',
    onchange: null,
    addListener: (listener) => changeListeners.add(listener),
    removeListener: (listener) => changeListeners.delete(listener),
    _fireChange(next: boolean) {
      this.matches = next;
      const event = { matches: next, media: this.media } as MediaQueryListEvent;
      changeListeners.forEach((listener) => listener(event));
    },
  };

  if (!legacy) {
    mql.addEventListener = (_type, listener) => changeListeners.add(listener);
    mql.removeEventListener = (_type, listener) => changeListeners.delete(listener);
    mql.dispatchEvent = () => true;
  }

  Object.defineProperty(window, 'matchMedia', {
    configurable: true,
    writable: true,
    value: vi.fn(() => mql),
  });
  return mql;
}

// ---------------------------------------------------------------------------
// IntersectionObserver fake
// ---------------------------------------------------------------------------

export interface FakeIntersectionObserver {
  callback: IntersectionObserverCallback;
  options?: IntersectionObserverInit;
  observed: Element[];
  observe: (el: Element) => void;
  unobserve: (el: Element) => void;
  disconnect: () => void;
  // Test-only: invoke the observer callback with synthetic entries.
  trigger: (entries: Array<Partial<IntersectionObserverEntry> & { target: Element }>) => void;
}

// Registry of all IntersectionObserver instances main.js constructs during a boot.
// The engine builds two: the sections observer and the decode observer.
const intersectionObservers: FakeIntersectionObserver[] = [];

// Install a controllable IntersectionObserver. Returns the registry array (shared
// reference) so a test can locate a created instance (see findObserver) and call
// `.trigger(...)` with synthetic entries.
export function installIntersectionObserver(): FakeIntersectionObserver[] {
  intersectionObservers.length = 0;

  class IO {
    constructor(callback: IntersectionObserverCallback, options?: IntersectionObserverInit) {
      const instance: FakeIntersectionObserver = {
        callback,
        options,
        observed: [],
        observe: (el: Element) => {
          instance.observed.push(el);
        },
        unobserve: (el: Element) => {
          instance.observed = instance.observed.filter((e) => e !== el);
        },
        disconnect: () => {
          instance.observed = [];
        },
        trigger: (entries) => {
          callback(
            entries as unknown as IntersectionObserverEntry[],
            instance as unknown as IntersectionObserver,
          );
        },
      };
      intersectionObservers.push(instance);
      // Return the plain instance so main.js's `new IntersectionObserver(...)` yields
      // an object exposing observe/unobserve/disconnect.
      return instance as unknown as IO;
    }
  }

  Object.defineProperty(window, 'IntersectionObserver', {
    configurable: true,
    writable: true,
    value: IO as unknown as typeof IntersectionObserver,
  });
  return intersectionObservers;
}

// Locate a created observer by its rootMargin option rather than by creation order.
// The engine's sections observer uses '-48% 0px -48% 0px'; its decode observer '0px'.
// Throws when no observer matches, so a missing observer fails loudly.
export function findObserver(
  registry: FakeIntersectionObserver[],
  rootMargin: string,
): FakeIntersectionObserver {
  const found = registry.find((observer) => observer.options?.rootMargin === rootMargin);
  if (!found) {
    throw new Error(`No IntersectionObserver with rootMargin "${rootMargin}" was created`);
  }
  return found;
}

// Delete IntersectionObserver from the global to exercise main.js's absent branch
// (`typeof IntersectionObserver === 'function'` false). Call BEFORE bootMain.
export function removeIntersectionObserver(): void {
  intersectionObservers.length = 0;
  Reflect.deleteProperty(window, 'IntersectionObserver');
  Reflect.deleteProperty(globalThis as unknown as Record<string, unknown>, 'IntersectionObserver');
}

// ---------------------------------------------------------------------------
// requestAnimationFrame / cancelAnimationFrame fakes
// ---------------------------------------------------------------------------

// Install rAF/cAF fakes. resetHarnessGlobals deletes jsdom's own rAF, so a test that
// does not call installRaf boots with requestAnimationFrame absent (the engine's
// no-rAF early return).
//
// These fakes do NOT auto-run the callback: the engine's frame loop re-schedules itself,
// so auto-run would loop unbounded. The returned controller lets a test flush a single
// frame deliberately. `flushOne(ts)` passes an explicit timestamp for deterministic
// time; omitted, it passes performance.now().
export interface RafController {
  flushOne: (ts?: number) => void;
  pending: () => number;
}

export function installRaf(): RafController {
  let nextId = 1;
  const callbacks = new Map<number, FrameRequestCallback>();

  Object.defineProperty(window, 'requestAnimationFrame', {
    configurable: true,
    writable: true,
    value: (cb: FrameRequestCallback): number => {
      const id = nextId++;
      callbacks.set(id, cb);
      return id;
    },
  });
  Object.defineProperty(window, 'cancelAnimationFrame', {
    configurable: true,
    writable: true,
    value: (id: number): void => {
      callbacks.delete(id);
    },
  });

  return {
    flushOne(ts?: number) {
      const entry = callbacks.entries().next();
      if (entry.done) return;
      const [id, cb] = entry.value;
      callbacks.delete(id);
      cb(ts ?? performance.now());
    },
    pending() {
      return callbacks.size;
    },
  };
}

// ---------------------------------------------------------------------------
// Canvas 2d context spy
// ---------------------------------------------------------------------------

type SpyFn = ReturnType<typeof vi.fn>;

// Every 2d-context member web/src/main.ts touches, on the #swarm context, the glow
// sprite contexts and the hero/glyph scratch contexts.
export type Canvas2dSpy = {
  clearRect: SpyFn;
  fillRect: SpyFn;
  beginPath: SpyFn;
  arc: SpyFn;
  fill: SpyFn;
  stroke: SpyFn;
  moveTo: SpyFn;
  lineTo: SpyFn;
  quadraticCurveTo: SpyFn;
  drawImage: SpyFn;
  fillText: SpyFn;
  setTransform: SpyFn;
  save: SpyFn;
  restore: SpyFn;
  translate: SpyFn;
  scale: SpyFn;
  createRadialGradient: SpyFn;
  getImageData: SpyFn;
  measureText: SpyFn;
  fillStyle: unknown;
  strokeStyle: unknown;
  globalCompositeOperation: string;
  globalAlpha: number;
  lineWidth: number;
  lineCap: string;
  lineJoin: string;
  font: string;
  textAlign: string;
  textBaseline: string;
  letterSpacing: string;
};

// Builds a fresh spy 2d context. getImageData returns a zeroed buffer sized to the
// requested region (never smaller than one pixel); measureText reports a fixed width.
function createCanvas2dSpy(): Canvas2dSpy {
  return {
    clearRect: vi.fn(),
    fillRect: vi.fn(),
    beginPath: vi.fn(),
    arc: vi.fn(),
    fill: vi.fn(),
    stroke: vi.fn(),
    moveTo: vi.fn(),
    lineTo: vi.fn(),
    quadraticCurveTo: vi.fn(),
    drawImage: vi.fn(),
    fillText: vi.fn(),
    setTransform: vi.fn(),
    save: vi.fn(),
    restore: vi.fn(),
    translate: vi.fn(),
    scale: vi.fn(),
    createRadialGradient: vi.fn(() => ({ addColorStop: vi.fn() })),
    getImageData: vi.fn((_x: number, _y: number, w: number, h: number) => ({
      data: new Uint8ClampedArray(Math.max(4, w * h * 4)),
    })),
    measureText: vi.fn(() => ({ width: 6 })),
    fillStyle: '',
    strokeStyle: '',
    globalCompositeOperation: 'source-over',
    globalAlpha: 1,
    lineWidth: 1,
    lineCap: 'butt',
    lineJoin: 'miter',
    font: '',
    textAlign: 'start',
    textBaseline: 'alphabetic',
    letterSpacing: '0px',
  };
}

// Stub HTMLCanvasElement.getContext('2d') with ONE shared spy 2d context, returned for
// every canvas (the #swarm canvas and the detached sprite/scratch canvases alike).
// jsdom returns null, which would make main.js take its no-context early return.
// Returns the spy so a test can assert CALL occurrence, never pixel output.
export function installCanvas2dContext(): Canvas2dSpy {
  const spy = createCanvas2dSpy();
  Object.defineProperty(HTMLCanvasElement.prototype, 'getContext', {
    configurable: true,
    writable: true,
    value: vi.fn((type: string) => (type === '2d' ? spy : null)),
  });
  return spy;
}

// ---------------------------------------------------------------------------
// document.hidden / visibilitychange driver
// ---------------------------------------------------------------------------

// Set document.hidden. jsdom does not let the tab go hidden on its own, so the
// visibilitychange handler in main.js is only reachable via this + dispatchVisibilityChange.
export function setDocumentHidden(value: boolean): void {
  Object.defineProperty(document, 'hidden', {
    configurable: true,
    get: () => value,
  });
}

// Dispatch a synthetic visibilitychange event. The real browser fires this on tab
// switches; jsdom never does, so the pause/resume path is characterizable only here.
export function dispatchVisibilityChange(): void {
  document.dispatchEvent(new Event('visibilitychange'));
}

// ---------------------------------------------------------------------------
// Boot-time listener tracking
// ---------------------------------------------------------------------------

interface TrackedListener {
  target: EventTarget;
  type: string;
  listener: EventListenerOrEventListenerObject;
  options?: boolean | EventListenerOptions;
}

// Listeners the engine registered on window, document and <html> during bootMain.
// Those targets outlive a test (only body/head are wiped), so a previous boot's
// visibilitychange or click handler would otherwise keep firing into the next test.
const bootListeners: TrackedListener[] = [];

// Replace target.addEventListener with a recording wrapper; returns a restore function
// that puts the original property descriptor back (or removes the own property).
function trackListenersOn(target: EventTarget): () => void {
  const original = target.addEventListener;
  const ownDescriptor = Object.getOwnPropertyDescriptor(target, 'addEventListener');
  Object.defineProperty(target, 'addEventListener', {
    configurable: true,
    writable: true,
    value: (
      type: string,
      listener: EventListenerOrEventListenerObject | null,
      options?: boolean | AddEventListenerOptions,
    ) => {
      if (listener) bootListeners.push({ target, type, listener, options });
      original.call(target, type, listener, options);
    },
  });
  return () => {
    if (ownDescriptor) Object.defineProperty(target, 'addEventListener', ownDescriptor);
    else Reflect.deleteProperty(target, 'addEventListener');
  };
}

// Remove every listener recorded by bootMain.
function removeBootListeners(): void {
  for (const tracked of bootListeners) {
    tracked.target.removeEventListener(tracked.type, tracked.listener, tracked.options);
  }
  bootListeners.length = 0;
}

// ---------------------------------------------------------------------------
// Reset
// ---------------------------------------------------------------------------

// Tear down every harness-installed global and registry. Called by setup before/after
// each test so no fake leaks across tests. INVARIANT: this must remove anything the
// installers and bootMain add (matchMedia, IntersectionObserver, rAF/cAF, getContext,
// document.hidden, document.readyState, boot-time listeners).
export function resetHarnessGlobals(): void {
  removeBootListeners();
  Reflect.deleteProperty(window, 'matchMedia');
  Reflect.deleteProperty(window, 'IntersectionObserver');
  Reflect.deleteProperty(globalThis as unknown as Record<string, unknown>, 'IntersectionObserver');
  Reflect.deleteProperty(window, 'requestAnimationFrame');
  Reflect.deleteProperty(window, 'cancelAnimationFrame');
  Reflect.deleteProperty(HTMLCanvasElement.prototype, 'getContext');
  Reflect.deleteProperty(document, 'readyState');
  // Restore document.hidden to a plain false value owned by the test harness.
  Object.defineProperty(document, 'hidden', {
    configurable: true,
    get: () => false,
  });
  intersectionObservers.length = 0;
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

export interface BootOptions {
  // 'loading' makes main.js wait for DOMContentLoaded (which bootMain then dispatches);
  // 'complete' makes it call init() synchronously on import. Default: 'complete'.
  readyState?: DocumentReadyState;
}

// Boot the compiled engine against the already-mounted DOM.
//
// CONTRACT:
//  1. Mount your fixture DOM (via fixtures/ loaders) and install whichever fakes the
//     test needs BEFORE calling bootMain. bootMain installs NO fakes itself.
//  2. bootMain sets document.readyState, then fresh-imports web/scripts/main.js while
//     recording the listeners it adds to window, document and <html> (removed again by
//     resetHarnessGlobals).
//
// Fresh boot is achieved with vi.resetModules() + dynamic import(): the compiled module
// has module-level side effects (it self-runs init()), and a second import in the same
// process returns the cached instance WITHOUT re-running init(). resetModules clears that
// cache so each call re-evaluates the module against the current DOM.
export async function bootMain(opts: BootOptions = {}): Promise<void> {
  const readyState = opts.readyState ?? 'complete';
  Object.defineProperty(document, 'readyState', {
    configurable: true,
    get: () => readyState,
  });

  const restorers = [window, document, document.documentElement].map(trackListenersOn);
  try {
    vi.resetModules();
    await import(/* @vite-ignore */ COMPILED_MAIN);

    // When readyState was 'loading', main.js registered a DOMContentLoaded listener
    // instead of calling init(); fire it so init() runs against the fixture DOM.
    if (readyState === 'loading') {
      document.dispatchEvent(new Event('DOMContentLoaded'));
    }
  } finally {
    restorers.forEach((restore) => restore());
  }
}
