#!/bin/bash

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

current_dir="`pwd`"
trap "cd \"$current_dir\"" EXIT
pushd "$ROOT" &> /dev/null

yarn install
rm -rf node_modules/eosjs
mkdir -p external
cd external
git clone --branch="wa-experiment" https://github.com/EOSIO/eosjs.git
cd eosjs
yarn install

cd ../..
yarn add file:external/eosjs