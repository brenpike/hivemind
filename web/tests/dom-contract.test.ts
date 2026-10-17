import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join, basename } from 'node:path';

/**
 * Static contract and guard suite for the shipped Swarm Glyph pages.
 *
 * Every assertion reads files from disk and parses them with DOMParser. Nothing here
 * boots web/scripts/main.js or reuses the behavioral harness, so a failure names a
 * markup, stylesheet, or source regression directly.
 */

const HERE = dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = resolve(HERE, '..');
const REPO_ROOT = resolve(WEB_ROOT, '..');

const PAGE_FILES = ['index.html', 'functionality.html', 'benefits.html'] as const;
type PageFile = (typeof PAGE_FILES)[number];
const DEEP_PAGES: PageFile[] = ['functionality.html', 'benefits.html'];

const FORMATIONS = new Set(['hero', 'agents', 'workflow', 'install', 'ambient']);
const NAV_LINK_TEXTS = ['How it works', 'Benefits', 'Install', 'GitHub'];
const SVG_NAMESPACE_URL = 'http://www.w3.org/2000/svg';
const CLASS_ALLOWLIST_EXCEPTIONS = new Set(['xs']);
const DECODE_SELECTOR = '.xs, .xg';
const DECODE_FORBIDDEN_ANCESTORS = ['table', 'pre', 'code', '.code-panel'];
const NETWORK_ELEMENTS = ['link', 'script', 'img', 'source', 'iframe', 'video', 'audio'];
const REMOTE_URL_PATTERN = /^(?:https?:|\/\/)/i;
const POINTER_COPY_PATTERN = /\b(?:tap|hover|touch|click|press and hold)\b/i;
const DASH_PATTERN =/[\u2013\u2014]|&(?:mdash|ndash|#8212|#8211|#x2014|#x2013);/i;

const SECTION_IDS: Record<PageFile, string[]> = {
  'index.html': ['hero', 'agents', 'workflow', 'install'],
  'functionality.html': [
    'func-hero',
    'install',
    'requirements',
    'setup',
    'agents',
    'skills',
    'lifecycle',
    'brood',
    'signals',
    'plain-english',
    'companions',
    'configuration',
    'func-cta',
  ],
  'benefits.html': [
    'ben-hero',
    'ben-pipeline',
    'ben-planning',
    'ben-review',
    'ben-parallelism',
    'ben-git',
    'ben-lockout',
    'ben-install',
  ],
};

const pageCache = new Map<string, Document>();

function readWebFile(relativePath: string): string {
  return readFileSync(resolve(WEB_ROOT, relativePath), 'utf8');
}

function loadPage(file: string): Document {
  const cached = pageCache.get(file);
  if (cached) return cached;
  const doc = new DOMParser().parseFromString(readWebFile(file), 'text/html');
  pageCache.set(file, doc);
  return doc;
}

function selectAll(root: ParentNode, selector: string): Element[] {
  return Array.from(root.querySelectorAll(selector));
}

function findInlineClassicScripts(doc: Document): HTMLScriptElement[] {
  return selectAll(doc, 'script:not([src])').filter((script) => {
    const type = (script.getAttribute('type') ?? '').trim().toLowerCase();
    return type === '' || type === 'text/javascript';
  }) as HTMLScriptElement[];
}

function listClassTokens(doc: Document): string[] {
  const tokens = selectAll(doc, '[class]').flatMap((element) =>
    (element.getAttribute('class') ?? '').split(/\s+/).filter((token) => token.length > 0),
  );
  return Array.from(new Set(tokens)).sort();
}

function stripCssComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//g, '');
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function hasClassSelector(css: string, token: string): boolean {
  return new RegExp(`\\.${escapeRegExp(token)}(?![\\w-])`).test(css);
}

function listFilesRecursively(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const entryPath = join(directory, entry);
    return statSync(entryPath).isDirectory() ? listFilesRecursively(entryPath) : [entryPath];
  });
}

function listDashScanTargets(): string[] {
  const topLevelPages = readdirSync(WEB_ROOT)
    .filter((entry) => entry.endsWith('.html'))
    .map((entry) => join(WEB_ROOT, entry));
  return [
    ...topLevelPages,
    ...listFilesRecursively(join(WEB_ROOT, 'styles')),
    ...listFilesRecursively(join(WEB_ROOT, 'src')),
    join(WEB_ROOT, 'README.md'),
  ];
}

