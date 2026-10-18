# web/tests: Characterization test charter

This suite is a **Feathers-style characterization (pinning) safety net** for the
Swarm Glyph engine (`web/src/main.ts`, compiled to `web/scripts/main.js`). Its job is
to lock in the *current observable behavior* of the shipped site so a future refactor
can be made with confidence that nothing changed.

## Organizing principle

> Characterization tests describe the software **as it is**, not as it should be.

These tests are a behavior-pinning net, not a correctness spec. They exist to make
a later refactor safe, not to assert the code is "right".

## The rules

1. **Pin CURRENT behavior, never desired behavior.** If the code does something
   surprising, the test pins it *as-is*.
2. **Suspected bugs/quirks are pinned, not fixed.** Annotate them with a
   `// PINNED QUIRK` comment explaining what looks wrong and why we are pinning it
   anyway. A fix is a separate, deliberate change, never a side effect of adding a
   test.
3. **Pin observable contracts only.** Acceptable to assert:
   - root classes on `<html>` (`swarm-ready`, `swarm-live`)
   - decode classes and nodes (`dx`, `dx-wait`, `dx-on`, the `aria-hidden` `.dx-ov`
     overlay, id-free cloned descendants)
   - card lighting (`is-lit` on `[data-cluster]` cards)
   - generated glyph defs (`svg.gdefs > defs > symbol#g0..g23`, single instance)
   - presence of the single `#swarm` `<canvas>` in the document
   - canvas 2d-context **call occurrence** (e.g. `fillRect` was called), never arguments
   - whether a frame is pending (`requestAnimationFrame` scheduled or cancelled)
   - which observer watches which elements, located by options (`rootMargin`)
   - which code branch was taken (IO present vs absent, reduced-motion on vs off,
     matchMedia modern vs legacy vs absent, canvas/context/rAF present vs absent)
4. **NEVER pin nondeterministic internals.** Off-limits:
   - particle positions, velocities, counts, sizes or colors
   - pixel/numeric canvas output or drawing arguments
   - `requestAnimationFrame` timing or frame counts (frames are flushed until a
     contract holds, under a cap, never counted)
   - anything seeded by `Math.random()` (scramble characters, glyph picks, delays)

## Decision: test the COMPILED artifact

The unit under test is **`web/scripts/main.js`** (the compiled output that the three
HTML pages actually load via `<script type="module" src="./scripts/main.js">`), NOT
the `.ts` source. `web/scripts/` is gitignored, so a fresh checkout has no `main.js`;
you **must** run `npm run build` (tsc) before the tests can import it.

## How to run

```sh
npm run build && npm test
```

`npm run build` compiles `web/src/main.ts` to `web/scripts/main.js`.
`npm test` runs Vitest (jsdom environment) against the compiled file.

## Suites

| Suite | Pins |
| --- | --- |
| `boot-smoke.test.ts` | Harness proof: index boots live (`swarm-ready`, `swarm-live`), glyph defs `g0..g23`, every `.xg`/`.xs` gets `dx` plus `dx-wait`, a frame is pending. |
| `swarm-canvas.jsdom.test.ts` | Canvas lifecycle: one canvas in the document, reduced-motion static paint, no-canvas / null-context / no-rAF early returns, live reduced-motion stop and resume, visibility pause and resume, sections observer wiring, formation frame smoke on all three pages, single glyph defs across stop/start. |
| `decode.test.ts` | Xenoglyph decode: reduced motion and IO-absent register nothing, overlay mount contract, overlay removal after frames, non-intersecting entries keep `dx-wait`. |
| `cluster-lighting.test.ts` | `is-lit` on `[data-cluster]` cards for mouse hover and touch tap toggle, with motion on and under reduced motion. |
| `fallback-branches.test.ts` | Legacy `addListener` path, matchMedia-absent boot (motion on), IO-absent boot (no throw, text not hidden). |
| `dom-contract.test.ts` | Static page contract (see `web/README.md`). |

### Retired suites

The prior engine's suites were deleted with the Swarm Glyph port, because the
features they pinned no longer exist:

- `nav-toggle.test.ts`: the nav drawer and its toggle were removed. Navigation is now
  a static wrapping nav with no script behavior; its markup is covered by
  `dom-contract.test.ts`.
- `glow-targets.test.ts`: the glow/pulse feature was deleted. Its successor, card
  cluster lighting, is pinned in `cluster-lighting.test.ts`.
- `scroll-reveal.test.ts`: scroll reveal was replaced by the xenoglyph decode,
  re-pinned in `decode.test.ts`.

## jsdom divergences from a real browser (documented, do NOT fight)

These are points where jsdom does not behave like a real browser. Tests must account
for them rather than try to force real-browser behavior:

- **`window.matchMedia` does not exist in jsdom.** The engine treats an absent
  matchMedia as motion on, so leaving it uninstalled is a supported path. When a test
  installs the fake it MUST do so before `bootMain`, because `init()` reads it once.
- **`IntersectionObserver` is not provided by jsdom.** The fake is controllable: its
  callback can be invoked manually with synthetic entries, and it can be deleted from
  the global to exercise the absent branch (scroll fallback, no decode registration).
- **`requestAnimationFrame` / `cancelAnimationFrame`.** The harness reset deletes
  jsdom's own rAF, so a test without `installRaf()` exercises the engine's no-rAF early
  return. NOTE: Vitest's `vi.useFakeTimers()` does NOT fake rAF/cAF by default.
