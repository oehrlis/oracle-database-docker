#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: generate_oracle_package_names.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2025.08.15
# Revision...: 2025.08.15 (SCRIPT_BASE default + multi-version support)
# Purpose....: Generate oracle_package_names_<arch>_<RU> files from
#              AutoUpgrade patch download logs for Docker build repository.
# Notes......:
#   - Parses AutoUpgrade patch logs (*.txt) to extract package ZIP names and
#     map them into variable assignments:
#       DB_BASE_PKG, DB_PATCH_PKG, DB_OJVM_PKG, DB_OPATCH_PKG,
#       DB_JDKPATCH_PKG, DB_PERLPATCH_PKG, DB_ONEOFF_PKGS
#   - Creates one package list file per architecture (amd64, arm64).
#   - Generic patches are included in both architecture lists (into ONEOFF).
#   - Defaults (runnable from anywhere):
#       SCRIPT_DIR  = directory of this script
#       SCRIPT_BASE = parent of SCRIPT_DIR
#       PRODUCT_DIR = 19c (can be changed with -p)
#       SOFTWARE_DIR= ${SCRIPT_BASE}/${PRODUCT_DIR}/software
#   - Use --base-amd64 and --base-arm64 to override base media filenames.
#   - Use --force to overwrite existing package list files.
#   - RU version is auto-detected unless specified with -r.
# License....: Apache License Version 2.0, January 2004
#              http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
# See git revision history for more information on changes/updates
# ------------------------------------------------------------------------------

# - Default Values -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_BASE="$(dirname "${SCRIPT_DIR}")"
PRODUCT_DIR="19c"                                  # can be changed via -p
SOFTWARE_DIR="${SCRIPT_BASE}/${PRODUCT_DIR}/software"

# Base media defaults (can be overridden by env or flags)
BASE_PACKAGE_AMD64="${BASE_PACKAGE_AMD64:-LINUX.X64_193000_db_home.zip}"
BASE_PACKAGE_ARM64="${BASE_PACKAGE_ARM64:-LINUX.ARM64_190000_db_home.zip}"

# Other defaults
INPUT_FILE=""              # will auto-detect if empty
RU_VERSION=""              # e.g. 19.27.0.0 ; parsed if empty
FORCE=0

# - Functions -----------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage:
  generate_oracle_package_names.sh [options] [INPUT_FILE]

Options:
  -p <product>   Product folder under SCRIPT_BASE (default: 19c). Examples:
                 19c, 23, 23ai
  -o <dir>       Software directory (default: SCRIPT_BASE/<product>/software)
  -r <ru>        RU version token for output filenames (e.g., 19.27.0.0).
                 If omitted, parsed from input.
  --base-amd64 <zip>
                 Base media filename for AMD64
                 (default: LINUX.X64_193000_db_home.zip)
  --base-arm64 <zip>
                 Base media filename for ARM64
                 (default: LINUX.ARM64_190000_db_home.zip)
  --force        Overwrite existing oracle_package_names_* files.
  -h|--help      Show this help.

Arguments:
  INPUT_FILE     AutoUpgrade patch download text file. If omitted, the newest
                 'autoupgrade*.txt' in the software directory is used.

Output:
  oracle_package_names_arm64_<RU>
  oracle_package_names_amd64_<RU>
  containing variable assignments needed by Docker build scripts.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*" >&2; }
warn() { echo "WARN: $*" >&2; }

find_newest_log() {
  local f
  f="$(ls -1t "${SOFTWARE_DIR}"/autoupgrade*.txt 2>/dev/null | head -n1)"
  echo "${f}"
}

# Parse RU from "DATABASE RELEASE UPDATE X.Y.Z.W.Q" (drop last component)
parse_ru_version() {
  awk '
    BEGIN{ru=""}
    /DATABASE RELEASE UPDATE/ {
      for (i=1;i<=NF;i++) {
        if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$/) {
          ru=$i
          gsub(/\.[0-9]+$/,"",ru)
          print ru
          exit
        }
      }
    }
  ' "${1}"
}