function collectTextNodes(node: Node): Text[] {
  if (node.nodeType === Node.TEXT_NODE) return [node as Text];
  return Array.from(node.childNodes).flatMap(collectTextNodes);
}

function listPointerCopyNodes(doc: Document): Text[] {
  return collectTextNodes(doc.body).filter((textNode) => POINTER_COPY_PATTERN.test(textNode.data));
}

function listRowKeys(table: Element): string[] {
  return selectAll(table, 'tbody tr').map((row) => row.querySelector('code')?.textContent?.trim() ?? '');
}

function listAgentNames(): string[] {
  return readdirSync(join(REPO_ROOT, 'plugin', 'agents'))
    .filter((entry) => entry.endsWith('.md'))
    .map((entry) => basename(entry, '.md'));
}

function listSkillNames(): string[] {
  const skillsRoot = join(REPO_ROOT, 'plugin', 'skills');
  return readdirSync(skillsRoot).filter(
    (entry) => entry !== '_shared' && statSync(join(skillsRoot, entry)).isDirectory(),
  );
}

function listWorkflowNames(): string[] {
  return readdirSync(join(REPO_ROOT, 'plugin', 'workflows'))
    .filter((entry) => entry.endsWith('.json') && entry !== 'workflow-router.json')
    .map((entry) => basename(entry, '.json'));
}

function sortedCopy(values: string[]): string[] {
  return [...values].sort();
}

