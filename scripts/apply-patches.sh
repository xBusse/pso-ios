#!/usr/bin/env bash
# apply-patches.sh <repo-dir> <stamp-dir> <patch>...
#
# Applies each patch to <repo-dir> once. A stamp records the hash of the
# patch that was applied; when a patch file changes, the files it touches are
# reset to the submodule's version and the new patch is applied in its place.
set -euo pipefail

repo="$1"
stamps="$2"
shift 2
mkdir -p "$stamps"

for patch in "$@"; do
  abs="$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")"
  name="$(basename "$patch")"
  stamp="$stamps/$name.sha"
  sum="$(shasum -a 256 "$abs" 2>/dev/null || sha256sum "$abs")"
  sum="${sum%% *}"

  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sum" ] &&
     git -C "$repo" apply --reverse --check "$abs" 2>/dev/null; then
    continue
  fi

  # Reset whatever this patch (any version of it) touches, then apply.
  files=$(sed -n 's|^+++ b/||p' "$abs")
  if [ -n "$files" ]; then
    # shellcheck disable=SC2086
    git -C "$repo" checkout -- $files
  fi
  echo "Applying $name"
  git -C "$repo" apply "$abs"
  echo "$sum" > "$stamp"
done
