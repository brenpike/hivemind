import { describe, it, expect } from 'vitest';
import {
  bootMain,
  installMatchMedia,
  installIntersectionObserver,
  removeIntersectionObserver,
  installRaf,
  installCanvas2dContext,
  findObserver,
  type RafController,
} from './helpers/boot-main';
import { mountPage } from './fixtures';

// Characterization suite for the xenoglyph decode on .xg (glyph headings) and .xs
// (scramble text) in web/src/main.ts.
//
// CONTRACT ONLY: classes dx, dx-wait, dx-on; the aria-hidden .dx-ov overlay; id-free
// cloned descendants; the element's own text left intact. Scramble characters, glyph
// picks, stagger delays and decode durations are random or timing-derived and are
// DELIBERATELY UNCHARACTERIZED. Frames are flushed until the overlay is gone (capped),
// never counted.

const DECODE_MARGIN = '0px';
const FRAME_STEP_MS = 50;
const FRAME_CAP = 400;

// Appended to the index fixture so overlay id stripping has nested ids to strip.
const PROBE_HTML = '<p class="xs" id="decode-probe">Probe <b id="decode-probe-inner">text</b> here</p>';

// Text of el excluding any decode overlay, read from a detached clone.
function readOwnText(el: Element): string {
  const clone = el.cloneNode(true) as Element;
  clone.querySelectorAll('.dx-ov').forEach((overlay) => overlay.remove());
  return clone.textContent ?? '';
}

// Flushes frames with ts advancing by FRAME_STEP_MS until done() holds or FRAME_CAP
// frames have run; returns whether done() held.
function flushUntil(raf: RafController, done: () => boolean): boolean {
  let ts = 1000;
  for (let frame = 0; frame < FRAME_CAP && !done(); frame++) {
    ts += FRAME_STEP_MS;
    raf.flushOne(ts);
  }
  return done();
}

// Mounts index plus the id probe, boots with motion on, and returns the decode observer.
async function bootIndexWithProbe() {
  installMatchMedia({ matches: false });
  const registry = installIntersectionObserver();
  const raf = installRaf();
  installCanvas2dContext();

  mountPage('index');
  document.getElementById('main')!.insertAdjacentHTML('beforeend', PROBE_HTML);
  await bootMain();

  return { raf, decodeObserver: findObserver(registry, DECODE_MARGIN) };
}

describe('xenoglyph decode (contract)', () => {
  it('registers nothing and mounts no overlays under reduced motion', async () => {
    installMatchMedia({ matches: true });
    installIntersectionObserver();
    installRaf();
    installCanvas2dContext();

    mountPage('index');
    await bootMain();

    expect(document.querySelectorAll('.xg, .xs').length).toBeGreaterThan(0);
    expect(document.querySelectorAll('.dx, .dx-wait').length).toBe(0);
    expect(document.querySelectorAll('.dx-ov').length).toBe(0);
  });

  it('leaves text unhidden and does not throw when IntersectionObserver is absent', async () => {
    installMatchMedia({ matches: false });
    removeIntersectionObserver();
    installRaf();
    installCanvas2dContext();

    mountPage('index');
    await expect(bootMain()).resolves.toBeUndefined();

    expect(document.querySelectorAll('.dx-wait').length).toBe(0);
    expect(document.querySelectorAll('.dx-ov').length).toBe(0);
  });

  it('mounts one aria-hidden, id-free overlay on an intersecting element and keeps its text', async () => {
    const { decodeObserver } = await bootIndexWithProbe();
    const probe = document.getElementById('decode-probe')!;
    const textBefore = readOwnText(probe);
    expect(decodeObserver.observed).toContain(probe);

    decodeObserver.trigger([{ target: probe, isIntersecting: true }]);

    const overlays = probe.querySelectorAll(':scope > .dx-ov');
    expect(overlays.length).toBe(1);
    expect(overlays[0].tagName).toBe('SPAN');
    expect(overlays[0].getAttribute('aria-hidden')).toBe('true');
    expect(overlays[0].querySelectorAll('[id]').length).toBe(0);
    expect(probe.classList.contains('dx-on')).toBe(true);
    expect(probe.classList.contains('dx-wait')).toBe(false);
    expect(probe.id).toBe('decode-probe');
    expect(document.getElementById('decode-probe-inner')).not.toBeNull();
    expect(readOwnText(probe)).toBe(textBefore);
  });

  it('removes the overlay and dx-on once the decode finishes', async () => {
    const { raf, decodeObserver } = await bootIndexWithProbe();
    const glyphHeading = document.querySelector<HTMLElement>('.xg')!;
    const probe = document.getElementById('decode-probe')!;

    decodeObserver.trigger([
      { target: glyphHeading, isIntersecting: true },
      { target: probe, isIntersecting: true },
    ]);
    expect(glyphHeading.querySelector('.dx-ov')).not.toBeNull();
    expect(probe.querySelector('.dx-ov')).not.toBeNull();

    const finished = flushUntil(raf, () => !glyphHeading.querySelector('.dx-ov') && !probe.querySelector('.dx-ov'));

    expect(finished).toBe(true);
    expect(glyphHeading.classList.contains('dx-on')).toBe(false);
    expect(probe.classList.contains('dx-on')).toBe(false);
  });

  it('leaves dx-wait on an element whose entry is not intersecting', async () => {
    const { decodeObserver } = await bootIndexWithProbe();
    const probe = document.getElementById('decode-probe')!;

    decodeObserver.trigger([{ target: probe, isIntersecting: false }]);

    expect(probe.classList.contains('dx-wait')).toBe(true);
    expect(probe.classList.contains('dx-on')).toBe(false);
    expect(probe.querySelector('.dx-ov')).toBeNull();
  });
});
