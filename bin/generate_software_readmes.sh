#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: generate_software_readmes.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2025.08.15
# Revision...: 2025.08.15 (SCRIPT_BASE default + multi-version support)
# Purpose....: Generate README.md documentation for Oracle Database software
#              directories in the Docker build repository.
# Notes......:
#   - Creates README.md files for:
#       * software root folder
#       * platform folders (amd64, arm64)
#       * base subfolders under each platform
#       * generic folder
#       * each RU_* folder under amd64 and arm64
#   - Each RU README includes:
#       * Linked consolidated package list file
#       * Inventory of contained patch ZIPs with size and optional SHA-256
#   - Defaults (runnable from anywhere):
#       SCRIPT_DIR  = directory of this script
#       SCRIPT_BASE = parent of SCRIPT_DIR
#       SOFTWARE_DIR= ${SCRIPT_BASE}/19c/software
#   - Use --versions 19c,23ai to run for multiple versions under SCRIPT_BASE
#   - Use --force     to overwrite existing README.md files
#   - Use --no-hash   to skip SHA-256 checksum calculation
# License....: Apache License Version 2.0, January 2004
#              http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
# See git revision history for more information on changes/updates
# ------------------------------------------------------------------------------

set -euo pipefail

# - Default Values -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Directory of this script
SCRIPT_BASE="$(dirname "${SCRIPT_DIR}")"                    # Base directory of the project
SOFTWARE_DIR="${SCRIPT_BASE}/19c/software"

FORCE=0
DO_HASH=1
VERSIONS=""   # comma-separated list like: 19c,23ai

# Usage / Options --------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: generate_software_readmes.sh [--force] [--no-hash] [--versions LIST] [SOFTWARE_DIR]

Default SOFTWARE_DIR:
  SCRIPT_BASE/19c/software

Options:
  --force         Overwrite existing README.md files.
  --no-hash       Do not compute SHA-256 checksums (faster).
  --versions LIST Comma-separated versions under SCRIPT_BASE to process,
                  e.g. "19c,23ai". Each version must have <version>/software.

Examples:
  ./bin/generate_software_readmes.sh
  ./bin/generate_software_readmes.sh --force
  ./bin/generate_software_readmes.sh --no-hash
  ./bin/generate_software_readmes.sh --versions 19c,23ai
  ./bin/generate_software_readmes.sh --force /custom/path/to/software
EOF
}

