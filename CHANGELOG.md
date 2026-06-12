# Changelog

## [0.1.1](https://github.com/GroupTherapyOrg/WasmMakie.jl/compare/v0.1.0...v0.1.1) (2026-06-12)


### Features

* coalesce img_buf_push_rgba runs to base64 in recorded streams ([b0dd18a](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/b0dd18ae9ceb9e983157bdb7d5edbb2bbed081d2))
* docs site rendered by WasmMakie itself (WASMMAKIE-U-004) ([06ec3e9](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/06ec3e9944ade6ad2bbadfb0caf253e74e9b658b))
* release engineering — release-please, CHANGELOG, working CI (WASMMAKIE-U-001) ([f1e5c2d](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/f1e5c2d2a9f034a14dedd3b8d3ccdd69d4eb1020))
* solid-color meshes render as canvas path fills (WASMMAKIE-R-006) ([c0c4be4](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/c0c4be4612216239f5922271975b4761a0e95831))


### Bug Fixes

* 2D-scope title skips — Textbox interactivity, 3D-mesh content (WASMMAKIE-R-006) ([a44e5ac](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/a44e5acaf98aa039ca3b2fd716c766285181d55b))
* C-002 oracle — isolated CI step, file IO, value comparison dodges 1.12 GC segv (WASMMAKIE-U-001) ([1678677](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/167867711cec7ff194fde99dfbb399f27b90d00e))
* Cairo-exact nearest-neighbor blits + vendored ticks OOB — 90.4% refpass (WASMMAKIE-R-006) ([9306c80](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/9306c8015a0826b0361f6fa979b67977d58ec02f))
* EXTEND_PAD-equivalent interpolated image blits (WASMMAKIE-R-006) ([529ae69](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/529ae69a2a6cc63b1412409b997114ed4ab2e150))
* font loading must never block drawing (WASMMAKIE-E-001) ([cd9f0ad](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/cd9f0ad3d081687056013ddf9019fbf6d4922e19))
* hybrid mesh compositing — same-color replace, distinct-surface source-over (WASMMAKIE-R-006) ([883a9db](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/883a9dbe6b31b8ac28886d18059edc14e8a45e66))
* julia compat includes 1.13 — Therapy CI's 1.13-rc leg resolves WasmMakie (WASMMAKIE-U-001) ([7186ac3](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/7186ac35b33dd584ae20584937e54179cfb00ac5))
* pin CI's WasmTarget checkout to bugsmash-post-0.3.1 (WASMMAKIE-U-001) ([d4b2ff7](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/d4b2ff70d766fe645c366b5ac745a1dbdc17de90))
* poly fallback, image markers, mesh NaN/AA/compositing, recipe recursion (WASMMAKIE-R-006) ([bed4a4c](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/bed4a4cbb73a7aad0e0f74791840c030d123fba2))
* portable julia invocation in the C-002 subprocess oracle (WASMMAKIE-U-001) ([07b6b4f](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/07b6b4f128fde27f659ec7efa3388b3e0486353a))
* unpin CI's WasmTarget checkout — bugsmash merged, v0.3.2 on main (WASMMAKIE-U-001) ([8068210](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/806821016e0f48e1611fe0fd3b837b43fde92cb5))
* W-005 stream normalization via file — Linux caps argv at 128KB (WASMMAKIE-U-001) ([d0253ef](https://github.com/GroupTherapyOrg/WasmMakie.jl/commit/d0253ef49d5edf47b73dcaa2b662f2ab47159219))

## Changelog

Releases are managed by release-please from [Conventional
Commits](https://www.conventionalcommits.org) (`feat:` / `fix:` / `docs:` …);
entries below this line are generated. Campaign story ids appear in
parentheses, e.g. `feat: embedding contract (WASMMAKIE-E-001)`.
