# OpenCode Package
#
# This package installs OpenCode (anomalyco/opencode) - the open source AI coding agent.
# It fetches pre-built native binaries from GitHub releases.
#
# Supported platforms: linux-x64, linux-arm64, darwin-x64, darwin-arm64

{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, autoPatchelfHook
, unzip
, zlib
, openssl
, icu
, binName ? "opencode"
}:

let
  version = "1.2.21";

  # Platform mapping: Nix system -> OpenCode release target
  platformMap = {
    "x86_64-linux"   = { target = "linux-x64";      ext = "tar.gz"; };
    "aarch64-linux"  = { target = "linux-arm64";     ext = "tar.gz"; };
    "x86_64-darwin"  = { target = "darwin-x64";      ext = "zip";    };
    "aarch64-darwin" = { target = "darwin-arm64";     ext = "zip";    };
  };

  platformInfo = platformMap.${stdenv.hostPlatform.system} or
    (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

  # Per-platform hashes (nix-prefetch-url, no --unpack)
  hashes = {
    "linux-x64" = "sha256-TM1e6DIv+X+TITSaBk3cTCubWbM1M20tKqAGcK8gBhc=";
    "linux-arm64" = "sha256-h6SFSsfAb2t51TmvD16yRkSIHptXvE1GwYj7kV7LaPE=";
    "darwin-x64" = "sha256-94uTMuDax5U7Sf0nKZXXSrqtLclmS2Jf3T2x0q56Jqs=";
    "darwin-arm64" = "sha256-Qy1TmVeXxJaz+zTdEUJryoLdjldB9bpQltUF+JXDnig=";
  };

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-${platformInfo.target}.${platformInfo.ext}";
    sha256 = hashes.${platformInfo.target};
  };

in
stdenv.mkDerivation {
  pname = "opencode";
  inherit version;

  inherit src;

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs = [ makeBinaryWrapper unzip ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # Runtime deps for the dynamically linked binary on Linux
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    zlib
    openssl
    icu
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Extract the binary from the archive
    ${if platformInfo.ext == "tar.gz" then ''
      tar -xzf $src
    '' else ''
      unzip -q $src
    ''}

    install -m755 opencode $out/bin/.opencode-unwrapped
    makeBinaryWrapper $out/bin/.opencode-unwrapped $out/bin/${binName}

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenCode - the open source AI coding agent";
    homepage = "https://opencode.ai";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    mainProgram = binName;
  };
}
