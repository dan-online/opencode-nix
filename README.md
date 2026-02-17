# opencode-nix

Always up-to-date Nix package for [OpenCode](https://opencode.ai) - the open source AI coding agent.

New versions are available within the hour of release, automatically.

## Why?

OpenCode is distributed as a pre-built binary via GitHub releases and npm. While `nixpkgs` has an OpenCode package, updates depend on upstream PR review cycles which can take days. This flake:

- **Checks for new releases every hour** and auto-merges updates
- **Fetches native binaries** directly from GitHub releases - no build from source needed
- **Patches for NixOS** via `autoPatchelfHook` so the binary just works
- **Provides an overlay** so `pkgs.opencode` slots into any Nix config

## Quick Start

```bash
# Try it without installing
nix run github:dan-online/opencode-nix
nix run github:dan-online/opencode-nix#opencode-desktop

# Install to your profile
nix profile install github:dan-online/opencode-nix
nix profile install github:dan-online/opencode-nix#opencode-desktop

# Update later
nix profile upgrade '.*opencode.*'
```

## Usage

### shell.nix

```nix
{ pkgs ? import <nixpkgs> {
    overlays = [
      (builtins.getFlake "github:dan-online/opencode-nix").overlays.default
    ];
  }
}:

pkgs.mkShell {
  packages = [ pkgs.opencode ];
}
```

### flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    opencode.url = "github:dan-online/opencode-nix";
  };

  outputs = { nixpkgs, opencode, ... }: {
    devShells.x86_64-linux.default = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ opencode.overlays.default ];
      };
    in pkgs.mkShell {
      packages = [ pkgs.opencode ];
    };
  };
}
```

### Home Manager

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    opencode.url = "github:dan-online/opencode-nix";
  };

  outputs = { nixpkgs, home-manager, opencode, ... }: {
    homeConfigurations."you" = home-manager.lib.homeManagerConfiguration {
      modules = [{
        nixpkgs.overlays = [ opencode.overlays.default ];
        home.packages = [ pkgs.opencode ];
      }];
    };
  };
}
```

### NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    opencode.url = "github:dan-online/opencode-nix";
  };

  outputs = { nixpkgs, opencode, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [{
        nixpkgs.overlays = [ opencode.overlays.default ];
        environment.systemPackages = [ pkgs.opencode ];
      }];
    };
  };
}
```

## Supported Platforms

CLI package (`opencode`):

| Platform | Architecture | Archive |
|----------|-------------|---------|
| Linux | x86_64 | `.tar.gz` |
| Linux | aarch64 | `.tar.gz` |
| macOS | x86_64 (Intel) | `.zip` |
| macOS | aarch64 (Apple Silicon) | `.zip` |

Desktop package (`opencode-desktop`):

| Platform | Architecture | Archive |
|----------|-------------|---------|
| Linux | x86_64 | `.deb` |
| Linux | aarch64 | `.deb` |
| macOS | x86_64 (Intel) | `.app.tar.gz` |
| macOS | aarch64 (Apple Silicon) | `.app.tar.gz` |

## How Updates Work

A GitHub Actions workflow runs every hour:

1. Queries the [anomalyco/opencode](https://github.com/anomalyco/opencode) releases API for the latest version
2. Compares against the version in `package.nix`
3. If newer, fetches hashes for all four platform binaries
4. Opens a PR with the version bump
5. CI builds and tests on Ubuntu and macOS
6. PR auto-merges on success

## Development

```bash
# Clone
git clone https://github.com/dan-online/opencode-nix
cd opencode-nix

# Build locally
nix build
./result/bin/opencode --version

# Check for updates
./scripts/update-version.sh --check

# Update to latest
./scripts/update-version.sh

# Update to a specific version
./scripts/update-version.sh --version 1.2.0
```

## Acknowledgements

Inspired by [sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix), which does the same thing for Claude Code. The hourly auto-update workflow and overall flake structure are modelled after that project.

## License

MIT. OpenCode itself is [MIT licensed](https://github.com/anomalyco/opencode/blob/dev/LICENSE).
