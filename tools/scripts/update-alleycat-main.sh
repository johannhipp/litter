#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="all"
case "${1:-}" in
  "")
    ;;
  --all|--shared|--kittylitter)
    MODE="${1#--}"
    ;;
  *)
    echo "usage: $(basename "$0") [--all|--shared|--kittylitter]" >&2
    exit 1
    ;;
esac

if [ "${LITTER_SKIP_ALLEYCAT_UPDATE:-0}" = "1" ]; then
  echo "==> Skipping Alleycat main refresh (LITTER_SKIP_ALLEYCAT_UPDATE=1)"
  exit 0
fi

KITTYLITTER_ALLEYCAT_REPO="${KITTYLITTER_ALLEYCAT_REPO:-johannhipp/alleycat}"
KITTYLITTER_ALLEYCAT_REF="${KITTYLITTER_ALLEYCAT_REF:-omp-support}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required" >&2
  exit 1
fi

ALLEYCAT_MAIN_SHA="$(
  git ls-remote https://github.com/dnakov/alleycat.git refs/heads/main \
    | awk '{ print $1; exit }'
)"
if [ -z "$ALLEYCAT_MAIN_SHA" ]; then
  echo "error: could not resolve dnakov/alleycat main" >&2
  exit 1
fi

KITTYLITTER_ALLEYCAT_SHA="$(
  git ls-remote "https://github.com/${KITTYLITTER_ALLEYCAT_REPO}.git" \
    "refs/heads/${KITTYLITTER_ALLEYCAT_REF}" \
    | awk '{ print $1; exit }'
)"
if [ -z "$KITTYLITTER_ALLEYCAT_SHA" ]; then
  echo "error: could not resolve ${KITTYLITTER_ALLEYCAT_REPO} ${KITTYLITTER_ALLEYCAT_REF}" >&2
  exit 1
fi

update_shared() {
  echo "==> Resolving shared Rust Alleycat deps to dnakov/alleycat main ($ALLEYCAT_MAIN_SHA)..."
  for package in \
    alleycat-bridge-core \
    alleycat-pi-bridge \
    alleycat-claude-bridge \
    alleycat-opencode-bridge
  do
    cargo update \
      --quiet \
      --manifest-path "$REPO_DIR/shared/rust-bridge/Cargo.toml" \
      -p "$package" \
      --precise "$ALLEYCAT_MAIN_SHA"
  done
}

update_kittylitter() {
  echo "==> Resolving kittylitter Alleycat dep to ${KITTYLITTER_ALLEYCAT_REPO} ${KITTYLITTER_ALLEYCAT_REF} ($KITTYLITTER_ALLEYCAT_SHA)..."
  cargo update \
    --quiet \
    --manifest-path "$REPO_DIR/services/kittylitter/Cargo.toml" \
    -p alleycat \
    --precise "$KITTYLITTER_ALLEYCAT_SHA"
}

case "$MODE" in
  all)
    update_shared
    update_kittylitter
    ;;
  shared)
    update_shared
    ;;
  kittylitter)
    update_kittylitter
    ;;
esac
