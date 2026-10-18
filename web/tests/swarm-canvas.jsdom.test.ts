import { describe, it, expect, vi } from 'vitest';
import {
  bootMain,
  installMatchMedia,
  installIntersectionObserver,
  installRaf,
  installCanvas2dContext,
  findObserver,
  setDocumentHidden,
  dispatchVisibilityChange,
} from './helpers/boot-main';
import { mountPage, mountMinimalDom, type PageName } from './fixtures';

// Characterization suite for the Swarm Glyph engine's canvas lifecycle (web/src/main.ts).
//
// CONTRACT ONLY. The swarm is a decorative particle field. Per the project's
// determinism policy, the following are DELIBERATELY UNCHARACTERIZED:
//   - particle positions, velocities, counts, sizes, colors
//   - pixel output / rendered frames
//   - requestAnimationFrame timing and frame cadence
//   - any Math.random-driven value
// We assert only: canvas presence, root classes (swarm-ready, swarm-live), pending rAF
// presence/absence, observer wiring, decode overlay presence, and 2d-context CALL occurrence.

const SECTIONS_MARGIN = '-48% 0px -48% 0px';
const DECODE_MARGIN = '0px';
const PAGES: ReadonlyArray<PageName> = ['index', 'functionality', 'benefits'];

// Simulates the page head gate, which adds swarm-live before the engine boots.
function preGateSwarmLive(): void {
  document.documentElement.classList.add('swarm-live');
}

