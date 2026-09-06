#!/usr/bin/env bash
# Resolve every package, including the one that is deliberately outside the
# pub workspace.
#
# `lattice_runtime` is not a workspace member on purpose: generated projects
# path-depend on it from outside the workspace, and pub refuses a path
# dependency onto a member. The cost is that a root `pub get` does not resolve
# it, so a fresh clone cannot even be analysed until this has run.
set -euo pipefail

flutter pub get
(cd packages/lattice_runtime && flutter pub get)

echo "Resolved the workspace and lattice_runtime."
