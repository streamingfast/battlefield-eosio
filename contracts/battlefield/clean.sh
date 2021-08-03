#!/usr/bin/env bash

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

BROWN='\033[0;33m'
NC='\033[0m'

printf "${BROWN}Deleting 'build' artifacts${NC}\n"
rm -rf "$ROOT"/*.abi
rm -rf "$ROOT"/*.wasm