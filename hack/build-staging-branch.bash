#!/usr/bin/env bash

# Simple helper script to extract commits which touch kcp staging files to
# a separate branch for easier PR making.
# Script is fully idempotent and leaves the kcp working tree untouched.

set -euo pipefail

log() { echo ">>> $*"; }
die() { log "$@"; exit 1; }
cd "$(dirname $0)/.."
source .env

IGNORE_DIRTY_PR="${IGNORE_DIRTY_PR:-false}"
ENABLE_SQUASH="${ENABLE_SQUASH:-true}"

# in dependency order
soft_fork_dirs=(
    staging/src/github.com/kcp-dev/apimachinery
    staging/src/github.com/kcp-dev/code-generator
    staging/src/github.com/kcp-dev/client-go
)
soft_fork_pattern='^staging/src/github.com/kcp-dev/(apimachinery|client-go|code-generator)/'

kcp_remote="kcp-dev"
base_ref="${kcp_remote}/main"
source_branch="${1:-kube-rebase-${NEW_KUBE_TAG}}"
output_branch="${source_branch}-staging"
if [[ "$ENABLE_SQUASH" == "true" ]]; then
    output_branch="${output_branch}-squashed"
fi

worktree=""
cleanup() {
    if [[ -n "$worktree" ]] && [[ -d "$worktree" ]]; then
        git -C kcp worktree remove --force "$worktree" &>/dev/null || true
    fi
}
trap cleanup EXIT

git -C kcp rev-parse --verify --quiet "$source_branch" &>/dev/null \
    || die "Source branch '$source_branch' does not exist in the kcp clone"

if [[ "$(git -C kcp branch --show-current)" == "$output_branch" ]]; then
    die "Output branch '$output_branch' is currently checked out in the kcp clone, switch branches first"
fi

fork_url="$(git -C kcp remote get-url origin 2>/dev/null)" \
    || die "The kcp clone has no origin remote, run ./hack/setup-remotes.bash first"

log "Fetching $base_ref"
git -C kcp fetch --quiet "$kcp_remote" main

log "Collecting soft fork commits on $base_ref..$source_branch"
commits=$(git -C kcp log --reverse --no-merges --format=%H "$base_ref..$source_branch" -- "${soft_fork_dirs[@]}")
if [[ -z "$commits" ]]; then
    die "No commits touching the soft fork modules found on $source_branch"
fi

# A commit that also touches files outside the modules would drag unrelated
# changes into the published staging repositories
for commit in $commits; do
    if git -C kcp show --format= --name-only "$commit" | grep -qvE "$soft_fork_pattern"; then
        git -C kcp --no-pager show --format="%h %s" --no-patch "$commit"
        if [[ "$IGNORE_DIRTY_PR" == "true" ]]; then
            log "Commit touches files outside the soft fork modules, continuing because IGNORE_DIRTY_PR=true"
        else
            die "Commit touches files outside the soft fork modules, split it or set IGNORE_DIRTY_PR=true"
        fi
    fi
done

log "The following commits are touching staging components and will be extracted to the PR branch:"
git -C kcp --no-pager log --format="    %h %s" --no-walk=unsorted $commits

log "Replaying onto $base_ref in a temporary worktree"
worktree="$(mktemp -d)"
git -C kcp worktree add --quiet --detach "$worktree" "$base_ref"
if ! git -C "$worktree" cherry-pick --quiet $commits >/dev/null; then
    git -C "$worktree" cherry-pick --abort || true
    die "Cherry-pick onto $base_ref failed, rebase '$source_branch' onto $base_ref and retry"
fi

if [[ "$ENABLE_SQUASH" == "true" ]]; then
    log "Squashing into one commit per soft fork module"
    # Unstage everything down to the base and re-commit it module by module.
    # The tree stays identical, only the history changes.
    git -C "$worktree" reset -q --mixed "$base_ref"
    for dir in "${soft_fork_dirs[@]}"; do
        [[ -n "$(git -C "$worktree" status --porcelain -- "$dir")" ]] || continue
        module="$(basename "$dir")"
        subjects=$(git -C kcp log --reverse --format="- %s" "$base_ref..$source_branch" -- "$dir")
        git -C "$worktree" add -A -- "$dir"
        # generate into the commit message, which commits got squashed into this one
        printf 'Bump %s to Kubernetes v%s\n\nSquashed into one commit per staging module so that the publishing bot\ncan run go mod tidy on every published commit on its own:\n\n%s\n' \
            "$module" "$NEW_KUBE_TAG" "$subjects" | git -C "$worktree" commit -q -F -
        git -C "$worktree" --no-pager log -1 --format="    %h %s"
    done
    # Leftovers are outside the modules and only exist with IGNORE_DIRTY_PR=true.
    if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
        git -C "$worktree" add -A
        git -C "$worktree" commit -q -m "Changes outside the soft fork modules"
        git -C "$worktree" --no-pager log -1 --format="    %h %s"
    fi
fi

# Final gate: the diff against the base must be confined to the modules.
if git -C "$worktree" diff --name-only "$base_ref" HEAD | grep -qvE "$soft_fork_pattern"; then
    if [[ "$IGNORE_DIRTY_PR" == "true" ]]; then
        log "Resulting branch touches files outside the soft fork modules, continuing because IGNORE_DIRTY_PR=true"
    else
        die "Resulting branch touches files outside the soft fork modules"
    fi
fi

git -C kcp branch --force "$output_branch" "$(git -C "$worktree" rev-parse HEAD)"

fork_owner="$(basename "$(dirname "${fork_url%.git}")")"
fork_owner="${fork_owner##*:}"

log "Extraction finished to branch $output_branch"
log "Either use these steps to create the PR or do it manually yourself:"
echo
echo "    git -C kcp push --force-with-lease --set-upstream origin $output_branch"
# gh has no equivalent of git -C, so it has to be run from inside the kcp clone
echo "    (cd kcp && gh pr create --web --repo kcp-dev/kcp --base main --head ${fork_owner}:$output_branch \\"
echo "        --title 'Bump soft-fork staging modules to Kubernetes v${NEW_KUBE_TAG}')"
echo
