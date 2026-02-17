#!/bin/sh
# Shell wrapper to work around Tauri sidecar spawning behavior.
#
# opencode-desktop spawns the CLI sidecar via: $SHELL -il -c "opencode-cli serve ..."
# The -il flags create an interactive login shell, which causes issues on NixOS
# with zsh (the shell waits for input, stopping the sidecar process).
#
# This wrapper strips the -il flags while preserving the -c command execution.
# See: https://github.com/anomalyco/opencode/blob/dev/packages/desktop/src-tauri/src/cli.rs

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
