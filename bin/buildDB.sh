#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: buildDB.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2025.08.11
# Revision...: 2025.08.11 (Initial consolidated draft for new repo layout)
# Purpose....: Build Oracle Database Docker images with minimal build context
# Notes......:
#   - Stages only required ZIPs into a local .swstage folder before build
#   - Generates a .dockerignore that whitelists only staged files + package list
#   - Supports both package list naming schemes:
#       * 19c/oracle_package_names_${TARGETARCH}_${RU}
#       * 19c/${TARGETARCH}/oracle_package_names_${RU}  (fallback)
#   - Can build Stage 2 (builder) or the final image
# License....: Apache License Version 2.0, January 2004
#              http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
# Modified...:
# See git revision history for more information on changes/updates
# ------------------------------------------------------------------------------

set -euo pipefail

# --- Defaults / Customization -----------------------------------------------
SCRIPT_NAME=$(basename "$0")
REPO_ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd -P)"

DB_VER_DIR="${DB_VER_DIR:-19c}"                 # version directory in repo (currently 19c)
DOCKERFILE_REL="${DOCKERFILE_REL:-docker/Dockerfile.base}"
DOCKERFILE="${REPO_ROOT}/${DB_VER_DIR}/${DOCKERFILE_REL}"

TARGETARCH="${TARGETARCH:-arm64}"               # arm64|amd64
ORACLE_RELEASE="${ORACLE_RELEASE:-19.0.0.0}"
ORACLE_RELEASE_UPDATE="${ORACLE_RELEASE_UPDATE:-19.27.0.0}"

# External software source root (optional). If empty, use repo-local 19c/software
SOFTWARE_SOURCE="${SOFTWARE_SOURCE:-}"

# Image tag
IMAGE_TAG="${IMAGE_TAG:-oracle-db:${ORACLE_RELEASE_UPDATE}-${TARGETARCH}}"

# Build target: "" (final) or "builder" for Stage 2
BUILD_TARGET="${BUILD_TARGET:-}"

# Use docker buildx? leave empty for plain docker
USE_BUILDX="${USE_BUILDX:-}"

# Keep staging and .dockerignore after build (for debug)
KEEP_STAGE="${KEEP_STAGE:-0}"

VERBOSE=0
DRY_RUN=0
# ----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]
Build Oracle Database Docker images with minimal build context (staged ZIPs).

Options:
  -a <arch>           Target arch (arm64|amd64). Default: ${TARGETARCH}
  -r <RU>             Release Update, e.g. 19.27.0.0. Default: ${ORACLE_RELEASE_UPDATE}
  -R <release>        Oracle release (e.g., 19.0.0.0). Default: ${ORACLE_RELEASE}
  -S <path>           External software source root (contains <arch>/base and <arch>/RU_<RU>)
  -d <dockerfile>     Dockerfile path relative to \$DB_VER_DIR. Default: ${DOCKERFILE_REL}
  -t <target>         Build target (e.g. 'builder' to stop after Stage 2). Default: final
  -i <image:tag>      Image tag. Default: ${IMAGE_TAG}
  -k                  Keep staging (.swstage) and .dockerignore after build
  -x                  Use docker buildx (otherwise plain docker build)
  -n                  Dry run (print actions only)
  -v                  Verbose

Examples:
  ${SCRIPT_NAME} -a arm64 -r 19.27.0.0 -S /Volumes/EXTERNAL/oracle_pkgs/19c/software -t builder
  TARGETARCH=amd64 ORACLE_RELEASE_UPDATE=19.27.0.0 ${SCRIPT_NAME}
EOF
  exit 1
}

log()  { printf "INFO: %s\n" "$*"; }
warn() { printf "WARN: %s\n" "$*\n" >&2; }
err()  { printf "ERROR: %s\n" "$*\n" >&2; exit 1; }

