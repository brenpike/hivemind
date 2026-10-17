import { describe, it, expect, vi } from 'vitest';
import {
  bootMain,
  installMatchMedia,
  installIntersectionObserver,
  removeIntersectionObserver,
  installRaf,
  installCanvas2dContext,
} from './helpers/boot-main';
import { mountPage } from './fixtures';

// Characterization suite for the legacy / absent-API fallback branches in main.ts:
// the deprecated WebKit addListener path for the reduced-motion listener, the
// matchMedia-absent path (motion on), and the IntersectionObserver-absent path (scroll
// fallback for sections, no decode registration).

describe('fallback branches', () => {
  it('registers the motion-change listener via the deprecated addListener when addEventListener is absent', async () => {
    const mql = installMatchMedia({ matches: false, legacy: true });
    installIntersectionObserver();
    installRaf();
    installCanvas2dContext();

    const addListenerSpy = vi.spyOn(mql, 'addListener');

    mountPage('index');
    await expect(bootMain()).resolves.toBeUndefined();

    expect(mql.addEventListener).toBeUndefined();
    expect(addListenerSpy).toHaveBeenCalledTimes(1);
    expect(typeof addListenerSpy.mock.calls[0][0]).toBe('function');
  });

  it('boots with motion on when matchMedia is absent', async () => {
    installIntersectionObserver();
    const raf = installRaf();
    installCanvas2dContext();
    expect(typeof window.matchMedia).toBe('undefined');

    mountPage('index');
    await expect(bootMain()).resolves.toBeUndefined();

    const root = document.documentElement;
    expect(root.classList.contains('swarm-ready')).toBe(true);
    expect(root.classList.contains('swarm-live')).toBe(true);
    expect(raf.pending()).toBe(1);
  });

  it('neither throws nor hides text when IntersectionObserver is absent', async () => {
    installMatchMedia({ matches: false });
    removeIntersectionObserver();
    const raf = installRaf();
    installCanvas2dContext();

    mountPage('index');
    await expect(bootMain()).resolves.toBeUndefined();

    const decodeTargets = document.querySelectorAll('.xg, .xs');
    expect(decodeTargets.length).toBeGreaterThan(0);
    decodeTargets.forEach((el) => {
      expect(el.classList.contains('dx-wait')).toBe(false);
      expect(el.classList.contains('dx-on')).toBe(false);
    });
    expect(document.documentElement.classList.contains('swarm-live')).toBe(true);
    expect(() => window.dispatchEvent(new Event('scroll'))).not.toThrow();
    expect(() => raf.flushOne(1000)).not.toThrow();
  });
});