- **`HTMLCanvasElement.getContext('2d')` returns `null` in jsdom.** The harness stubs
  it with one shared spy 2d context (see Harness API) returned for the `#swarm` canvas
  and for the detached sprite and scratch canvases alike. Assert *calls*, never pixels.
- **No `Path2D`.** The engine's glyph paths are null, so the hero glyph raster, glyph
  strokes and the wordmark glyph sequence (`wm-ov`, `wm-gl`, `wm-l`) are skipped
  entirely under jsdom. The wordmark sequence is uncharacterized here.
- **No `PointerEvent`.** Pointer events are dispatched as `MouseEvent`s whose
  `pointerType` is set with `Object.defineProperty`.
- **No `Range.getClientRects` (or `Range.getBoundingClientRect`).** The decode overlay
  skips its line-break mirroring, and the hero letter sampling path is unreachable.
- **Zero-size layout.** Every `getBoundingClientRect()` is all zeros and
  `documentElement.clientWidth` is 0 (the engine falls back to `window.innerWidth`).
  Formation geometry is degenerate, so formation tests are smoke only (no throw).
- **`visibilitychange` does not auto-fire in jsdom.** Set `document.hidden` via the
  helper and dispatch a synthetic `visibilitychange` event manually.
- **`<html>`, `window` and `document` outlive a test.** Only body and head are wiped
  between tests, so setup also clears `<html>` classes and the harness removes every
  listener the engine registered on those targets during `bootMain`.

## Uncharacterized: requires a real browser (deferred)

jsdom cannot honestly test these; they are explicitly out of scope for this suite:

1. **Canvas actual rendering / animation**: pixels, frame loop visuals, particle motion,
   formation geometry.
2. **The wordmark glyph sequence and glyph rasters** (need `Path2D`).
3. **Real `visibilitychange` firing** on real tab switches.
4. **Real `IntersectionObserver` geometry/threshold** on actual scroll position
   (sections observer midline band, decode observer entry).
5. **Real pointer input**: hover, tap, press-hold convergence on the swarm.

## PLAYWRIGHT TRIPWIRE

Add a Playwright suite when a change's scope actually touches swarm-canvas rendering,
the `visibilitychange` pause/resume logic, or the `IntersectionObserver` wiring.

**The tripwire FIRED with the Swarm Glyph port**, which rewrote all three areas.
The real-browser suite is tracked in
<https://github.com/brenpike/hivemind/issues/405>. Until it lands, jsdom plus
manually driven fakes cover the logic; real-browser-only API misuse in those areas is
the open gap.

## Harness API

See `web/tests/helpers/boot-main.ts` and `web/tests/fixtures/` for the importable
helpers. The contract:

- `installMatchMedia(opts)`: install the matchMedia fake. `opts.matches` sets the
  reduced-motion preference; `opts.legacy: true` produces a MediaQueryList that
  exposes only `addListener` (no `addEventListener`) to drive the legacy WebKit path.
  The returned list's `_fireChange(matches)` drives a live preference change.
- `installIntersectionObserver()`: install the controllable IO fake; returns a
  registry of created instances.
- `findObserver(registry, rootMargin)`: locate an observer by its options, not its
  creation order. The sections observer uses `'-48% 0px -48% 0px'`; the decode
  observer uses `'0px'`. Throws when none matches. Call `.trigger(entries)` on it.
- `removeIntersectionObserver()`: delete IO from the global to test the absent branch.
- `installRaf()`: install rAF/cAF fakes; returns `{ flushOne(ts?), pending() }`.
  `flushOne(ts)` runs one pending frame with an explicit timestamp for deterministic
  time (omitted, it uses `performance.now()`). Frames never auto-run.
- `installCanvas2dContext()`: stub `getContext('2d')` with a spy context and return
  it. Methods are `vi.fn`: `clearRect`, `fillRect`, `beginPath`, `arc`, `fill`,
  `stroke`, `moveTo`, `lineTo`, `quadraticCurveTo`, `drawImage`, `fillText`,
  `setTransform`, `save`, `restore`, `translate`, `scale`. `createRadialGradient`
  returns `{ addColorStop }`, `getImageData(x, y, w, h)` returns a zeroed
  `Uint8ClampedArray` of `max(4, w*h*4)` bytes, `measureText` returns `{ width: 6 }`.
  Writable props: `fillStyle`, `strokeStyle`, `globalCompositeOperation`,
  `globalAlpha`, `lineWidth`, `lineCap`, `lineJoin`, `font`, `textAlign`,
  `textBaseline`, `letterSpacing`.
- `setDocumentHidden(value)` / `dispatchVisibilityChange()`: drive the tab-hidden path.
- `mountPage(page)` / `mountMinimalDom()`: mount a real page body (`index`,
  `functionality`, `benefits`) or a minimal `<main id="main">` with one paragraph and
  no `#swarm` canvas (the no-canvas early return).
- `bootMain(opts)`: installs no fakes. Mount the fixture and install the fakes you
  need first, then call `bootMain()`, which sets `readyState`, records boot-time
  listeners on `window`, `document` and `<html>`, and **fresh-imports** the compiled
  module (via `vi.resetModules()` + dynamic `import()`) so `init()` runs against your
  DOM. Returns once `init()` has run.
- `resetHarnessGlobals()`: run by setup before and after every test; removes
  everything the installers and `bootMain` add.

**Fresh boot is mandatory per test.** The compiled module has module-level side
effects; importing it twice in one process returns the cached instance and will NOT
re-run `init()`. `bootMain` calls `vi.resetModules()` then `await import(...)` to force
a clean evaluation each time.
