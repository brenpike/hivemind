import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Fixture loaders for the characterization suite.
//
// Primary strategy (locked decision A'): use the REAL shipped HTML pages as
// high-fidelity fixtures. They pin the actual id/class/data-attribute contract that
// web/scripts/main.js depends on, so a structural change to the markup that would break
// the engine surfaces here instead of silently in production.

const HERE = dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = resolve(HERE, '..', '..');

export type PageName = 'index' | 'functionality' | 'benefits';

const PAGE_FILES: Record<PageName, string> = {
  index: 'index.html',
  functionality: 'functionality.html',
  benefits: 'benefits.html',
};

// Read a real page's <body> innerHTML from disk. We mount only the body so the page's
// own <script type="module" src="./scripts/main.js"> and head gate script in <head> do
// not run (the harness controls module evaluation explicitly via bootMain).
export function readPageBody(page: PageName): string {
  const filePath = resolve(WEB_ROOT, PAGE_FILES[page]);
  const html = readFileSync(filePath, 'utf8');
  const match = html.match(/<body[^>]*>([\s\S]*)<\/body>/i);
  if (!match) {
    throw new Error(`Fixture page "${page}" has no <body>; cannot mount fixture`);
  }
  return match[1];
}

// Mount a real page's body into the current jsdom document.body. Call this (or
// mountMinimalDom) BEFORE bootMain so main.js's init() finds the expected DOM.
export function mountPage(page: PageName): void {
  document.body.innerHTML = readPageBody(page);
}

// Minimal/stripped DOM for the no-canvas early return: no #swarm canvas, so init()
// adds swarm-ready, removes swarm-live and returns before any other wiring.
export function mountMinimalDom(): void {
  document.body.innerHTML = `
    <main id="main">
      <p>Minimal fixture: no swarm canvas, no sections, no decode targets.</p>
    </main>
  `;
}
