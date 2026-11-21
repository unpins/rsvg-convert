{
  description = "rsvg-convert (SVG → PNG/PDF/PS converter) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # librsvg ships the `rsvg-convert` CLI. The library fixes it shares with
  # chafa, ffmpeg and fpcalc live in nix-lib/native-overlay/librsvg.nix.
  outputs = { self, unpins-lib }:
    let ulib = unpins-lib.lib; in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "rsvg-convert";
      smoke = [ "--version" ];
      smokePattern = "^rsvg-convert version [0-9]+\\.[0-9]+";
      pkgsAttr = "librsvg";
      # Data directories baked in by the libraries: fontconfig's config templates
      # and nixpkgs' default font dir (dejavu), glib's GIO module/locale/dbus
      # paths, libthai's word-break dictionary (and pango's reference to it on
      # i686). None exists off Nix, so the binary already
      # runs without them; left alone they pulled all of these into the closure.
      removeReferences = [
        "fontconfig-static" "dejavu-fonts" "glib-static"
        "libthai-static" "pango-static"
      ];

      # Linux builds librsvg in the engine set (the one chafa, ffmpeg and
      # fpcalc link it from), with rust-overlay's prebuilt rustc. Darwin
      # keeps a pristine pkgsStatic, outside the engine, so the fixes
      # nix-lib autoWires there are applied here by hand. The text/render
      # chain (glib → harfbuzz, pango, cairo) needs the same fixes ffmpeg
      # uses: glib/pango objc cross-file, graphite2 build-time python
      # (withPackages loses splicing), fontconfig with upstream's default
      # font folders and its doCheck off, cairo ipc_rmid_deferred_release.
      build = origPkgs:
        let
          host = origPkgs.stdenv.hostPlatform;
          darwinStatic = origPkgs.pkgsStatic.appendOverlays [
            (final: prev: {
              glib       = ulib.nativeFixes.glib       prev;
              graphite2  = ulib.nativeFixes.graphite2  prev;
              fontconfig = ulib.nativeFixes.fontconfig prev;
              pango      = ulib.nativeFixes.pango      prev;
              cairo      = ulib.nativeFixes.cairo      prev;
              # librsvg buildInputs pull dav1d; nixpkgs writes
              # cpu_family='arm64' into the darwin-aarch64 meson machine
              # file (native macos-14 runner included), tripping dav1d's
              # 'aarch64'-keyed asm dispatch. Same fix ffmpeg applies.
              dav1d      = ulib.nativeFixes.dav1d      prev;
            })
            # nix-lib's autoWired libxml2 fix (sysconfdir=/etc) never reaches
            # this set; without it the binary carries libxml2's store catalog
            # path. Gated per stage: libxml2 is in the darwin stdenv
            # bootstrap, and an ungated override rebuilds the toolchain.
            (final: prev:
              if !(prev.stdenv.hostPlatform.isStatic or false) then { }
              else { libxml2 = ulib.nativeFixes.libxml2 prev; })
          ];
          librsvg =
            if host.isLinux
            then (ulib.enginePkgsStaticFor {
              pkgs = origPkgs;
              toolchain = ulib.unpinToolchain origPkgs.stdenv.buildPlatform.system;
            }).librsvg
            else ulib.nativeFixes.librsvg darwinStatic;
        in
        librsvg.overrideAttrs (oa: {
          # `--version` only proves the binary loads. Render a real document —
          # shapes, text, an embedded PNG and JPEG — to PNG, PDF and SVG, on
          # every target the build machine can run (i686 is never run in CI).
          # The SVG output keeps an <image> only for a picture that decoded.
          doInstallCheck = oa.doInstallCheck or false
            || origPkgs.stdenv.buildPlatform.canExecute host;
          installCheckPhase = ''
            runHook preInstallCheck
            r=$out/bin/rsvg-convert
            cat > $TMPDIR/t.svg <<'SVG'
            <svg xmlns="http://www.w3.org/2000/svg" width="64" height="32">
              <rect width="64" height="32" fill="#36c"/><circle cx="16" cy="16" r="8" fill="red"/>
              <text x="4" y="28" font-size="10">unpins</text>
            </svg>
            SVG
            $r $TMPDIR/t.svg -o $TMPDIR/t.png
            [ "$(od -An -tx1 -N24 $TMPDIR/t.png | tr -d ' \n')" = 89504e470d0a1a0a0000000d494844520000004000000020 ] \
              || { echo "installCheck: PNG output is not a 64x32 PNG" >&2; exit 1; }
            $r -f pdf $TMPDIR/t.svg -o $TMPDIR/t.pdf
            [ "$(head -c 5 $TMPDIR/t.pdf)" = %PDF- ] || { echo "installCheck: PDF output is not a PDF" >&2; exit 1; }
            # One picture per file: cairo may rasterize a page into a single
            # <image>, so only "some image vs none" tells a decode apart.
            for img in png:iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAEElEQVR4nGP8ywACLGCSAQANEQED1LYyQAAAAABJRU5ErkJggg== jpeg:/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMAD/2wBDAAgUFBcUFxsbGxsbGyAeICEhISAgICAhISEkJCQqKiokJCQhISQkKCgqKi4vLisrKisvLzIyMjw8OTlGRkhWVmf/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAIAAgDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z; do
              printf '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><image width="16" height="16" href="data:image/%s;base64,%s"/></svg>' \
                "''${img%%:*}" "''${img#*:}" > $TMPDIR/i.svg
              $r -f svg $TMPDIR/i.svg -o $TMPDIR/out.svg
              grep -q '<image' $TMPDIR/out.svg \
                || { echo "installCheck: the embedded ''${img%%:*} did not decode" >&2; exit 1; }
            done
            runHook postInstallCheck
          '';
        });

      # The engine's mingw set, the one chafa and ffmpeg link librsvg from:
      # clang + lld, libc++/libunwind and rust's `-gnullvm` std, so no gcc
      # runtime (libgcc, libstdc++, mcfgthread) exists to leak as a DLL.
      # mingw-overlay/librsvg.nix (auto-applied by mingwStaticCross) and
      # `nativeFixes.librsvg` carry the library fixes.
      windowsBuild = _pkgs:
        ulib.nativeFixes.librsvg (ulib.mingwStaticCross ulib.windowsEnginePkgsShared);
    };
}
