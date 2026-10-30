#!/usr/bin/env bash

# poor man's detection, but better than going strictly by OS
if sed --version &>/dev/null; then
    _sed() { sed -i "$@"; }
else
    _sed() { sed -i '' "$@"; }
fi
