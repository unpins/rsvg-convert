# Changelog

## [Unreleased]

### Fixed

- `nix build` and `nix run` downloaded 43 MB for a 17 MB program: the binary
  pointed at data folders of the libraries it was built with (fonts, XML
  catalog, GIO modules) that do not exist outside Nix and that it does not need.
  It now depends on nothing else.
