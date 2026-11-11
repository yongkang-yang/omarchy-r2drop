#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for bin/r2drop (offline, no network, no secrets).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export R2DROP_NO_NOTIFY=1
export R2DROP_NO_IPC=1

# shellcheck source=../bin/r2drop
R2DROP_LIB=1 source "${REPO_DIR}/bin/r2drop"

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${label}" >&2
    echo "  expected: $(printf '%q' "$expected")" >&2
    echo "  actual:   $(printf '%q' "$actual")" >&2
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${label} (expected success)" >&2
  fi
}

assert_false() {
  local label="$1"
  shift
  if "$@"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: ${label} (expected failure)" >&2
  else
    PASS=$((PASS + 1))
  fi
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/r2drop-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

# ---------------------------------------------------------------------------
# 1. slugify tests (matching R2.swift)
# ---------------------------------------------------------------------------
assert_eq "survey2-team-list" "$(slugify "Survey2 Team List")" "slugify basic words"
assert_eq "my-slug" "$(slugify "My Slug!")" "slugify trailing punctuation"
assert_eq "" "$(slugify "截图")" "slugify non-ASCII only becomes empty"
assert_eq "hello-world" "$(slugify "---Hello___World---")" "slugify collapses non-alnum runs and trims dashes"
assert_eq "a-1-b-2" "$(slugify "  A 1 / B 2  ")" "slugify mixed symbols"

# 60-char truncation and trailing dash trim after prefix(60)
long_input="$(printf '%59s' '' | tr ' ' 'a') bbbb"
assert_eq "$(printf '%59s' '' | tr ' ' 'a')" "$(slugify "$long_input")" "slugify trims dash at char 60 boundary"

long_exact="$(printf '%70s' '' | tr ' ' 'x')"
slug_70=$(slugify "$long_exact")
assert_eq 60 "${#slug_70}" "slugify caps at 60 characters"

# ---------------------------------------------------------------------------
# 2. Key format tests (matching R2Tests.testKeys)
# ---------------------------------------------------------------------------
assert_eq "2026/09/survey2-team-list-a8f31c.png" \
  "$(build_key "Survey2 Team List.PNG" "" "a8f31c" "2026/09")" \
  "build_key standard filename and uppercase extension"

assert_eq "2026/09/a8f31c.jpg" \
  "$(build_key "截图.jpg" "" "a8f31c" "2026/09")" \
  "build_key empty slug uses hash only"

assert_eq "2026/09/my-slug-ff0000.png" \
  "$(build_key "x.png" "My Slug!" "ff0000" "2026/09")" \
  "build_key with custom slug"

assert_eq "2026/09/screenshot-123abc.png" \
  "$(build_key "screenshot.png" "screenshot" "123abc" "2026/09")" \
  "build_key for screenshot"

hash_sample=$(random_hash 3)
assert_true "random_hash is 6 hex chars" bash -c "[[ '$hash_sample' =~ ^[0-9a-f]{6}$ ]]"

assert_eq "image/jpeg" "$(content_type_for_ext "JPEG")" "content_type_for_ext JPEG"
assert_eq "image/svg+xml" "$(content_type_for_ext ".svg")" "content_type_for_ext .svg"
assert_true "is_image_ext HEIC" is_image_ext "/tmp/a.HEIC"
assert_false "is_image_ext pdf" is_image_ext "/tmp/a.pdf"

# ---------------------------------------------------------------------------
# 3. Output format tests (matching R2Tests.testFormats)
# ---------------------------------------------------------------------------
test_url="https://img.example.com/2026/09/a-1.png"
assert_eq "$test_url" \
  "$(format_link "url" "$test_url" "shot.png")" \
  "format_link url"

assert_eq "![](${test_url})" \
  "$(format_link "markdown" "$test_url" "shot.png")" \
  "format_link markdown"

assert_eq "<img src=\"${test_url}\">" \
  "$(format_link "html" "$test_url" "shot.png")" \
  "format_link html"

assert_eq "![team list](${test_url})" \
  "$(format_link "markdown-filename" "$test_url" "team list.png")" \
  "format_link markdown-filename with extension"

assert_eq "![team list](${test_url})" \
  "$(format_link "markdown-filename" "$test_url" "team list")" \
  "format_link markdown-filename without extension"

assert_eq "https://img.example.com/k.png" \
  "$(public_url "https://img.example.com///" "k.png")" \
  "public_url strips trailing slashes"

# ---------------------------------------------------------------------------
# 4. Config parsing & validation tests
# ---------------------------------------------------------------------------
cfg_file="${TMP_ROOT}/config.env"
pwned_file="${TMP_ROOT}/pwned"
cat > "$cfg_file" <<EOF
# Comment line
CLOUDFLARE_ACCOUNT_ID = "acct-123"
export CLOUDFLARE_R2_BUCKET='my-bucket'
CLOUDFLARE_R2_PUBLIC_URL=https://cdn.example.com/ # inline comment
R2DROP_FORMAT=html
UNTRUSTED_KEY=\$(touch "${pwned_file}")
EOF

unset CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_R2_BUCKET CLOUDFLARE_R2_PUBLIC_URL R2DROP_FORMAT
load_and_validate_config "$cfg_file"
assert_eq "acct-123" "$CLOUDFLARE_ACCOUNT_ID" "config parses double-quoted value"
assert_eq "my-bucket" "$CLOUDFLARE_R2_BUCKET" "config parses export + single-quoted value"
assert_eq "https://cdn.example.com/" "$CLOUDFLARE_R2_PUBLIC_URL" "config parses unquoted value with inline comment"
assert_eq "html" "$R2DROP_FORMAT" "config parses R2DROP_FORMAT"
assert_false "config parser never executes command substitutions" test -e "$pwned_file"

# Env var override test
CLOUDFLARE_R2_BUCKET="override-bucket"
R2DROP_FORMAT="url"
load_and_validate_config "$cfg_file"
assert_eq "override-bucket" "$CLOUDFLARE_R2_BUCKET" "env var overrides config file bucket"
assert_eq "url" "$R2DROP_FORMAT" "env var overrides config file format"

# Missing key test
bad_cfg="${TMP_ROOT}/bad_config.env"
cat > "$bad_cfg" <<EOF
CLOUDFLARE_ACCOUNT_ID="acct"
EOF
unset CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_R2_BUCKET CLOUDFLARE_R2_PUBLIC_URL R2DROP_FORMAT
err_out=$(load_and_validate_config "$bad_cfg" 2>&1 || true)
assert_true "missing config error names missing keys and file path" \
  bash -c '[[ "$1" == *"CLOUDFLARE_R2_BUCKET"* && "$1" == *"CLOUDFLARE_R2_PUBLIC_URL"* && "$1" == *"$2"* ]]' _ "$err_out" "$bad_cfg"

# ---------------------------------------------------------------------------
# 5. History trimming (200 lines) & thumbnail pruning & recent --json
# ---------------------------------------------------------------------------
export XDG_STATE_HOME="${TMP_ROOT}/state"
export XDG_CACHE_HOME="${TMP_ROOT}/cache"
hist_file=$(history_file_path)
thumbs_dir=$(thumbs_dir_path)
mkdir -p "$thumbs_dir"

for i in $(seq 1 205); do
  k=$(printf '2026/09/item-%03d.png' "$i")
  t=$(thumb_path_for_key "$k" "$thumbs_dir")
  touch "$t"
  record_history "$k" "https://img.example.com/$k" "item-$i" "2026-09-01T00:00:00Z" "$t" "$hist_file" "$thumbs_dir" 200
done

line_count=$(wc -l < "$hist_file" | tr -d ' ')
assert_eq "200" "$line_count" "history trimmed to last 200 lines"

first_kept_key=$(head -n 1 "$hist_file" | jq -r '.key')
last_kept_key=$(tail -n 1 "$hist_file" | jq -r '.key')
assert_eq "2026/09/item-006.png" "$first_kept_key" "oldest 5 entries trimmed from history"
assert_eq "2026/09/item-205.png" "$last_kept_key" "newest entry kept at end of history"

assert_false "pruned thumb 001 removed" test -e "$(thumb_path_for_key "2026/09/item-001.png" "$thumbs_dir")"
assert_false "pruned thumb 005 removed" test -e "$(thumb_path_for_key "2026/09/item-005.png" "$thumbs_dir")"
assert_true "active thumb 006 kept" test -e "$(thumb_path_for_key "2026/09/item-006.png" "$thumbs_dir")"
assert_true "active thumb 205 kept" test -e "$(thumb_path_for_key "2026/09/item-205.png" "$thumbs_dir")"

recent_json=$(cmd_recent --json 3)
recent_len=$(jq 'length' <<< "$recent_json")
recent_first=$(jq -r '.[0].key' <<< "$recent_json")
recent_third=$(jq -r '.[2].key' <<< "$recent_json")
assert_eq "3" "$recent_len" "recent --json 3 returns 3 items"
assert_eq "2026/09/item-205.png" "$recent_first" "recent --json returns newest first (index 0)"
assert_eq "2026/09/item-203.png" "$recent_third" "recent --json returns newest first (index 2)"

# ---------------------------------------------------------------------------
# 6. URI decoding, image detection, copy KEY, pick without zenity, upload rejection
# ---------------------------------------------------------------------------
assert_eq "/home/user/My Photo (1).png"   "$(uri_to_path "file:///home/user/My%20Photo%20%281%29.png")"   "uri_to_path decodes percent-encoded file URI"

sample_png="${TMP_ROOT}/sample.png"
sample_txt="${TMP_ROOT}/sample.txt"
magick -size 4x4 xc:red "$sample_png"
echo "not an image" > "$sample_txt"

assert_true "is_image_file accepts real PNG" is_image_file "$sample_png"
assert_false "is_image_file rejects plain text file" is_image_file "$sample_txt"

# Mock wl-copy in PATH to test cmd_copy offline
mock_bin="${TMP_ROOT}/bin"
mkdir -p "$mock_bin"
cat > "${mock_bin}/wl-copy" <<'MOCK'
#!/usr/bin/env bash
cat > "${TMP_CLIPBOARD_FILE}"
MOCK
chmod +x "${mock_bin}/wl-copy"
export TMP_CLIPBOARD_FILE="${TMP_ROOT}/clipboard.txt"

PATH="${mock_bin}:${PATH}" R2DROP_FORMAT="markdown-filename" cmd_copy "2026/09/item-205.png" >/dev/null
assert_eq "![item-205](https://img.example.com/2026/09/item-205.png)"   "$(cat "$TMP_CLIPBOARD_FILE")"   "cmd_copy copies formatted link for key"

# Non-image rejection via CLI
reject_err=$("${REPO_DIR}/bin/r2drop" upload "$sample_txt" 2>&1 || true)
assert_true "upload rejects non-image file"   bash -c '[[ "$1" == *"Rejected non-image file"* ]]' _ "$reject_err"

# zenity missing message when running pick without zenity on PATH
pick_err=$(PATH="/usr/bin:/bin" "${REPO_DIR}/bin/r2drop" pick 2>&1 || true)
assert_true "pick suggests omarchy pkg add zenity when missing"   bash -c '[[ "$1" == *"omarchy pkg add zenity"* ]]' _ "$pick_err"

echo "All ${PASS} assertions passed (${FAIL} failed)."
(( FAIL == 0 ))
