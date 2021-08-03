#!/usr/bin/env bash

set -e

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

BROWN='\033[0;33m'
NC='\033[0m'

CORES=`getconf _NPROCESSORS_ONLN`

printf "${BROWN}Compiling ${NC}\n"

function build() {
    name=$1
    define=$2

    printf "${BROWN}Building battlefield ($name)${NC}\n"
    eosio-cpp \
    -O3 \
    -I${ROOT}/include \
    -D=$define \
    -abigen -abigen_output="${ROOT}/battlefield-${name}.abi" \
    -contract battlefield \
    -o "${ROOT}/battlefield-${name}.wasm" \
    src/battlefield.cpp
}

build "with-handler" "WITH_ONERROR_HANDLER=1"
echo ""

build "without-handler" "WITH_ONERROR_HANDLER=0"

popd &> /dev/null

