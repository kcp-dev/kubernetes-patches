#!/usr/bin/env bash

set -euo pipefail

log() { echo ">>> $*"; }
die() { log "$@"; exit 1; }
cd "$(dirname $0)/.."
source ".env"

# because git by default does not differentiate for tags from which remote they come from
# and we have the same tag names on both remotes, we explicitly fetch them into their remote namespaces.
# This allows us to address them via <remote>/<tag>, e.g. kcp-dev/v1.36.0 or kubernetes/v1.36.0.
# This is safe, as we don't have any overlapping tag and branch names, plus the fetch would fail if that
# ever becomes the case.
configure_remote_tags() {
    local remote="$1"
    local refspec="+refs/tags/*:refs/remotes/$remote/*"

    git config "remote.$remote.tagOpt" --no-tags
    if ! git config --get-all "remote.$remote.fetch" | grep -qF "$refspec"; then
        git config --add "remote.$remote.fetch" "$refspec"
    fi
}

clone_kube() {
    [[ -d ./kubernetes ]] || git clone --origin kubernetes --no-tags https://github.com/kubernetes/kubernetes
    (
        cd kubernetes
        if ! git remote show kcp-dev &>/dev/null; then
            git remote add kcp-dev https://github.com/kcp-dev/kubernetes
        fi
        configure_remote_tags kubernetes
        configure_remote_tags kcp-dev
        git fetch --all
    )
}

clone_kcp() {
    [[ -d ./kcp ]] || git clone --origin kcp-dev https://github.com/kcp-dev/kcp
    (
        cd kcp
        git fetch --all
    )
}

# checkout_increment recurses until the target branch does not
# exist
checkout_increment() {
    local baseline="$1"
    local branch_prefix="$2"
    local increment="$3"

    local branch="$branch_prefix"
    if [[ "$increment" -gt 0 ]]; then
        branch="$branch-$increment"
    fi

    if git rev-parse --verify "$branch" &>/dev/null; then
        log "Branch '$branch' already exists, recursing"
        checkout_increment "$baseline" "$branch_prefix" "$(( $increment + 1 ))"
        return
    fi
    # we need --no-track here, because git sets up auto-tracking if tags
    # are in different namespaces than default <insert-rolling-eyes-emoji>
    git checkout --no-track -b "$branch" "$baseline"
}

checkout_kube_baseline() {
    local kube_baseline="${1:-}"
    if [[ -z "$kube_baseline" ]]; then
        die "Usage: $0 <kube_baseline>"
    fi

    local branch="kcp-$kube_baseline"

    log "Creating fresh kube branch"
    (
        cd kubernetes
        git checkout master
        checkout_increment "kubernetes/v$kube_baseline" "$branch" 0
    )
}

checkout_kcp_baseline() {
    local kube_baseline="${1:-}"
    if [[ -z "$kube_baseline" ]]; then
        die "Usage: $0 <kube_baseline>"
    fi

    local branch="kube-rebase-$kube_baseline"

    log "Ensuring kcp branch '$branch'"
    (
        cd kcp
        git checkout main
        checkout_increment main "$branch" 0
    )
}

do_kube() {
    clone_kube
    checkout_kube_baseline "$NEW_KUBE_TAG"
}

do_kcp() {
    clone_kcp
    checkout_kcp_baseline "$NEW_KUBE_TAG"
}

case "$@" in
    (kube*) do_kube;;
    (kcp) do_kcp;;
    (both) do_kube; do_kcp;;
esac
