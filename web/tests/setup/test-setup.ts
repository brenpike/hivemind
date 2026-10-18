import { afterEach, beforeEach } from 'vitest';
import { resetHarnessGlobals } from '../helpers/boot-main';

// Global setup for the characterization suite.
//
// jsdom provides the DOM but NOT: window.matchMedia, IntersectionObserver, a real
// 2d canvas context, Path2D, or PointerEvent. Individual fakes are installed per-test
// via the helpers in helpers/boot-main.ts (so each test controls the exact configuration
// it needs, e.g. reduced-motion on/off, IO present/absent, rAF present/absent).
//
// This file only guarantees a CLEAN SLATE around every test: it tears down any fakes,
// boot-time listeners and DOM mutations left behind so tests cannot leak state into one
// another. The compiled module under test has module-level side effects and writes
// classes onto <html>, so leaked globals or root classes would otherwise silently
// corrupt the next test's boot.

beforeEach(() => {
  resetHarnessGlobals();
});

afterEach(() => {
  resetHarnessGlobals();
  document.documentElement.removeAttribute('class');
  document.body.innerHTML = '';
  document.head.innerHTML = '';
});
