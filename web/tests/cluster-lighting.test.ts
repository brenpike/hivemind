import { describe, it, expect } from 'vitest';
import {
  bootMain,
  installMatchMedia,
  installIntersectionObserver,
  installRaf,
  installCanvas2dContext,
} from './helpers/boot-main';
import { mountPage } from './fixtures';

// Characterization suite for agent-card cluster lighting on index.html: each
// [data-cluster] card toggles is-lit on hover (mouse) or tap (touch/pen).
//
// jsdom has no PointerEvent, so pointer events are dispatched as MouseEvents carrying a
// pointerType defined via Object.defineProperty. CONTRACT ONLY: the is-lit class; the
// canvas-side highlight (particle lighting, repaint pixels) is DELIBERATELY UNCHARACTERIZED.

// Dispatches a synthetic pointer event of the given type and pointerType on target.
function dispatchPointer(target: Element, type: string, pointerType: string): void {
  const event = new MouseEvent(type, { bubbles: type === 'pointerup' });
  Object.defineProperty(event, 'pointerType', { value: pointerType });
  target.dispatchEvent(event);
}

// Indices of the [data-cluster] cards currently carrying is-lit.
function readLitClusters(): string[] {
  return Array.from(document.querySelectorAll('[data-cluster].is-lit')).map(
    (card) => card.getAttribute('data-cluster') ?? '',
  );
}

// Boots index with the given reduced-motion preference and returns the cards.
async function bootIndex(reducedMotion: boolean): Promise<HTMLElement[]> {
  installMatchMedia({ matches: reducedMotion });
  installIntersectionObserver();
  installRaf();
  installCanvas2dContext();

  mountPage('index');
  await bootMain();

  const cards = Array.from(document.querySelectorAll<HTMLElement>('[data-cluster]'));
  expect(cards.length).toBe(6);
  return cards;
}

describe.each([
  ['motion on', false],
  ['reduced motion', true],
])('cluster lighting (%s)', (_label, reducedMotion) => {
  it('lights only the hovered card on mouse enter and clears it on leave', async () => {
    const cards = await bootIndex(reducedMotion);

    dispatchPointer(cards[2], 'pointerenter', 'mouse');
    expect(readLitClusters()).toEqual(['2']);

    dispatchPointer(cards[2], 'pointerleave', 'mouse');
    expect(readLitClusters()).toEqual([]);
  });

  it('toggles a card on then off with touch pointerup', async () => {
    const cards = await bootIndex(reducedMotion);

    dispatchPointer(cards[4], 'pointerup', 'touch');
    expect(readLitClusters()).toEqual(['4']);

    dispatchPointer(cards[4], 'pointerup', 'touch');
    expect(readLitClusters()).toEqual([]);
  });
});
