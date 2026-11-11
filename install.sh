#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Install r2drop CLI symlink and create initial config directory.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/r2drop"
CONFIG_FILE="${CONFIG_DIR}/config.env"

mkdir -p "$BIN_DIR"
ln -sfn "${REPO_DIR}/bin/r2drop" "${BIN_DIR}/r2drop"
echo "Linked ${BIN_DIR}/r2drop -> ${REPO_DIR}/bin/r2drop"

mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "${REPO_DIR}/config.env.example" "$CONFIG_FILE"
  echo "Created ${CONFIG_FILE} from config.env.example"
else
  echo "Kept existing ${CONFIG_FILE}"
fi

cat <<EOF

Next steps:
  1. Edit ${CONFIG_FILE} and set CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_R2_BUCKET, and CLOUDFLARE_R2_PUBLIC_URL.
  2. Provide CLOUDFLARE_R2_ACCESS_KEY_ID and CLOUDFLARE_R2_SECRET_ACCESS_KEY in your environment or via ykcred ('image-hosting').
  3. To enable the Omarchy bar widget:
       omarchy plugin add "${REPO_DIR}" --enable
     (or symlink "${REPO_DIR}" to ~/.config/omarchy/plugins/ykyan.r2drop, then run:
      omarchy-shell shell rescanPlugins && omarchy plugin enable ykyan.r2drop)
EOF
