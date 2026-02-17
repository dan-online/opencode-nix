#!/usr/bin/env bash
set -euo pipefail

# Update OpenCode version in package.nix
# Usage:
#   ./scripts/update-version.sh              # Update to latest
#   ./scripts/update-version.sh --check      # Check if update available
#   ./scripts/update-version.sh --version X  # Update to specific version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGE_NIX="$REPO_DIR/package.nix"
DESKTOP_PACKAGE_NIX="$REPO_DIR/package-desktop.nix"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_only=false
target_version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            check_only=true
            shift
            ;;
        --version)
            target_version="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--check] [--version VERSION]"
            echo ""
            echo "Options:"
            echo "  --check           Only check if a new version is available"
            echo "  --version VERSION Update to a specific version (e.g., 1.1.64)"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Get current version from package.nix
current_version=$(grep 'version = "' "$PACKAGE_NIX" | head -1 | sed 's/.*version = "\(.*\)";/\1/')
echo -e "Current version: ${YELLOW}${current_version}${NC}"

# Get latest version from GitHub
if [[ -z "$target_version" ]]; then
    api_response=$(curl -s https://api.github.com/repos/anomalyco/opencode/releases/latest)

    latest_tag=$(echo "$api_response" | jq -r '.tag_name // empty' | sed 's/^v//')

    if [[ -z "$latest_tag" ]]; then
        echo -e "${RED}Failed to fetch latest version from GitHub${NC}"
        exit 1
    fi
    target_version="$latest_tag"
fi

echo -e "Target version:  ${YELLOW}${target_version}${NC}"

if [[ "$current_version" == "$target_version" ]]; then
    echo -e "${GREEN}Already up to date!${NC}"
    exit 0
fi

echo -e "${GREEN}New version available: ${target_version}${NC}"

if [[ "$check_only" == "true" ]]; then
    exit 0
fi

echo ""
echo "Fetching hashes for all platforms..."

# Platforms to fetch
declare -A platforms
platforms=(
    ["linux-x64"]="tar.gz"
    ["linux-arm64"]="tar.gz"
    ["darwin-x64"]="zip"
    ["darwin-arm64"]="zip"
)

declare -A new_hashes

for platform in "${!platforms[@]}"; do
    ext="${platforms[$platform]}"
    url="https://github.com/anomalyco/opencode/releases/download/v${target_version}/opencode-${platform}.${ext}"
    echo -n "  Fetching ${platform}... "

    json=$(nix store prefetch-file --json "$url" 2>/dev/null)
    if [[ -z "$json" ]]; then
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}Could not fetch hash for ${platform}. Release may not exist.${NC}"
        exit 1
    fi

    hash=$(echo "$json" | jq -r '.hash')
    new_hashes["$platform"]="$hash"
    echo -e "${GREEN}${hash}${NC}"
done

# Desktop platforms to fetch
declare -A desktop_platforms
desktop_platforms=(
    ["linux-amd64"]="deb"
    ["linux-arm64"]="deb"
    ["darwin-x64"]="app.tar.gz"
    ["darwin-aarch64"]="app.tar.gz"
)

declare -A new_desktop_hashes

for platform in "${!desktop_platforms[@]}"; do
    ext="${desktop_platforms[$platform]}"
    url="https://github.com/anomalyco/opencode/releases/download/v${target_version}/opencode-desktop-${platform}.${ext}"
    echo -n "  Fetching desktop ${platform}... "

    # Use nix store prefetch-file for SRI hash format
    json=$(nix store prefetch-file --json "$url" 2>/dev/null)
    if [[ -z "$json" ]]; then
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}Could not fetch desktop hash for ${platform}. Release may not exist.${NC}"
        exit 1
    fi

    hash=$(echo "$json" | jq -r '.hash')
    new_desktop_hashes["$platform"]="$hash"
    echo -e "${GREEN}${hash}${NC}"
done

echo ""
echo "Updating package.nix..."

# Update version
sed -i "s/version = \"${current_version}\"/version = \"${target_version}\"/" "$PACKAGE_NIX"
sed -i "s/version = \"${current_version}\"/version = \"${target_version}\"/" "$DESKTOP_PACKAGE_NIX"

# Update hashes
for platform in "${!new_hashes[@]}"; do
    hash="${new_hashes[$platform]}"
    # Match the hash line for this platform and replace just the hash value
    sed -i "s|\"${platform}\"[[:space:]]*= \"[^\"]*\"|\"${platform}\" = \"${hash}\"|" "$PACKAGE_NIX"
done

for platform in "${!new_desktop_hashes[@]}"; do
    hash="${new_desktop_hashes[$platform]}"
    sed -i "s|\"${platform}\"[[:space:]]*= \"[^\"]*\"|\"${platform}\" = \"${hash}\"|" "$DESKTOP_PACKAGE_NIX"
done

# Verify the update
new_version=$(grep 'version = "' "$PACKAGE_NIX" | head -1 | sed 's/.*version = "\(.*\)";/\1/')
if [[ "$new_version" == "$target_version" ]]; then
    echo -e "${GREEN}Successfully updated to ${target_version}${NC}"
else
    echo -e "${RED}Update failed - version mismatch${NC}"
    exit 1
fi

# Update flake.lock
echo "Updating flake.lock..."
(cd "$REPO_DIR" && nix flake update 2>/dev/null) || true

echo ""
echo -e "${GREEN}Done! You can now test with:${NC}"
echo "  nix build"
echo "  ./result/bin/opencode --version"
