# shellcheck shell=bash
# Per-developer identity defaults for device/signing scripts. Sourced (not executed).
#
# Real values live in scripts/local.env (git-ignored; copy scripts/local.env.example). Anything
# already set in the environment wins, and every variable is defined (possibly empty) afterwards so
# `set -u` scripts can reference it:
#   VRMC_DEVICE_UDID     target Apple Vision Pro UDID (xcrun devicectl list devices)
#   VRMC_TEAM_ID         Apple developer team ID used for signing/profiles
#   VRMC_SIGN_IDENTITY   codesigning identity, e.g. "Apple Development: you@example.com (ABCDE12345)"
_vrmc_local_env="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/local.env"
if [ -f "$_vrmc_local_env" ]; then
  # shellcheck disable=SC1090
  . "$_vrmc_local_env"
fi
unset _vrmc_local_env
: "${VRMC_DEVICE_UDID:=}"
: "${VRMC_TEAM_ID:=}"
: "${VRMC_SIGN_IDENTITY:=}"
export VRMC_DEVICE_UDID VRMC_TEAM_ID VRMC_SIGN_IDENTITY
