# hivemind website

The repo-root `README.md` is the canonical source of truth for all website content. This site (`web/`) mirrors that content. There is no automated sync. Any content edit must trace back to a claim in `README.md`.

## Design system

Every page follows these rules:

- Link `./styles/main.css` and `./scripts/main.js`.
- Include the shared head gate script.
- Use only classes defined in `main.css`.
- Use no `style` attributes.
- Sections declare `data-formation` (`hero`, `agents`, `workflow`, `install`, `ambient`).
- Install sections hold one `[data-orbit]`.
- Decode classes `xs` and `xg` go only on headings and intro text.
- Load no external resources.
- Use relative paths only (the Pages base path is `/hivemind/`).
- Use no em or en dashes.

The contract is pinned by `web/tests/dom-contract.test.ts`.

The prototypes now live in `docs/design/prototypes/`.
