# rsvg-convert

[rsvg-convert](https://gitlab.gnome.org/GNOME/librsvg) — convert SVG images to PNG, PDF, PostScript, EPS or SVG. A single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/rsvg-convert/actions/workflows/rsvg-convert.yml/badge.svg)](https://github.com/unpins/rsvg-convert/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install rsvg-convert`.

## Usage

Run the `rsvg-convert` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin rsvg-convert in.svg -o out.png
```

To install it onto your PATH:

```bash
unpin install rsvg-convert
```

## Man pages

`rsvg-convert.1` is embedded in the binary — read it with `unpin man rsvg-convert`.

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

- **Images inside SVGs:** PNG, JPEG, GIF, WebP and AVIF.
- **Text** uses the system's fonts: fontconfig on Linux, Core Text on macOS and
  DirectWrite on Windows.