reset_arch_vars() {
  # ARM64
  DB_PATCH_PKG_ARM64=""
  DB_OJVM_PKG_ARM64=""
  DB_OPATCH_PKG_ARM64=""
  DB_JDKPATCH_PKG_ARM64=""
  DB_PERLPATCH_PKG_ARM64=""
  DB_ONEOFF_PKGS_ARM64=""
  # AMD64
  DB_PATCH_PKG_AMD64=""
  DB_OJVM_PKG_AMD64=""
  DB_OPATCH_PKG_AMD64=""
  DB_JDKPATCH_PKG_AMD64=""
  DB_PERLPATCH_PKG_AMD64=""
  DB_ONEOFF_PKGS_AMD64=""
}

append_oneoff() {
  local current="$1"
  local item="$2"
  if [[ -z "$item" ]]; then
    echo "$current"; return
  fi
  if [[ " $current " == *" $item "* ]]; then
    echo "$current"
  else
    [[ -z "$current" ]] && echo "$item" || echo "$current $item"
  fi
}

assign_for_arch() {
  local arch="$1" type="$2" file="$3"
  case "$arch" in
    ARM64)
      case "$type" in
        DATABASE_RELEASE_UPDATE)
          [[ -z "$DB_PATCH_PKG_ARM64" ]] && DB_PATCH_PKG_ARM64="$file" \
            || DB_ONEOFF_PKGS_ARM64="$(append_oneoff "$DB_ONEOFF_PKGS_ARM64" "$file")"
          ;;
        OJVM_RELEASE_UPDATE)
          [[ -z "$DB_OJVM_PKG_ARM64" ]] && DB_OJVM_PKG_ARM64="$file" \
            || DB_ONEOFF_PKGS_ARM64="$(append_oneoff "$DB_ONEOFF_PKGS_ARM64" "$file")"
          ;;
        OPATCH)
          [[ -z "$DB_OPATCH_PKG_ARM64" ]] && DB_OPATCH_PKG_ARM64="$file" \
            || DB_ONEOFF_PKGS_ARM64="$(append_oneoff "$DB_ONEOFF_PKGS_ARM64" "$file")"
          ;;
        JDK_BUNDLE_PATCH)
          [[ -z "$DB_JDKPATCH_PKG_ARM64" ]] && DB_JDKPATCH_PKG_ARM64="$file" \
            || DB_ONEOFF_PKGS_ARM64="$(append_oneoff "$DB_ONEOFF_PKGS_ARM64" "$file")"
          ;;
        PERL_BUNDLE_PATCH)
          [[ -z "$DB_PERLPATCH_PKG_ARM64" ]] && DB_PERLPATCH_PKG_ARM64="$file" \
            || DB_ONEOFF_PKGS_ARM64="$(append_oneoff "$DB_ONEOFF_PKGS_ARM64" "$file")"
          ;;
        *)
          DB_ONEOFF_PKGS_ARM64="$(append_oneoff "$DB_ONEOFF_PKGS_ARM64" "$file")"
          ;;
      esac
      ;;
    AMD64)
      case "$type" in
        DATABASE_RELEASE_UPDATE)
          [[ -z "$DB_PATCH_PKG_AMD64" ]] && DB_PATCH_PKG_AMD64="$file" \
            || DB_ONEOFF_PKGS_AMD64="$(append_oneoff "$DB_ONEOFF_PKGS_AMD64" "$file")"
          ;;
        OJVM_RELEASE_UPDATE)
          [[ -z "$DB_OJVM_PKG_AMD64" ]] && DB_OJVM_PKG_AMD64="$file" \
            || DB_ONEOFF_PKGS_AMD64="$(append_oneoff "$DB_ONEOFF_PKGS_AMD64" "$file")"
          ;;
        OPATCH)
          [[ -z "$DB_OPATCH_PKG_AMD64" ]] && DB_OPATCH_PKG_AMD64="$file" \
            || DB_ONEOFF_PKGS_AMD64="$(append_oneoff "$DB_ONEOFF_PKGS_AMD64" "$file")"
          ;;
        JDK_BUNDLE_PATCH)
          [[ -z "$DB_JDKPATCH_PKG_AMD64" ]] && DB_JDKPATCH_PKG_AMD64="$file" \
            || DB_ONEOFF_PKGS_AMD64="$(append_oneoff "$DB_ONEOFF_PKGS_AMD64" "$file")"
          ;;
        PERL_BUNDLE_PATCH)
          [[ -z "$DB_PERLPATCH_PKG_AMD64" ]] && DB_PERLPATCH_PKG_AMD64="$file" \
            || DB_ONEOFF_PKGS_AMD64="$(append_oneoff "$DB_ONEOFF_PKGS_AMD64" "$file")"
          ;;
        *)
          DB_ONEOFF_PKGS_AMD64="$(append_oneoff "$DB_ONEOFF_PKGS_AMD64" "$file")"
          ;;
      esac
      ;;
  esac
}

