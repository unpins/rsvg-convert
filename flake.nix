{
  description = "rsvg-convert (SVG → PNG/PDF/PS converter) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # librsvg ships the `rsvg-convert` CLI. Shared `nativeFixes.librsvg`:
  # (1) + libunwind (librsvg's rustc --print=native-static-libs emits
  #     -lunwind on musl; pkgsStatic forces the static probe);
  # (2) propagate pango (librsvg-2.0.pc Requires.private: pangocairo).
  # See nix-lib/native-overlay/librsvg.nix.
  outputs = { self, unpins-lib }:
    let ulib = unpins-lib.lib; in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "rsvg-convert";
      smoke = [ "--version" ];
      smokePattern = "^rsvg-convert version [0-9]+\\.[0-9]+";
      pkgsAttr = "librsvg";
      # Data directories baked in by the libraries: fontconfig's config templates
      # and nixpkgs' default font dir (dejavu), libxml2's XML catalog, glib's GIO
      # module/locale/dbus paths, libthai's word-break dictionary (and pango's
      # reference to it on i686). None exists off Nix, so the binary already
      # runs without them; left alone they pulled all of these into the closure.
      removeReferences = [
        "fontconfig-static" "dejavu-fonts" "libxml2-static" "glib-static"
        "libthai-static" "pango-static"
      ];

      # On darwin the transitive text/render chain (glib → harfbuzz,
      # pango, cairo) needs the same cross-within-darwin fixes ffmpeg
      # uses: glib/pango objc cross-file, graphite2 static-SONAME guard,
      # fontconfig doCheck path-symlink, cairo ipc_rmid_deferred_release.
      # Each fix short-circuits to prev.X off darwin, so linux passes
      # through unchanged.
      build = origPkgs:
        let
          host = origPkgs.stdenv.hostPlatform;
          pkgsStatic =
            if host.isDarwin
            then origPkgs.pkgsStatic.extend (final: prev: {
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
            # riscv64: libjpeg-turbo's RVV SIMD coverage helper fails to
            # compile (see nix-lib/native-overlay/libjpeg-turbo.nix). Pulled
            # via gdk-pixbuf → libtiff/libwebp. Gate to riscv so the other
            # arches keep the unmodified (cache-hit) libjpeg.
            else if host.isRiscV
            then origPkgs.pkgsStatic.extend (final: prev: {
              libjpeg = ulib.nativeFixes."libjpeg-turbo" prev;
            })
            else origPkgs.pkgsStatic;
        in
        (ulib.nativeFixes.librsvg pkgsStatic).overrideAttrs (oa: {
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

      # mingw-overlay/librsvg.nix (auto-applied by mingwStaticCross)
      # carries the cross-mingw library fixes: + winpthreads/mcfgthreads,
      # NIX_LDFLAGS_AFTER late-link for libintl, completion stubs.
      #
      # mingw single-binary policy. By default rsvg-convert.exe ships next
      # to libgcc_s_seh-1.dll, libstdc++-6.dll and libmcfgthread-2.dll.
      # Three independent leaks, three fixes — all CLI-only (ffmpeg's C
      # link never pulls these), so they stay out of nix-lib's overlay:
      #
      # 1. libgcc_s. cargoSetupHook writes the Rust target's `crt-static`
      #    from `targetPlatform.isStatic`, but `mingwStaticCross` only
      #    flips `hostPlatform.isStatic` (the white lie that makes C libs
      #    build `.a`), so the config lands `-Ctarget-feature=-crt-static`
      #    and rustc links the gnu runtime dynamically. Flip it to
      #    `+crt-static` in the generated `.cargo/config.toml`.
      #
      # 2. libstdc++ + libmcfgthread. rustc still links these as `dylib`
      #    kind: `-l stdc++` is emitted plain by a `-sys` build script (the
      #    C++ runtime for harfbuzz/graphite2), and the mingw-overlay
      #    appends `-lmcfgthread` via NIX_LDFLAGS_AFTER — neither carries
      #    the `static=` prefix system-deps gives the rest, so both resolve
      #    to `.dll.a` import libs. `+crt-static` doesn't touch them. Stage
      #    static-only copies of `libstdc++.a`/`libmcfgthread.a` in a dir
      #    and put it on the rustc link path via `-Lnative=`: rustc emits
      #    user `-L` ahead of both NIX_LDFLAGS (mcfgthread's lib dir) and
      #    gcc's internal dir (libstdc++'s `.dll.a`), and mingw ld tries
      #    `libNAME.dll.a` then `libNAME.a` *per directory* — so a dir with
      #    no `.dll.a` yields the static archive even under -Bdynamic.
      #    Static `libmcfgthread.a` then needs ntdll/kernel32 directly (the
      #    NT keyed-event + heap APIs the import DLL used to carry); append
      #    `-lntdll -lkernel32` after the overlay's trailing `-lmcfgthread`
      #    (single-pass ld, so they must follow it). Both are system DLLs.
      #
      # 3. `+crt-static` static-links libgcc, whose
      #    ___chkstk_ms/__udivmodti4/__udivti3 then collide with the
      #    compiler_builtins symbols Rust bundles in its own objects (the
      #    COMDAT/weak marking doesn't survive the dual-static-archive
      #    link). `-Wl,--allow-multiple-definition` is the canonical
      #    mingw+Rust workaround — the same flag ffmpeg's librsvg link uses.
      #
      # Result: a single rsvg-convert.exe importing only system DLLs.
      windowsBuild = pkgs:
        (ulib.mingwStaticCross pkgs).librsvg.overrideAttrs (oa: {
          preBuild = (oa.preBuild or "") + ''
            mkdir -p "$TMPDIR/static-rt"
            for lib in libstdc++.a libmcfgthread.a; do
              src=$($CC -print-file-name=$lib)
              [ -f "$src" ] || src=$(find /nix/store -maxdepth 3 \
                -name "$lib" -path '*mingw32*' 2>/dev/null | head -1)
              [ -f "$src" ] && cp "$src" "$TMPDIR/static-rt/"
            done
            cfg=$(grep -rl --include=config.toml 'crt-static' "$NIX_BUILD_TOP" | head -1)
            sed -i "s|-Ctarget-feature=-crt-static|-Ctarget-feature=+crt-static\", \"-Clink-arg=-Wl,--allow-multiple-definition\", \"-Lnative=$TMPDIR/static-rt|" "$cfg"
            # glib/gio's gwin32mount.c (pulled in statically via librsvg's rlib)
            # calls SHGetDesktopFolder / SHBindToParent — both exported by
            # shell32.dll. librsvg 2.62.1 (26.05) surfaces these in the static
            # link; add -lshell32 so the __imp_ imports resolve.
            export NIX_LDFLAGS_AFTER_x86_64_w64_mingw32="''${NIX_LDFLAGS_AFTER_x86_64_w64_mingw32:-} -lntdll -lkernel32 -lshell32"
          '';
        });
    };
}
