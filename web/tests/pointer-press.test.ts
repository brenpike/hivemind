import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import type { MockInstance } from 'vitest';
import {
  bootMain,
  installMatchMedia,
  installIntersectionObserver,
  installRaf,
  installCanvas2dContext,
} from './helpers/boot-main';
import { mountPage } from './fixtures';

// Contract suite for the press guard on index.html: a pointerdown that lands on a page
// scrollbar (target <html>, or at or beyond documentElement.clientWidth/clientHeight)
// never starts a press-hold; a press on page content (mouse or touch) still does.
//
// Probe: an accepted press stamps its start time through performance.now(), and no other
// engine pointerdown listener reads the clock, so the CALL OCCURRENCE of performance.now
// during one dispatched pointerdown tells accepted from rejected. Values are never read.
//
// jsdom has zero-size layout (clientWidth/clientHeight are 0), so the layout cases stub
// own getters on document.documentElement after boot. jsdom has no PointerEvent, so
// presses are MouseEvents carrying pointerType and isPrimary via Object.defineProperty.

// Dispatches a primary pointerdown of the given pointerType at (clientX, clientY) on target.
function dispatchPress(target: Element, pointerType: string, clientX: number, clientY: number): void {
  const event = new MouseEvent('pointerdown', { bubbles: true, clientX, clientY });
  Object.defineProperty(event, 'pointerType', { value: pointerType });
  Object.defineProperty(event, 'isPrimary', { value: true });
  target.dispatchEvent(event);
}

// Gives <html> a 1000 x 700 client box via own getters (jsdom reports 0 x 0).
function stubRootClientBox(): void {
  const root = document.documentElement;
  Object.defineProperty(root, 'clientWidth', { configurable: true, get: () => 1000 });
  Object.defineProperty(root, 'clientHeight', { configurable: true, get: () => 700 });
}

// Boots index with motion on and the fakes the engine needs to reach its pointer wiring.
async function bootIndex(): Promise<void> {
  installMatchMedia({ matches: false });
  installIntersectionObserver();
  installRaf();
  installCanvas2dContext();

  mountPage('index');
  await bootMain();
}

describe('pointer press guard', () => {
  let nowSpy: MockInstance<() => number>;

  beforeEach(async () => {
    await bootIndex();
    nowSpy = vi.spyOn(window.performance, 'now');
  });

  afterEach(() => {
    const root = document.documentElement;
    Reflect.deleteProperty(root, 'clientWidth');
    Reflect.deleteProperty(root, 'clientHeight');
    nowSpy.mockRestore();
  });

  it('starts a press for a mouse press on page content', () => {
    stubRootClientBox();
    nowSpy.mockClear();
    dispatchPress(document.body, 'mouse', 500, 300);
    expect(nowSpy).toHaveBeenCalled();
  });

  it('starts a press for a touch press on page content', () => {
    stubRootClientBox();
    nowSpy.mockClear();
    dispatchPress(document.body, 'touch', 500, 300);
    expect(nowSpy).toHaveBeenCalled();
  });

  it('ignores a press at the right edge of the client box (vertical scrollbar)', () => {
    stubRootClientBox();
    nowSpy.mockClear();
    dispatchPress(document.body, 'mouse', 1000, 300);
    expect(nowSpy).not.toHaveBeenCalled();
  });

  it('ignores a press at the bottom edge of the client box (horizontal scrollbar)', () => {
    stubRootClientBox();
    nowSpy.mockClear();
    dispatchPress(document.body, 'mouse', 500, 700);
    expect(nowSpy).not.toHaveBeenCalled();
  });

  it('ignores a press targeting <html> itself (overlay scrollbar)', () => {
    stubRootClientBox();
    nowSpy.mockClear();
    dispatchPress(document.documentElement, 'mouse', 500, 300);
    expect(nowSpy).not.toHaveBeenCalled();
  });

  it('stays inert under zero-size layout: a far press on content still starts', () => {
    nowSpy.mockClear();
    dispatchPress(document.body, 'mouse', 5000, 300);
    expect(nowSpy).toHaveBeenCalled();
  });
});
