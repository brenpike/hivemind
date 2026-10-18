import { describe, it, expect } from 'vitest';
import {
  bootMain,
  installMatchMedia,
  installIntersectionObserver,
  installRaf,
  installCanvas2dContext,
} from './helpers/boot-main';
import { mountPage } from './fixtures';

// Smoke proof for the characterization harness. This is the harness's living proof
// that it can install the required fakes, mount a real page, boot the COMPILED Swarm
// Glyph engine, and observe init() running all the way to live motion. It is NOT a
// behavior-pinning suite; keep it minimal and keep it green.

describe('harness boot smoke', () => {
  it('boots the compiled engine against the real index.html and goes live', async () => {
    installMatchMedia({ matches: false });
    installIntersectionObserver();
    const raf = installRaf();
    installCanvas2dContext();

    mountPage('index');
    await bootMain();

    const root = document.documentElement;
    expect(root.classList.contains('swarm-ready')).toBe(true);
    expect(root.classList.contains('swarm-live')).toBe(true);

    // Generated glyph defs: svg.gdefs > defs > symbol#g0..g23.
    const gdefs = document.querySelectorAll('svg.gdefs');
    expect(gdefs.length).toBe(1);
    const symbolIds = Array.from(gdefs[0].querySelectorAll('defs > symbol')).map((s) => s.id);
    expect(symbolIds).toEqual(Array.from({ length: 24 }, (_v, gi) => `g${gi}`));

    // Every decode target is registered and waiting for its observer.
    const decodeTargets = document.querySelectorAll('.xg, .xs');
    expect(decodeTargets.length).toBeGreaterThan(0);
    decodeTargets.forEach((el) => {
      expect(el.classList.contains('dx')).toBe(true);
      expect(el.classList.contains('dx-wait')).toBe(true);
    });

    expect(raf.pending()).toBe(1);
  });
});
