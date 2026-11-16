#!/usr/bin/env bash
# apply-patches.sh <repo-dir> <stamp-dir> <patch>...
#
# Applies a set of patches to <repo-dir>, in order, once. A stamp records a hash
# of the whole set and the submodule's commit. When a patch is added, removed or
# changed, or the submodule moves, every file any of the patches touches is reset
# to the submodule's version (files a patch creates are removed) and the whole set
# is applied again. Resetting per patch would undo an earlier patch that edits the
# same file.
set -euo pipefail

repo="$1"
stamps="$2"
shift 2
mkdir -p "$stamps"
stamp="$stamps/applied.sha"

abs=()
for patch in "$@"; do
  abs+=("$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")")
done

hash_of() { if command -v shasum >/dev/null; then shasum -a 256; else sha256sum; fi; }
sum="$({ git -C "$repo" rev-parse HEAD
         for p in ${abs[@]+"${abs[@]}"}; do basename "$p"; cat "$p"; done; } | hash_of)"
sum="${sum%% *}"

touched=$({ for p in ${abs[@]+"${abs[@]}"}; do sed -n 's|^+++ b/||p' "$p"; done
            [ -f "$stamps/touched" ] && cat "$stamps/touched" || true; } | sed '/^$/d' | sort -u)

# Up to date: same set and commit, and the patched files still differ from the
# commit (a checkout of the submodule would have reset them).
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sum" ]; then
  if [ ${#abs[@]} -eq 0 ] || ! git -C "$repo" diff --quiet -- $touched 2>/dev/null ||
     [ -n "$(git -C "$repo" ls-files --others --exclude-standard -- $touched)" ]; then
    exit 0
  fi
fi

for f in $touched; do
  if git -C "$repo" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    git -C "$repo" checkout -- "$f"
  else
    rm -f "$repo/$f"  # created by a patch
  fi
done

for p in ${abs[@]+"${abs[@]}"}; do
  echo "Applying $(basename "$p")"
  git -C "$repo" apply "$p"
done
printf '%s\n' "$touched" > "$stamps/touched"
echo "$sum" > "$stamp"
# Stamps left by the earlier per-patch version of this script.
rm -f "$stamps"/*.patch.sha
