#!/usr/bin/env bash

set -euo pipefail

log() { echo ">>> $*"; }
die() { log "$@"; exit 1; }
cd "$(dirname $0)/.."
source ./hack/lib.bash

# if generation of patches fails
restore_patches() {
    if [[ "$?" -ne 0 ]]; then
        log "Formatting failed, restoring patches/"
        git restore -- patches/
        git clean -f -- patches/
    fi
}

format_patches() {
    local upstream_tag="${1:-}"
    if [[ -z "$upstream_tag" ]]; then
        die "Usage: format-kube-patches.bash <upstream-tag> [fork-ref]"
    fi
    local base_ref="kubernetes/v${upstream_tag}"
    local fork_ref="${2:-kcp-dev/kcp-${upstream_tag}}"

    git -C kubernetes rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null \
        || die "Upstream tag '$base_ref' not found in the kubernetes clone, run ./hack/setup.bash to fetch it"
    git -C kubernetes rev-parse --verify --quiet "$fork_ref^{commit}" >/dev/null \
        || die "Fork ref '$fork_ref' not found in the kubernetes clone"

    log "Exporting $base_ref..$fork_ref to patches/"

    trap restore_patches EXIT

    rm -f patches/*.patch
    (
        cd kubernetes/
        git format-patch \
            --no-numbered \
            --no-thread \
            --no-cover-letter \
            --zero-commit \
            --signature='' \
            --text \
            --output-directory=../patches \
            "${base_ref}..${fork_ref}"

        # remove the "carry: drop: ..." commits; matching the leading
        # patch counter is required since some commits contain "drop" or
        # every "carry..drop"
        find ../patches -iregex '.*/[0-9]*-carry-drop-.*' -delete
    )
}

format_patches "$@"
