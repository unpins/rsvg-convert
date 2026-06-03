{
  description = "Standalone build of rsvg-convert (SVG → PNG/PDF/PS converter)";

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
      pkgsAttr = "librsvg";

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
        ulib.nativeFixes.librsvg pkgsStatic;

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
