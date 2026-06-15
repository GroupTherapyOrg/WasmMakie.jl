# Changelog

## [0.1.1](https://github.com/GroupTherapyOrg/WasmMakie.jl/compare/v0.1.0...v0.1.1) (2026-06-15)


### Features

* coalesce img_buf_push_rgba runs to base64 in recorded streams ([b0dd18a](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/b0dd18ae9ceb9e983157bdb7d5edbb2bbed081d2))
* docs site rendered by WasmMakie itself (WASMMAKIE-U-004) ([06ec3e9](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/06ec3e9944ade6ad2bbadfb0caf253e74e9b658b))


### Bug Fixes

* Cairo-exact nearest-neighbor blits + vendored ticks OOB — 90.4% refpass (WASMMAKIE-R-006) ([9306c80](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/9306c8015a0826b0361f6fa979b67977d58ec02f))
* font loading must never block drawing (WASMMAKIE-E-001) ([cd9f0ad](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/cd9f0ad3d081687056013ddf9019fbf6d4922e19))

## Changelog

Releases are managed by release-please from [Conventional
Commits](https://www.conventionalcommits.org) (`feat:` / `fix:` / `docs:` …);
entries below this line are generated. Campaign story ids appear in
parentheses, e.g. `feat: embedding contract (WASMMAKIE-E-001)`.
