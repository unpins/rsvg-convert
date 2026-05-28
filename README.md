# rsvg-convert

Standalone build of [rsvg-convert](https://gitlab.gnome.org/GNOME/librsvg) — librsvg's SVG → PNG/PDF/PS/SVG converter CLI.

[![CI](https://github.com/unpins/rsvg-convert/actions/workflows/rsvg-convert.yml/badge.svg)](https://github.com/unpins/rsvg-convert/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

Rasterizes or converts SVG documents to PNG, PDF, PS, EPS, or SVG.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin rsvg-convert
```

Or run without installing:

```bash
unpin run rsvg-convert
```

## Build locally

```bash
nix build github:unpins/rsvg-convert
./result/bin/rsvg-convert --version
```

Or run directly:

```bash
nix run github:unpins/rsvg-convert -- input.svg -o output.png
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/rsvg-convert/releases) page has standalone binaries for manual download.

## Build notes

- **Windows:** `mingw` cross, single `.exe`, no companion DLLs.
- **No upstream features disabled** on any platform.

Platform fixes live in [`nix-lib/native-overlay/librsvg.nix`](https://github.com/unpins/nix-lib/blob/main/native-overlay/librsvg.nix) and [`nix-lib/mingw-overlay/librsvg.nix`](https://github.com/unpins/nix-lib/blob/main/mingw-overlay/librsvg.nix).