# --- Parse args --------------------------------------------------------------
while getopts ":a:r:R:S:d:t:i:kvxnvh" opt; do
  case "$opt" in
    a) TARGETARCH="$OPTARG" ;;
    r) ORACLE_RELEASE_UPDATE="$OPTARG" ;;
    R) ORACLE_RELEASE="$OPTARG" ;;
    S) SOFTWARE_SOURCE="$OPTARG" ;;
    d) DOCKERFILE_REL="$OPTARG"; DOCKERFILE="${REPO_ROOT}/${DB_VER_DIR}/${DOCKERFILE_REL}" ;;
    t) BUILD_TARGET="$OPTARG" ;;
    i) IMAGE_TAG="$OPTARG" ;;
    k) KEEP_STAGE=1 ;;
    x) USE_BUILDX=1 ;;
    n) DRY_RUN=1 ;;
    v) VERBOSE=$((VERBOSE+1)) ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND-1))

[[ $VERBOSE -gt 0 ]] && set -x
[[ -f "${DOCKERFILE}" ]] || err "Dockerfile not found: ${DOCKERFILE}"

# --- Resolve package list file (supports both layouts) -----------------------
PKG_FILE_NEW="${REPO_ROOT}/${DB_VER_DIR}/software/oracle_package_names_${TARGETARCH}_${ORACLE_RELEASE_UPDATE}"
PKG_FILE_OLD="${REPO_ROOT}/${DB_VER_DIR}/software/${TARGETARCH}/oracle_package_names_${ORACLE_RELEASE_UPDATE}"

if   [[ -f "${PKG_FILE_NEW}" ]]; then PKG_FILE="${PKG_FILE_NEW}"
elif [[ -f "${PKG_FILE_OLD}" ]]; then PKG_FILE="${PKG_FILE_OLD}"
else err "Package list not found: ${PKG_FILE_NEW} or ${PKG_FILE_OLD}"
fi

log "Using package list: ${PKG_FILE}"

# --- Read package variables --------------------------------------------------
# shellcheck disable=SC1090
source "${PKG_FILE}"

# Collect PKG vars (non-empty)
PKGS=()
while IFS='=' read -r k _; do
  if [[ "$k" =~ _PKG$ ]] && [[ -n "${!k:-}" ]]; then
    PKGS+=("${!k}")
  fi
done < <(grep -E '^[A-Z0-9_]+=' "${PKG_FILE}" || true)

# One-offs
if [[ -n "${DB_ONEOFF_PKGS:-}" ]]; then
  for p in ${DB_ONEOFF_PKGS}; do PKGS+=("$p"); done
fi

# --- Prepare staging tree ----------------------------------------------------
STAGE_ROOT="${REPO_ROOT}/${DB_VER_DIR}/software"          # <— note: software/, not .swstage
STAGE_BASE="${STAGE_ROOT}/${TARGETARCH}/base"
STAGE_RU="${STAGE_ROOT}/${TARGETARCH}/RU_${ORACLE_RELEASE_UPDATE}"
STAGE_GENERIC="${STAGE_ROOT}/generic"

rm -rf "${STAGE_BASE}" "${STAGE_RU}"
mkdir -p "${STAGE_BASE}" "${STAGE_RU}" "${STAGE_GENERIC}"

# Determine sources
if [[ -n "${SOFTWARE_SOURCE}" ]]; then
  SRC_BASE="${SOFTWARE_SOURCE}/${TARGETARCH}/base"
  SRC_RU="${SOFTWARE_SOURCE}/${TARGETARCH}/RU_${ORACLE_RELEASE_UPDATE}"
else
  SRC_BASE="${REPO_ROOT}/${DB_VER_DIR}/software/${TARGETARCH}/base"
  SRC_RU="${REPO_ROOT}/${DB_VER_DIR}/software/${TARGETARCH}/RU_${ORACLE_RELEASE_UPDATE}"
fi

[[ -d "${SRC_BASE}" ]] || warn "Base source dir missing: ${SRC_BASE}"
[[ -d "${SRC_RU}"   ]] || warn "RU source dir missing:   ${SRC_RU}"

