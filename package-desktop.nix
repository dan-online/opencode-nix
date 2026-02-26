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
, gst_all_1 ? null
, binName ? "opencode-desktop"
}:

let
  version = "1.2.15";

  # Shell wrapper to work around Tauri sidecar spawning (see script for details)
  shellWrapper = ./scripts/tauri-shell-wrapper.sh;

  platformMap = {
    "x86_64-linux" = { target = "linux-amd64"; ext = "deb"; };
    "aarch64-linux" = { target = "linux-arm64"; ext = "deb"; };
    "x86_64-darwin" = { target = "darwin-x64"; ext = "app.tar.gz"; };
    "aarch64-darwin" = { target = "darwin-aarch64"; ext = "app.tar.gz"; };
  };

  platformInfo = platformMap.${stdenv.hostPlatform.system} or
    (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

  hashes = {
    "linux-amd64" = "sha256-TJmFT+ZUtnb3O7LG2xrJJKJBt+VNkTs4jk45j8mnHPE=";
    "linux-arm64" = "sha256-wlEfUjNASbo0xkC4gfwTwmWghkv1rEahKvOLhWJUL2c=";
    "darwin-x64" = "sha256-b0yYuzGufXGq+0tc7W59QFNXfmEHTLBzHWXX2ruiiIo=";
    "darwin-aarch64" = "sha256-dWM7gFBeO7S9quefSsK7fElIn2ewTFeIGAXh2Hvm1dA=";
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
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
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

    # Install shell wrapper for Tauri sidecar spawning workaround
    install -Dm755 ${shellWrapper} "$out/bin/.shell-wrapper"

    makeBinaryWrapper "$out/bin/.OpenCode-unwrapped" "$out/bin/${binName}" \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath linuxLibs}"''} \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--set OC_ALLOW_WAYLAND 1''} \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--prefix GST_PLUGIN_PATH : "${lib.makeSearchPath "lib/gstreamer-1.0" [gst_all_1.gstreamer gst_all_1.gst-plugins-base gst_all_1.gst-plugins-good]}"''} \
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
