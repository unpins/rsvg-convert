# Changelog

## [Unreleased]

### Fixed

- The binary no longer names a Nix store path as libxml2's default XML
  catalog; it now names `/etc/xml/catalog`, where Linux distributions keep it.
- FreeType no longer looks for a HarfBuzz shared library at run time. It used
  one, when the system had it, to hint glyphs such as small caps and
  superscripts; that HarfBuzz is now built into the binary, so the result no
  longer depends on what the system has installed.

## [2.62.3-1] - 2026-09-26

### Changed

- Updated to librsvg 2.62.3.

### Fixed

- `nix build` and `nix run` downloaded 43 MB for a 17 MB program: the binary
  pointed at data folders of the libraries it was built with (fonts, XML
  catalog, GIO modules) that do not exist outside Nix and that it does not need.
  It now depends on nothing else.
