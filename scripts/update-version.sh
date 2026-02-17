#!/usr/bin/env bash
set -euo pipefail

# Update OpenCode version in package.nix and package-desktop.nix
# Usage:
#   ./scripts/update-version.sh              # Update to latest
#   ./scripts/update-version.sh --check      # Check if update available
#   ./scripts/update-version.sh --version X  # Update to specific version

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check_only=false
target_version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) check_only=true; shift ;;
        --version) target_version="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--check] [--version VERSION]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

current_version=$(grep -oP 'version = "\K[^"]+' "$REPO_DIR/package.nix" | head -1)
[[ -z "$target_version" ]] && target_version=$(gh api repos/anomalyco/opencode/releases/latest --jq '.tag_name | ltrimstr("v")')

echo "Current: $current_version -> Target: $target_version"

[[ "$current_version" == "$target_version" ]] && { echo "Already up to date!"; exit 0; }
[[ "$check_only" == "true" ]] && exit 0

fetch_hash() {
    nix store prefetch-file --json "$1" 2>/dev/null | jq -r '.hash'
}

update_hash() {
    local file="$1" platform="$2" hash="$3"
    sed -i "s|\"${platform}\"[[:space:]]*= \"[^\"]*\"|\"${platform}\" = \"${hash}\"|" "$file"
}

echo "Fetching hashes..."

# CLI package
for platform in linux-x64 linux-arm64 darwin-x64 darwin-arm64; do
    ext=$([[ "$platform" == darwin* ]] && echo "zip" || echo "tar.gz")
    hash=$(fetch_hash "https://github.com/anomalyco/opencode/releases/download/v${target_version}/opencode-${platform}.${ext}")
    echo "  $platform: $hash"
    update_hash "$REPO_DIR/package.nix" "$platform" "$hash"
done

# Desktop package
declare -A desktop_ext=(["linux-amd64"]="deb" ["linux-arm64"]="deb" ["darwin-x64"]="app.tar.gz" ["darwin-aarch64"]="app.tar.gz")
for platform in "${!desktop_ext[@]}"; do
    hash=$(fetch_hash "https://github.com/anomalyco/opencode/releases/download/v${target_version}/opencode-desktop-${platform}.${desktop_ext[$platform]}")
    echo "  desktop $platform: $hash"
    update_hash "$REPO_DIR/package-desktop.nix" "$platform" "$hash"
done

# Update versions
sed -i "s/version = \"${current_version}\"/version = \"${target_version}\"/" "$REPO_DIR/package.nix" "$REPO_DIR/package-desktop.nix"

echo "Updating flake.lock..."
nix flake update --flake "$REPO_DIR" 2>/dev/null || true

echo "Done! Test with: nix build && ./result/bin/opencode --version"
