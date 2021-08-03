#!/usr/bin/env bash

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

source "$ROOT/bin/library.sh"

parent_pid="$$"
syncer_pid=""
syncer_container=""
current_dir=`pwd`

main() {
  pushd "$ROOT" &> /dev/null

  skip_comparison=false
  skip_generation=false

  while getopts "hsn" opt; do
    case $opt in
      h) usage && exit 0;;
      s) skip_generation=true;;
      n) skip_comparison=true;;
      \?) usage_error "Invalid option: -$OPTARG";;
    esac
  done
  shift $((OPTIND-1))

  if [[ $1 == "" ]]; then
    usage_error "The <chain> argument must be provided, one of `valid_chains`"
  fi

  if [[ ! -d "run/data/oracle/$1" ]]; then
    usage_error "The <chain> argument must exist under run/data/oracle, one of `valid_chains`"
  fi

  chain="$1"; shift
  trap cleanup EXIT

  syncer_data_dir="$RUN_DIR/data/syncer/$chain"
  syncer_log="$RUN_DIR/syncer-$chain-nodeos.log"
  syncer_dmlog="$RUN_DIR/syncer-$chain.dmlog"

  if [[ $skip_generation == false ]]; then
    recreate_data_directories "$chain"

    # We need to delete the previous log final since we use it later to determine if we
    # are fully sync or not. If the file is not deleted, there is a race where `nodeos`
    # did not start yet but the wait for sync below thinks it's already finish.
    rm -rf "$syncer_log" &> /dev/null || true
    touch "$syncer_log" &> /dev/null || true

    echo "Starting syncer process (log `relpath $syncer_log`)"
    ($nodeos_bin \
        --data-dir="$syncer_data_dir" \
        --config-dir="$syncer_data_dir" \
        --replay-blockchain $@ 1> $syncer_dmlog 2> $syncer_log) &
    syncer_pid=$!

    monitor "syncer" $syncer_pid $parent_pid "$syncer_log" &

    echo ""
    echo "Waiting for syncer to fully sync"
    set +e
    while true; do
      result=`cat "$syncer_log" | grep -E "Blockchain started"`
      if [[ $result != "" ]]; then
          echo ""
          break
      fi

      echo "Giving 5s for syncer to complete syncing"
      sleep 5
    done
    set -e
  fi

  echo "Statistics"
  echo " Blocks: `cat "$syncer_dmlog" | grep "ACCEPTED_BLOCK" | wc -l | tr -d ' '`"
  echo " Trxs: `cat "$syncer_dmlog" | grep "APPLIED_TRANSACTION" | wc -l | tr -d ' '`"
  echo " Actions: `cat "$syncer_dmlog" | grep "CREATION_OP" | wc -l | tr -d ' '`"
  echo ""
  echo " Database Operations: `cat "$syncer_dmlog" | grep "DB_OP" | wc -l | tr -d ' '`"
  echo " Permission Operations: `cat "$syncer_dmlog" | grep "PERM_OP" | wc -l | tr -d ' '`"
  echo " RAM Operations: `cat "$syncer_dmlog" | grep "RAM_OP" | wc -l | tr -d ' '`"
  echo ""

  echo "Inspect log files"
  echo " Syncer Deep Mind logs: cat `relpath "$syncer_dmlog"`"
  echo " Syncer logs (geth): cat `relpath "$syncer_log"`"
  echo ""

  if [[ $skip_comparison == false ]]; then
    echo "Launching blocks comparison task (and compiling Go code)"
    go run battlefield.go "$chain"
  fi
}

cleanup() {
  kill_pid "syncer" $syncer_pid
  [[ $syncer_container != "" ]] && (docker kill $syncer_container &> /dev/null || true)

  # Let's kill everything else
  kill $( jobs -p ) &> /dev/null
}

usage_error() {
  message="$1"
  exit_code="$2"

  echo "ERROR: $message"
  echo ""
  usage
  exit ${exit_code:-1}
}

usage() {
  echo "usage: compare_vs_oracle.sh [-s] [-n] <chain>"
  echo ""
  echo "The <chain> parameter must be either one of `valid_chains`."
  echo ""
  echo "Run a comparison between oracle reference files and a new Deep Mind version."
  echo "This scripts starts replays the chain from a fixed 'blocks.log' file replaying"
  echo "all transactions in it and generating Deep Mind logs."
  echo ""
  echo "Options"
  echo "    -s          Skip syncer/miner launching and only run comparison (useful when developing 'battlefield.go')"
  echo "    -n          Dry-run by not running any comparison code, exit right away once syncing has completed"
  echo "    -h          Display help about this script"
}

valid_chains() {
  ls run/data/oracle | tr "\n" "," | sed -E 's/,$//' | sed 's/,/, /g'
}

main "$@"