copy_one() {
  local src="$1" dst="$2"
  [[ $DRY_RUN -eq 1 ]] && { echo "DRY RUN: cp -a \"$src\" \"$dst/\""; return; }
  cp -a "$src" "$dst/"
}

# Stage only the required files
log "Staging selected packages to ${STAGE_ROOT}"
for z in "${PKGS[@]}"; do
  if   [[ -f "${SRC_BASE}/${z}" ]]; then copy_one "${SRC_BASE}/${z}" "${STAGE_BASE}"
  elif [[ -f "${SRC_RU}/${z}"   ]]; then copy_one "${SRC_RU}/${z}"   "${STAGE_RU}"
  else warn "Package not found in base/RU sources: ${z}"
  fi
done

# --- Generate .dockerignore for this build ----------------------------------
DOCKERIGNORE_PATH="${REPO_ROOT}/${DB_VER_DIR}/.dockerignore"
DOCKERIGNORE_BAK="${DOCKERIGNORE_PATH}.bak"

[[ -f "${DOCKERIGNORE_PATH}" ]] && mv "${DOCKERIGNORE_PATH}" "${DOCKERIGNORE_BAK}"

# Calculate relative path of staging dir from $DB_VER_DIR
REL_STAGE="${STAGE_ROOT#${REPO_ROOT}/${DB_VER_DIR}/}"

cat > "${DOCKERIGNORE_PATH}" <<EOF
# Auto-generated by ${SCRIPT_NAME}
# Ignore everything heavy by default
software/**

# Allow only staged content
!${REL_STAGE}/**

# Allow the package list (support both naming schemes)
$(basename "${PKG_FILE_NEW}")*
$(basename "${TARGETARCH}")/$(basename "${PKG_FILE_OLD}")*

# Usual ignores
.git/
*.log
*.tar
*.zip
.DS_Store
EOF

# --- Build command -----------------------------------------------------------
CTX_DIR="${REPO_ROOT}/${DB_VER_DIR}"

BUILDER_BIN="docker"
[[ -n "${USE_BUILDX}" ]] && BUILDER_BIN="docker buildx"

CMD_ARGS=(
  build
  --file "${DOCKERFILE_REL}"
  --build-arg "TARGETARCH=${TARGETARCH}"
  --build-arg "ORACLE_RELEASE=${ORACLE_RELEASE}"
  --build-arg "ORACLE_RELEASE_UPDATE=${ORACLE_RELEASE_UPDATE}"
  --tag "${IMAGE_TAG}"
)

# Platform: single-arch chosen by TARGETARCH (linux/<arch>)
CMD_ARGS+=( --platform "linux/${TARGETARCH}" )

# Stage 2 test?
[[ -n "${BUILD_TARGET}" ]] && CMD_ARGS+=( --target "${BUILD_TARGET}" )

log "Building image: ${IMAGE_TAG}"
log "Dockerfile:     ${DOCKERFILE}"
log "Context:        ${CTX_DIR}"
log "Target:         ${BUILD_TARGET:-final}"
log "Platform:       linux/${TARGETARCH}"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN: (cd \"${CTX_DIR}\" && ${BUILDER_BIN} ${CMD_ARGS[*]} .)"
else
  ( cd "${CTX_DIR}" && ${BUILDER_BIN} "${CMD_ARGS[@]}" . )
fi

# --- Cleanup -----------------------------------------------------------------
if [[ "${KEEP_STAGE}" -eq 0 ]]; then
  rm -rf "${STAGE_ROOT}"
  if [[ -f "${DOCKERIGNORE_BAK}" ]]; then
    mv "${DOCKERIGNORE_BAK}" "${DOCKERIGNORE_PATH}"
  else
    rm -f "${DOCKERIGNORE_PATH}"
  fi
  log "Cleaned staging and .dockerignore"
else
  log "Kept staging at: ${STAGE_ROOT}"
  log "Kept .dockerignore at: ${DOCKERIGNORE_PATH}"
fi

log "Build complete: ${IMAGE_TAG}"
# --- EOF --------------------------------------------------------------------