describe.each(PAGE_FILES)('%s', (file) => {
  const doc = loadPage(file);

  it('HEAD: one inline classic script before the stylesheet, with the swarm boot guard', () => {
    const inlineScripts = findInlineClassicScripts(doc);
    expect(inlineScripts).toHaveLength(1);
    const bootScript = inlineScripts[0];
    expect(bootScript.parentElement?.tagName).toBe('HEAD');
    const bootSource = bootScript.textContent ?? '';
    expect(bootSource).toContain('swarm-live');
    expect(bootSource).toContain('swarm-ready');
    expect(bootSource).toContain('prefers-reduced-motion');

    const stylesheets = selectAll(doc, 'link[rel="stylesheet"]');
    expect(stylesheets.map((link) => link.getAttribute('href'))).toEqual(['./styles/main.css']);
    const precedesStylesheet = bootScript.compareDocumentPosition(stylesheets[0]) & Node.DOCUMENT_POSITION_FOLLOWING;
    expect(precedesStylesheet).toBeTruthy();

    const moduleScripts = selectAll(doc, 'script[type="module"]');
    expect(moduleScripts.map((script) => script.getAttribute('src'))).toEqual(['./scripts/main.js']);
  });

  it('HEAD: viewport, color-scheme and theme-color meta present, no robots noindex', () => {
    expect(doc.querySelector('head meta[name="viewport"][content]')).not.toBeNull();
    expect(doc.querySelector('head meta[name="color-scheme"][content]')).not.toBeNull();
    expect(doc.querySelector('head meta[name="theme-color"][content]')).not.toBeNull();
    const robotsDirectives = selectAll(doc, 'meta[name="robots" i]').map((meta) =>
      (meta.getAttribute('content') ?? '').toLowerCase(),
    );
    expect(robotsDirectives.filter((content) => content.includes('noindex'))).toEqual([]);
  });

  it('SHELL: skip link, main landmark, one swarm canvas, vignette', () => {
    expect(doc.querySelector('a.skip')?.getAttribute('href')).toBe('#main');
    expect(doc.querySelector('main#main')).not.toBeNull();
    const canvases = selectAll(doc, 'canvas');
    expect(canvases).toHaveLength(1);
    expect(canvases[0].matches('#swarm.swarm')).toBe(true);
    expect(canvases[0].getAttribute('aria-hidden')).toBe('true');
    const vignette = doc.querySelector('.vignette');
    expect(vignette).not.toBeNull();
    expect(vignette?.getAttribute('aria-hidden')).toBe('true');
  });

  it('SHELL: primary nav link texts and aria-current placement', () => {
    const navs = selectAll(doc, 'nav.site-nav');
    expect(navs).toHaveLength(1);
    expect(navs[0].getAttribute('aria-label')).toBe('Primary');
    const linkTexts = selectAll(navs[0], 'a').map((link) => (link.textContent ?? '').trim());
    expect(linkTexts).toEqual(NAV_LINK_TEXTS);

    const currentElements = selectAll(doc, '[aria-current]');
    if (file === 'index.html') {
      expect(currentElements).toHaveLength(0);
      return;
    }
    expect(currentElements).toHaveLength(1);
    expect(currentElements[0].getAttribute('aria-current')).toBe('page');
    expect(currentElements[0].closest('nav.site-nav')).toBe(navs[0]);
    expect(currentElements[0].getAttribute('href')).toBe(`./${file}`);
  });

  it('FORMATIONS: every data-formation value is known', () => {
    const formations = selectAll(doc, '[data-formation]').map((element) => element.getAttribute('data-formation'));
    expect(formations.length).toBeGreaterThan(0);
    expect(formations.filter((value) => !FORMATIONS.has(value ?? ''))).toEqual([]);
  });

  it('FORMATIONS: one hero section with a short single text node wordmark', () => {
    const heroes = selectAll(doc, 'section[data-formation="hero"]');
    expect(heroes).toHaveLength(1);
    const wordmarks = selectAll(heroes[0], '#hero-title.wordmark');
    expect(wordmarks).toHaveLength(1);
    const childNodes = Array.from(wordmarks[0].childNodes);
    expect(childNodes).toHaveLength(1);
    expect(childNodes[0].nodeType).toBe(Node.TEXT_NODE);
    const wordmarkText = childNodes[0].textContent ?? '';
    expect(wordmarkText).toBe(wordmarkText.trim());
    const glyphCount = wordmarkText.replace(/\s/g, '').length;
    expect(glyphCount).toBeGreaterThan(0);
    expect(glyphCount).toBeLessThanOrEqual(16);
  });

  it('FORMATIONS: install sections orbit once, workflow sections carry beats', () => {
    const installSections = selectAll(doc, 'section[data-formation="install"]');
    expect(installSections.length).toBeGreaterThan(0);
    for (const section of installSections) {
      expect(selectAll(section, '[data-orbit]'), `#${section.id}`).toHaveLength(1);
    }
    for (const section of selectAll(doc, 'section[data-formation="workflow"]')) {
      const flows = selectAll(section, '.flow');
      expect(flows, `#${section.id}`).toHaveLength(1);
      expect(selectAll(flows[0], '.beat').length, `#${section.id}`).toBeGreaterThan(0);
    }
  });

  it('DECODE SCOPE: no decode targets inside tables, code, or nested decode targets', () => {
    const forbiddenAncestorSelector = [...DECODE_FORBIDDEN_ANCESTORS, DECODE_SELECTOR].join(', ');
    const misplaced = selectAll(doc, DECODE_SELECTOR)
      .filter((element) => element.parentElement?.closest(forbiddenAncestorSelector))
      .map((element) => element.outerHTML.slice(0, 120));
    expect(misplaced).toEqual([]);
  });

  it('CLASS ALLOWLIST: every class token has a selector in main.css', () => {
    const css = stripCssComments(readWebFile('styles/main.css'));
    const unstyled = listClassTokens(doc).filter(
      (token) => !CLASS_ALLOWLIST_EXCEPTIONS.has(token) && !hasClassSelector(css, token),
    );
    expect(unstyled).toEqual([]);
  });

  it('A11Y: pointer-only instructions are hidden from assistive tech', () => {
    const exposed = listPointerCopyNodes(doc)
      .filter((textNode) => textNode.parentElement?.closest('[aria-hidden="true"]') === null)
      .map((textNode) => textNode.data.trim());
    expect(exposed).toEqual([]);
  });

  it('has no style attributes', () => {
    expect(selectAll(doc, '[style]').map((element) => element.tagName)).toEqual([]);
  });

  it('ZERO NETWORK: no remote resource src or href', () => {
    const remoteRefs = selectAll(doc, NETWORK_ELEMENTS.join(', '))
      .flatMap((element) => [element.getAttribute('src'), element.getAttribute('href')])
      .filter((value): value is string => value !== null && REMOTE_URL_PATTERN.test(value.trim()));
    expect(remoteRefs).toEqual([]);
  });

  it('BASE PATH: no root-relative href or src', () => {
    const rootRelative = selectAll(doc, '[href], [src]')
      .flatMap((element) => [element.getAttribute('href'), element.getAttribute('src')])
      .filter((value): value is string => value !== null && value.trim().startsWith('/'));
    expect(rootRelative).toEqual([]);
  });

  it('LINKS: every fragment href resolves on its page or target page', () => {
    const unresolved: string[] = [];
    for (const element of selectAll(doc, '[href]')) {
      const href = element.getAttribute('href') ?? '';
      const samePage = /^#(.*)$/.exec(href);
      const crossPage = /^\.\/([\w.-]+\.html)#(.+)$/.exec(href);
      if (samePage && !(samePage[1] && doc.getElementById(samePage[1]))) unresolved.push(href);
      if (!crossPage) continue;
      const targetExists = existsSync(resolve(WEB_ROOT, crossPage[1]));
      if (!targetExists || !loadPage(crossPage[1]).getElementById(crossPage[2])) unresolved.push(href);
    }
    expect(unresolved).toEqual([]);
  });

  it('DEPTH: section ids in document order', () => {
    expect(selectAll(doc, 'section[id]').map((section) => section.id)).toEqual(SECTION_IDS[file]);
  });
});

