#!/usr/bin/env bash
set -euo pipefail

ARTI_VERSION="${ARTI_VERSION:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/Arti"

usage() {
  echo "Usage: $0 [--version <crate-version>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      ARTI_VERSION="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if ! command -v cargo >/dev/null 2>&1; then
  echo "Cargo is required to install Arti. Install Rust from https://rustup.rs/ first." >&2
  exit 1
fi

mkdir -p "${VENDOR_DIR}"

if [[ -n "${ARTI_VERSION}" ]]; then
  cargo install arti --locked --root "${VENDOR_DIR}" --version "${ARTI_VERSION}"
else
  cargo install arti --locked --root "${VENDOR_DIR}"
fi

if [[ ! -x "${VENDOR_DIR}/bin/arti" ]]; then
  echo "Arti install finished, but ${VENDOR_DIR}/bin/arti was not created." >&2
  exit 1
fi

"${VENDOR_DIR}/bin/arti" --version
echo "Arti is ready at ${VENDOR_DIR}/bin/arti"