# NEW: robust, case-insensitive type detection for ANY non-File line
normalize_type() {
  local line="$1"
  shopt -s nocasematch
  if [[ "$line" == *"DATABASE RELEASE UPDATE"* ]]; then
    echo "DATABASE_RELEASE_UPDATE"
  elif [[ "$line" == *"OJVM RELEASE UPDATE"* ]]; then
    echo "OJVM_RELEASE_UPDATE"
  elif [[ "$line" == *"OPATCH"* || "$line" == *"OPatch"* ]]; then
    echo "OPATCH"
  elif [[ "$line" == *"JDK BUNDLE PATCH"* ]]; then
    echo "JDK_BUNDLE_PATCH"
  elif [[ "$line" == *"PERL BUNDLE PATCH"* ]]; then
    echo "PERL_BUNDLE_PATCH"
  elif [[ "$line" == *"PATCH"* ]]; then
    echo "OTHER_PATCH"
  else
    echo "UNKNOWN"
  fi
  shopt -u nocasematch
}

collect_packages_structured() {
  local infile="$1"
  local line file current_type t

  reset_arch_vars
  current_type="UNKNOWN"

  while IFS= read -r line; do
    # update current_type on any descriptive line (not the File: line)
    if [[ "$line" != *"File:"* ]]; then
      t="$(normalize_type "$line")"
      if [[ "$t" != "UNKNOWN" ]]; then
        current_type="$t"
        continue
      fi
    fi

    # File lines
    if [[ "$line" == *"File:"*" - LOCATED"* ]]; then
      file="${line#*File: }"
      file="${file%% - LOCATED*}"
      file="$(echo "$file" | tr -d '\r' | sed 's/[[:space:]]\+$//')"

      if [[ "$file" == *"Linux-ARM-64.zip" ]]; then
        assign_for_arch "ARM64" "$current_type" "$file"
      elif [[ "$file" == *"Linux-x86-64.zip" ]]; then
        assign_for_arch "AMD64" "$current_type" "$file"
      elif [[ "$file" == *"Generic.zip" ]]; then
        assign_for_arch "ARM64" "$current_type" "$file"
        assign_for_arch "AMD64" "$current_type" "$file"
      fi
    fi
  done < "${infile}"
}

# Emit variable assignments
write_list() {
  local outfile="$1"
  local basepkg="$2"
  local arch="$3"

  local PATCH OJVM OPATCH JDK PERL ONEOFF

  if [[ "$arch" == "ARM64" ]]; then
    PATCH="$DB_PATCH_PKG_ARM64"
    OJVM="$DB_OJVM_PKG_ARM64"
    OPATCH="$DB_OPATCH_PKG_ARM64"
    JDK="$DB_JDKPATCH_PKG_ARM64"
    PERL="$DB_PERLPATCH_PKG_ARM64"
    ONEOFF="$DB_ONEOFF_PKGS_ARM64"
  else
    PATCH="$DB_PATCH_PKG_AMD64"
    OJVM="$DB_OJVM_PKG_AMD64"
    OPATCH="$DB_OPATCH_PKG_AMD64"
    JDK="$DB_JDKPATCH_PKG_AMD64"
    PERL="$DB_PERLPATCH_PKG_AMD64"
    ONEOFF="$DB_ONEOFF_PKGS_AMD64"
  fi

  {
    echo "DB_BASE_PKG=\"${basepkg}\""
    echo "DB_PATCH_PKG=\"${PATCH}\""
    echo "DB_OJVM_PKG=\"${OJVM}\""
    echo "DB_OPATCH_PKG=\"${OPATCH}\""
    echo "DB_JDKPATCH_PKG=\"${JDK}\""
    echo "DB_PERLPATCH_PKG=\"${PERL}\""
    echo "DB_ONEOFF_PKGS=\"${ONEOFF}\""
  } > "${outfile}.tmp" || return 1

  mv "${outfile}.tmp" "${outfile}"
}