describe('cross page contract', () => {
  it('HEAD: inline boot script is byte identical across pages', () => {
    const bootSources = PAGE_FILES.map((file) => findInlineClassicScripts(loadPage(file))[0]?.textContent ?? '');
    expect(bootSources[0].length).toBeGreaterThan(0);
    expect(new Set(bootSources).size).toBe(1);
  });

  it('FORMATIONS: index carries the agent stage and clusters 0 to 5', () => {
    const doc = loadPage('index.html');
    expect(doc.getElementById('agent-stage')).not.toBeNull();
    const clusters = selectAll(doc, '[data-cluster]').map((element) => element.getAttribute('data-cluster'));
    expect(clusters).toEqual(['0', '1', '2', '3', '4', '5']);
  });

  it('A11Y: index carries pointer-only instruction copy, so the hidden-from-AT check is not vacuous', () => {
    expect(listPointerCopyNodes(loadPage('index.html')).length).toBeGreaterThan(0);
  });

  it.each(DEEP_PAGES)('FORMATIONS: %s canvas density is in (0, 1]', (file) => {
    const density = Number(loadPage(file).querySelector('canvas#swarm')?.getAttribute('data-density'));
    expect(Number.isFinite(density)).toBe(true);
    expect(density).toBeGreaterThan(0);
    expect(density).toBeLessThanOrEqual(1);
  });

  it('ZERO NETWORK: main.css has no url( and no @import', () => {
    const css = readWebFile('styles/main.css');
    expect(css).not.toContain('url(');
    expect(css).not.toContain('@import');
  });

  it('ZERO NETWORK: main.ts has no fetch, XMLHttpRequest, or remote URL', () => {
    const source = readWebFile('src/main.ts');
    expect(source).not.toContain('fetch(');
    expect(source).not.toContain('XMLHttpRequest');
    const urls = source.match(/https?:\/\/[^\s'"`)<>]+/g) ?? [];
    expect(urls.filter((url) => url !== SVG_NAMESPACE_URL)).toEqual([]);
  });

  it('GROUND TRUTH: agents table has one row per plugin agent', () => {
    const tables = selectAll(loadPage('functionality.html'), '#agents table');
    expect(tables).toHaveLength(1);
    const expected = listAgentNames().map((name) => `hivemind:${name}`);
    expect(sortedCopy(listRowKeys(tables[0]))).toEqual(sortedCopy(expected));
  });

  it('GROUND TRUTH: skills table has one row per plugin skill directory', () => {
    const tables = selectAll(loadPage('functionality.html'), '#skills table');
    expect(tables).toHaveLength(1);
    const expected = listSkillNames().map((name) => `hivemind:${name}`);
    expect(sortedCopy(listRowKeys(tables[0]))).toEqual(sortedCopy(expected));
  });

  it('GROUND TRUTH: lifecycle workflows table has one row per routable workflow', () => {
    const tables = selectAll(loadPage('functionality.html'), '#lifecycle table');
    expect(tables).toHaveLength(1);
    expect(sortedCopy(listRowKeys(tables[0]))).toEqual(sortedCopy(listWorkflowNames()));
  });

  it('DASH BAN: no em or en dashes in shipped pages, styles, source, or README', () => {
    const offenders = listDashScanTargets().filter((path) => DASH_PATTERN.test(readFileSync(path, 'utf8')));
    expect(offenders).toEqual([]);
  });
});