describe('swarm canvas (contract)', () => {
  it('leaves exactly one canvas in the document; glow sprites stay detached', async () => {
    installMatchMedia({ matches: false });
    installIntersectionObserver();
    installRaf();
    installCanvas2dContext();

    mountPage('index');
    await bootMain();

    const canvases = document.querySelectorAll('canvas');
    expect(canvases.length).toBe(1);
    expect(canvases[0].id).toBe('swarm');
  });

  it('paints statically and never goes live under reduced motion at load', async () => {
    installMatchMedia({ matches: true });
    installIntersectionObserver();
    const raf = installRaf();
    const ctxSpy = installCanvas2dContext();

    mountPage('index');
    preGateSwarmLive();
    await bootMain();

    const root = document.documentElement;
    expect(root.classList.contains('swarm-ready')).toBe(true);
    expect(root.classList.contains('swarm-live')).toBe(false);
    expect(ctxSpy.fillRect).toHaveBeenCalled();
    expect(raf.pending()).toBe(0);
  });

  it('takes the no-canvas early return on a page without #swarm', async () => {
    installMatchMedia({ matches: false });
    installIntersectionObserver();
    const raf = installRaf();
    installCanvas2dContext();

    mountMinimalDom();
    preGateSwarmLive();
    await expect(bootMain()).resolves.toBeUndefined();

    const root = document.documentElement;
    expect(root.classList.contains('swarm-ready')).toBe(true);
    expect(root.classList.contains('swarm-live')).toBe(false);
    expect(document.querySelector('svg.gdefs')).toBeNull();
    expect(raf.pending()).toBe(0);
  });

  it('takes the no-context early return when getContext yields null', async () => {
    installMatchMedia({ matches: false });
    installIntersectionObserver();
    const raf = installRaf();
    Object.defineProperty(HTMLCanvasElement.prototype, 'getContext', {
      configurable: true,
      writable: true,
      value: vi.fn(() => null),
    });

    mountPage('index');
    preGateSwarmLive();
    await expect(bootMain()).resolves.toBeUndefined();

    const root = document.documentElement;
    expect(root.classList.contains('swarm-ready')).toBe(true);
    expect(root.classList.contains('swarm-live')).toBe(false);
    expect(document.querySelector('svg.gdefs')).toBeNull();
    expect(document.querySelectorAll('.dx-wait').length).toBe(0);
    expect(raf.pending()).toBe(0);
  });

  it('takes the no-rAF early return when requestAnimationFrame is absent', async () => {
    installMatchMedia({ matches: false });
    installIntersectionObserver();
    installCanvas2dContext();
    expect(typeof window.requestAnimationFrame).toBe('undefined');

    mountPage('index');
    preGateSwarmLive();
    await expect(bootMain()).resolves.toBeUndefined();

    const root = document.documentElement;
    expect(root.classList.contains('swarm-ready')).toBe(true);
    expect(root.classList.contains('swarm-live')).toBe(false);
    expect(document.querySelector('svg.gdefs')).toBeNull();
    expect(document.querySelectorAll('.dx-wait').length).toBe(0);
  });

  it('stops and repaints statically on a live reduced-motion change, then resumes', async () => {
    const mql = installMatchMedia({ matches: false });
    const registry = installIntersectionObserver();
    const raf = installRaf();
    const ctxSpy = installCanvas2dContext();

    mountPage('index');
    await bootMain();

    const decodeTargets = Array.from(document.querySelectorAll('.xg, .xs')).slice(0, 3);
    findObserver(registry, DECODE_MARGIN).trigger(
      decodeTargets.map((target) => ({ target, isIntersecting: true })),
    );
    expect(document.querySelectorAll('.dx-ov').length).toBeGreaterThan(0);

    const root = document.documentElement;
    const fillRectCallsBefore = ctxSpy.fillRect.mock.calls.length;
    mql._fireChange(true);

    expect(raf.pending()).toBe(0);
    expect(root.classList.contains('swarm-live')).toBe(false);
    expect(document.querySelectorAll('.dx-ov').length).toBe(0);
    expect(ctxSpy.fillRect.mock.calls.length).toBeGreaterThan(fillRectCallsBefore);

    mql._fireChange(false);

    expect(root.classList.contains('swarm-live')).toBe(true);
    expect(raf.pending()).toBe(1);
  });

  it('cancels the frame while hidden and reschedules when visible again', async () => {
    installMatchMedia({ matches: false });
    installIntersectionObserver();
    const raf = installRaf();
    installCanvas2dContext();

    mountPage('index');
    await bootMain();
    expect(raf.pending()).toBe(1);

    setDocumentHidden(true);
    dispatchVisibilityChange();
    expect(raf.pending()).toBe(0);

    setDocumentHidden(false);
    dispatchVisibilityChange();
    expect(raf.pending()).toBe(1);
  });

  it('observes every [data-formation] section with the sections observer', async () => {
    installMatchMedia({ matches: false });
    const registry = installIntersectionObserver();
    installRaf();
    installCanvas2dContext();

    mountPage('index');
    await bootMain();

    const sections = Array.from(document.querySelectorAll('[data-formation]'));
    expect(sections.length).toBeGreaterThan(0);
    expect(findObserver(registry, SECTIONS_MARGIN).observed).toEqual(sections);
  });

  it.each(PAGES)('runs frames through every formation on %s without throwing', async (page) => {
    installMatchMedia({ matches: false });
    const registry = installIntersectionObserver();
    const raf = installRaf();
    installCanvas2dContext();

    mountPage(page);
    await bootMain();

    const sectionsObserver = findObserver(registry, SECTIONS_MARGIN);
    let ts = 1000;
    for (const section of Array.from(document.querySelectorAll('[data-formation]'))) {
      sectionsObserver.trigger([{ target: section, isIntersecting: true }]);
      for (let frame = 0; frame < 3; frame++) {
        ts += 16;
        expect(() => raf.flushOne(ts)).not.toThrow();
      }
    }
    expect(raf.pending()).toBe(1);
  });

  it('keeps a single glyph defs block across a stop/start cycle', async () => {
    const mql = installMatchMedia({ matches: false });
    installIntersectionObserver();
    installRaf();
    installCanvas2dContext();

    mountPage('index');
    await bootMain();

    mql._fireChange(true);
    mql._fireChange(false);

    expect(document.querySelectorAll('svg.gdefs').length).toBe(1);
    expect(document.querySelectorAll('#g0').length).toBe(1);
  });
});