# - Parse Parameters -----------------------------------------------------------
ARGS=()
while (( "$#" )); do
  case "$1" in
    -p) PRODUCT_DIR="$2"; shift 2 ;;
    -o) SOFTWARE_DIR="$2"; shift 2 ;;
    -r) RU_VERSION="$2"; shift 2 ;;
    --base-amd64) BASE_PACKAGE_AMD64="$2"; shift 2 ;;
    --base-arm64) BASE_PACKAGE_ARM64="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "Unknown option: $1 (use -h for help)" ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
  INPUT_FILE="${ARGS[0]}"
fi

# - Resolve Paths --------------------------------------------------------------
SOFTWARE_DIR="${SOFTWARE_DIR%/}"
[[ -d "${SOFTWARE_DIR}" ]] || die "Software directory not found: ${SOFTWARE_DIR}"

if [[ -z "${INPUT_FILE}" ]]; then
  INPUT_FILE="$(find_newest_log)"
  [[ -n "${INPUT_FILE}" ]] || die "No INPUT_FILE and no autoupgrade*.txt in ${SOFTWARE_DIR}"
fi
[[ -r "${INPUT_FILE}" ]] || die "Cannot read INPUT_FILE: ${INPUT_FILE}"

info "SCRIPT_BASE       : ${SCRIPT_BASE}"
info "PRODUCT_DIR       : ${PRODUCT_DIR}"
info "SOFTWARE_DIR      : ${SOFTWARE_DIR}"
info "INPUT_FILE        : ${INPUT_FILE}"
info "BASE_PACKAGE_AMD64: ${BASE_PACKAGE_AMD64}"
info "BASE_PACKAGE_ARM64: ${BASE_PACKAGE_ARM64}"

# - Determine RU Version -------------------------------------------------------
if [[ -z "${RU_VERSION}" ]]; then
  RU_VERSION="$(parse_ru_version "${INPUT_FILE}")"
  [[ -n "${RU_VERSION}" ]] || die "Failed to parse RU version from ${INPUT_FILE}"
fi
info "RU_VERSION        : ${RU_VERSION}"

OUT_ARM64="${SOFTWARE_DIR}/oracle_package_names_arm64_${RU_VERSION}"
OUT_AMD64="${SOFTWARE_DIR}/oracle_package_names_amd64_${RU_VERSION}"

if [[ ${FORCE} -eq 0 ]]; then
  if [[ -e "${OUT_ARM64}" || -e "${OUT_AMD64}" ]]; then
    die "Output files exist. Use --force to overwrite:
  ${OUT_ARM64}
  ${OUT_AMD64}"
  fi
fi

# - Collect and Write ----------------------------------------------------------
collect_packages_structured "${INPUT_FILE}"

write_list "${OUT_ARM64}" "${BASE_PACKAGE_ARM64}" "ARM64" \
  || die "Failed writing ${OUT_ARM64}"
write_list "${OUT_AMD64}" "${BASE_PACKAGE_AMD64}" "AMD64" \
  || die "Failed writing ${OUT_AMD64}"

info "Created:"
echo "  ${OUT_ARM64}"
echo "  ${OUT_AMD64}"
# ------------------------------------------------------------------------------
