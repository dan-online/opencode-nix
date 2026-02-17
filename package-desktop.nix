{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, autoPatchelfHook
, unzip
, binutils
, zlib
, openssl
, icu
, gtk3 ? null
, gdk-pixbuf ? null
, cairo ? null
, glib ? null
, webkitgtk_4_1 ? null
, libsoup_3 ? null
, binName ? "opencode-desktop"
}:

let
  version = "1.2.6";

  platformMap = {
    "x86_64-linux" = { target = "linux-amd64"; ext = "deb"; };
    "aarch64-linux" = { target = "linux-arm64"; ext = "deb"; };
    "x86_64-darwin" = { target = "darwin-x64"; ext = "app.tar.gz"; };
    "aarch64-darwin" = { target = "darwin-aarch64"; ext = "app.tar.gz"; };
  };

  platformInfo = platformMap.${stdenv.hostPlatform.system} or
    (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

  hashes = {
    "linux-amd64" = "sha256-AYCgmSCR2Qmnuows6IYS4rmut6RISS4c1fGArV/I4lw=";
    "linux-arm64" = "sha256-q5YYM3oho+tXgBrbBvssttBlIpfKN5Nx6AyT0Homsq0=";
    "darwin-x64" = "sha256-thf+djaMRfo30trZq37OTu7W4AWOprh27+q+3lrAMfs=";
    "darwin-aarch64" = "sha256-ch91mdUJDOxdJ2/7exfrA1bxFffu1DukjA2PqsMJl54=";
  };

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-desktop-${platformInfo.target}.${platformInfo.ext}";
    sha256 = hashes.${platformInfo.target};
  };

  linuxLibs = [
    stdenv.cc.cc.lib
    zlib
    openssl
    icu
    gtk3
    gdk-pixbuf
    cairo
    glib
    webkitgtk_4_1
    libsoup_3
  ];
in
stdenv.mkDerivation {
  pname = "opencode-desktop";
  inherit version src;

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [ makeBinaryWrapper unzip ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook binutils ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux linuxLibs;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"

    if [ "${stdenv.hostPlatform.system}" = "x86_64-linux" ] || [ "${stdenv.hostPlatform.system}" = "aarch64-linux" ]; then
      mkdir -p unpack
      cd unpack

      ar x "$src"
      tar -xzf data.tar.gz

      install -Dm755 usr/bin/OpenCode "$out/bin/.OpenCode-unwrapped"
      install -Dm755 usr/bin/opencode-cli "$out/bin/.opencode-cli-unwrapped"
      cp -R usr/share "$out/share"
    else
      tar -xzf "$src"

      mkdir -p "$out/Applications"
      cp -R OpenCode.app "$out/Applications/"

      install -Dm755 OpenCode.app/Contents/MacOS/OpenCode "$out/bin/.OpenCode-unwrapped"
      install -Dm755 OpenCode.app/Contents/MacOS/opencode-cli "$out/bin/.opencode-cli-unwrapped"
    fi

    # Copy the bundled opencode-cli directly (autoPatchelf fixes rpath on Linux)
    cp "$out/bin/.opencode-cli-unwrapped" "$out/bin/opencode-cli"

    # Shell wrapper to work around Tauri sidecar spawning behavior.
    #
    # opencode-desktop spawns the CLI sidecar via: $SHELL -il -c "opencode-cli serve ..."
    # The -il flags create an interactive login shell, which causes issues on NixOS
    # with zsh (the shell waits for input, stopping the sidecar process).
    #
    # This wrapper strips the -il flags while preserving the -c command execution.
    # See: https://github.com/anomalyco/opencode/blob/dev/packages/desktop/src-tauri/src/cli.rs
    cat > "$out/bin/.shell-wrapper" << 'EOF'
#!/bin/sh
# Tauri sidecar shell wrapper - strips interactive flags
cmd=""
found_c=false
for arg in "$@"; do
  case "$arg" in
    -i|-l|-il|-li) continue ;;
    -c) found_c=true ;;
    *)
      if $found_c; then
        cmd="$arg"
        break
      fi
      ;;
  esac
done
if [ -n "$cmd" ]; then
  exec /bin/sh -c "$cmd"
else
  exec /bin/sh "$@"
fi
EOF
    chmod +x "$out/bin/.shell-wrapper"

    makeBinaryWrapper "$out/bin/.OpenCode-unwrapped" "$out/bin/${binName}" \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath linuxLibs}"''} \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--set OC_ALLOW_WAYLAND 1''} \
      --set SHELL "$out/bin/.shell-wrapper"

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenCode Desktop - AI coding assistant GUI";
    homepage = "https://opencode.ai";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    mainProgram = binName;
  };
}
