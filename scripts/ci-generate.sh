#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEF="${1:?usage: ci-generate.sh definition.json}"
case "$DEF" in
  /*) ;;
  *) DEF="$ROOT/$DEF" ;;
esac
mkdir -p "$ROOT/.cache"
POB="$ROOT/vendor/PathOfBuilding"
export LUA_PATH="$POB/runtime/lua/?.lua;$POB/runtime/lua/?/init.lua;$ROOT/core/pob-engine/shims/?.lua;;"
export LUA_CPATH=";;"
cd "$POB/src"
exec luajit "$ROOT/core/pob-engine/worker.lua" generate "$DEF"
