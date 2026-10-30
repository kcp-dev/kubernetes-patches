#!/usr/bin/env bash
# strips the blob information from the patch files so we don't
# generate unnecessary changes to the blob files every time we
# do the reformatting.

# Only run this AFTER you have applied all patches as otherwise
# it will be breaking the `--3way` merge option!
set -euo pipefail

log() { echo ">>> $*"; }
die() { log "$@"; exit 1; }
cd "$(dirname $0)/.."
source ./hack/lib.bash

_sed -e '/^index/d' patches/*.patch
