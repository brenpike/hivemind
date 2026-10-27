# Vendored acorn

This directory holds an unmodified copy of the acorn JavaScript parser. Do not edit the vendored files.

## Provenance

| Field | Value |
|---|---|
| Package | `acorn` |
| Version | `8.19.0` |
| Tarball | https://registry.npmjs.org/acorn/-/acorn-8.19.0.tgz |
| Tarball integrity | `sha512-oJlA3XiRm7Cyk6qFD2Jn8ak9B7jSy0qy00ADO3+8dpT0LSjFihQYv4C02LFCSYJV3Q37xYwwRy5m+IpIiUzqWw==` |
| `acorn.mjs` sha256 | `76254fc76529713b4dfd2532972d17a991ffd9aafeebb1f977445b5506b9fb0b` |

Files taken from the tarball, byte for byte:

- `package/dist/acorn.mjs` is `acorn.mjs` here.
- `package/LICENSE` is `LICENSE` here (MIT).

Nothing else from the tarball is kept, and nothing from it was run.

## Why the build vendors a parser

`tools/build_workflows.mjs` needs a real JavaScript parser. It reads every workflow source through acorn's tokens, comments and syntax tree, and it proves that comment stripping and compaction keep the code the same by comparing syntax trees. A hand-written lexer cannot tell a regex from a division after every token, so it can change code without an error.

Vendoring keeps Node 18 the only thing validation needs, with no install step. The root `package.json` is website tooling, and validation never installs it.

`.gitattributes` checks out every file under `tools/vendor/` with no line-ending conversion, so the sha256 pin holds on every checkout.

## Updating the copy

1. Pick the new version and read its `dist.integrity` from `https://registry.npmjs.org/acorn/<version>`.
2. Download `https://registry.npmjs.org/acorn/-/acorn-<version>.tgz` into a new, empty scratch directory outside the repository.
3. Check the tarball against that integrity before extracting anything:

   ```bash
   printf 'sha512-%s\n' "$(openssl dgst -sha512 -binary acorn-<version>.tgz | base64 -w0)"
   ```

4. Extract only `package/dist/acorn.mjs` and `package/LICENSE`. Run nothing from the tarball.
5. Copy them over `acorn.mjs` and `LICENSE` here, unchanged.
6. Compute the new pin with `sha256sum tools/vendor/acorn/acorn.mjs`.
7. Update the version, tarball URL, tarball integrity and `acorn.mjs` sha256 in the table above, and the sha256 pin in the hash-pin test in `tests/workflow-scripts/build.test.mjs`.
8. Run `bash tools/validate.sh --changed`.