# Parse args -------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1; shift;;
    --no-hash) DO_HASH=0; shift;;
    --versions)
      [[ $# -ge 2 ]] || { echo "ERROR: --versions requires a value" >&2; exit 1; }
      VERSIONS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *)
      # Positional override for SOFTWARE_DIR
      SOFTWARE_DIR="$1"; shift;;
  esac
done

# Helpers ----------------------------------------------------------------------
md() { printf "%s\n" "$*"; }

exists_or_force() {
  local path="$1"
  [[ $FORCE -eq 1 || ! -f "$path" ]]
}

fsize() { du -h "$1" | awk '{print $1}'; }

sha256() {
  local f="$1"
  [[ $DO_HASH -eq 0 ]] && { echo ""; return; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    echo ""
  fi
}

write_file() {
  local path="$1"; shift
  if exists_or_force "$path"; then
    mkdir -p "$(dirname "$path")"
    printf "%s" "$*" > "$path"
    echo "Wrote: $path"
  else
    echo "SKIP (exists): $path"
  fi
}

# Content generators -----------------------------------------------------------
root_readme() {
  local version="$1"  # e.g., 19c or 23ai
  md "# Oracle Database ${version} Software Packages"
  md
  md "This tree contains platform-specific and generic software for building Oracle Database ${version} Docker images."
  md
  md "## Layout"
  md
  md "- \`amd64/\` - AMD64 platform folders, with \`RU_*\` subfolders and \`base/\`"
  md "- \`arm64/\` - ARM64 platform folders, with \`RU_*\` subfolders and \`base/\`"
  md "- \`generic/\` - Architecture-independent packages (e.g., DBRU generic zips)"
  md
  md "Consolidated package lists live at the root as:"
  md "- \`oracle_package_names_amd64_<RU>\`"
  md "- \`oracle_package_names_arm64_<RU>\`"
  md
}

arch_readme() {
  local arch="$1"
  md "# ${arch^^} Packages"
  md
  md "This folder contains Release Update (RU) subfolders and a \`base/\` folder for ${arch^^} builds."
  md
}

base_readme() {
  local arch="$1"
  md "# ${arch^^} Base Packages"
  md
  md "Place the base Oracle Database Home ZIP(s) for ${arch^^} here (e.g., \`LINUX.${arch^^}_1919000_db_home.zip\`)."
  md
}

generic_readme() {
  md "# Generic Packages"
  md
  md "Architecture-independent patches and utilities (e.g. DBRU generic components)."
  md
}

ru_readme() {
  local arch="$1"       # amd64 or arm64
  local ru_dir="$2"     # path to RU_* folder
  local version="$3"    # 19c / 23ai (for titles)
  local ru_base; ru_base=$(basename "$ru_dir")    # RU_19.27.0.0
  local ru_ver="${ru_base#RU_}"                   # 19.27.0.0
  local pkglist_rel="../../oracle_package_names_${arch}_${ru_ver}"

  md "# Oracle ${version} ${ru_base} (${arch^^})"
  md
  md "This folder contains architecture-specific patches needed for **${ru_base}** on **${arch^^}**."
  md
  md "## Consolidated package list"
  md
  md "- \`${pkglist_rel}\`"
  md
  md "## Files in this folder"
  md
  shopt -s nullglob
  local files=("$ru_dir"/*)
  if [[ ${#files[@]} -eq 0 ]]; then
    md "_(No files found in this RU directory.)_"
    md
    return
  fi
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    local bn size sum
    bn=$(basename "$f")
    size=$(fsize "$f")
    sum=$(sha256 "$f")
    if [[ -n "$sum" ]]; then
      md "- \`$bn\` — $size — SHA256: \`$sum\`"
    else
      md "- \`$bn\` — $size"
    fi
  done
  md
}

list_and_write_ru_readmes() {
  local arch="$1"
  local swdir="$2"
  local version="$3"
  local arch_dir="${swdir}/${arch}"
  [[ -d "$arch_dir" ]] || return 0
  find "$arch_dir" -maxdepth 1 -type d -name 'RU_*' | sort | while read -r ru; do
    local readme="$ru/README.md"
    write_file "$readme" "$(ru_readme "$arch" "$ru" "$version")"
  done
}

# Processor for a single software dir -----------------------------------------
process_one_software_dir() {
  local swdir="$1"

  if [[ ! -d "$swdir" ]]; then
    echo "WARN: SOFTWARE_DIR not found, skipping: $swdir" >&2
    return 0
  fi

  # Version is the parent folder name of /software (e.g., 19c, 23ai)
  local version
  version="$(basename "$(dirname "$swdir")")"

  # Ensure core folders exist
  mkdir -p "$swdir"/{amd64,arm64,generic}
  mkdir -p "$swdir/amd64/base" "$swdir/arm64/base"

  # Root README
  write_file "$swdir/README.md" "$(root_readme "$version")"

  # Arch READMEs
  write_file "$swdir/amd64/README.md" "$(arch_readme amd64)"
  write_file "$swdir/arm64/README.md" "$(arch_readme arm64)"

  # Base READMEs
  write_file "$swdir/amd64/base/README.md" "$(base_readme amd64)"
  write_file "$swdir/arm64/base/README.md" "$(base_readme arm64)"

  # Generic README
  write_file "$swdir/generic/README.md" "$(generic_readme)"

  # Per-RU inventories
  list_and_write_ru_readmes "amd64" "$swdir" "$version"
  list_and_write_ru_readmes "arm64" "$swdir" "$version"

  echo "Done: ${swdir}"
}

# Main -------------------------------------------------------------------------
if [[ -n "$VERSIONS" ]]; then
  # Run for each version under SCRIPT_BASE
  IFS=',' read -r -a vers <<< "$VERSIONS"
  for v in "${vers[@]}"; do
    sw="${SCRIPT_BASE}/${v}/software"
    process_one_software_dir "$sw"
  done
else
  # Single run (default SOFTWARE_DIR or user override)
  process_one_software_dir "$SOFTWARE_DIR"
fi
# - EOF ------------------------------------------------------------------------