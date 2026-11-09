#!/usr/bin/env bash

# TODO (@SimonTheLeg) move this into the regular setup.bash

set -euo pipefail

log() { echo ">>> $*"; }
die() { log "$@"; exit 1; }
cd "$(dirname $0)/.."

[[ -n "${KUBERNETES_FORK_REMOTE:-}" ]] || die "KUBERNETES_FORK_REMOTE must be set to the URL of your kubernetes fork"
[[ -n "${KCP_FORK_REMOTE:-}" ]] || die "KCP_FORK_REMOTE must be set to the URL of your kcp fork"
[[ -d kubernetes ]] && [[ -d kcp ]] || die "kubernetes/ and kcp/ clones not found, run ./hack/setup.bash both first"

setup_origin() {
    local repo="$1"
    local url="$2"

    if git -C "$repo" remote get-url origin &>/dev/null; then
        git -C "$repo" remote set-url origin "$url"
    else
        git -C "$repo" remote add origin "$url"
    fi
    git -C "$repo" config remote.pushDefault origin
    log "$repo: origin -> $url"
}

setup_origin kubernetes "$KUBERNETES_FORK_REMOTE"
# a kubernetes fork carries all upstream tags, keep them out of the default
# tag namespace like setup.bash does for the other remotes
git -C kubernetes config remote.origin.tagOpt --no-tags

setup_origin kcp "$KCP_FORK_REMOTE"
