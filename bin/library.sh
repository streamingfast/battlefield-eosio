export BIN_DIR=${ROOT}/bin
export BOOT_DIR=${ROOT}/boot
export RUN_DIR=${ROOT}/run

export nodeos_bin=${NODEOS_BIN:-"nodeos"}

recreate_data_directories() {
  chain="$1"
  data_dir="$RUN_DIR/data/syncer/$chain"
  oracle_dir="$RUN_DIR/data/oracle/$chain"

  rm -rf "$data_dir" > /dev/null
  mkdir -p "$data_dir" > /dev/null

  cp -a "$oracle_dir/config.ini" "$data_dir"
  cp -a "$oracle_dir/blocks" "$data_dir"
  cp -a "$oracle_dir/protocol_features" "$data_dir"
}

# usage <name> <pid> <parent_pid> [<process_log>]
monitor() {
  name=$1
  pid=$2
  parent_pid=$3
  process_log=

  if [[ $# -gt 3 ]]; then
    process_log=$4
  fi

  while true; do
    if ! kill -0 $pid &> /dev/null; then
      sleep 2

      echo "Process $name ($pid) died, exiting parent"
      if [[ "$process_log" != "" ]]; then
        echo "Last 75 lines of log"
        tail -n 75 $process_log

        echo
        echo "See full logs with 'less `relpath $process_log`'"
      fi

      kill -s TERM $parent_pid &> /dev/null
      exit 0
    fi

    sleep 1
  done
}

kill_pid() {
  name=$1
  pid=$2

  if [[ $pid != "" ]]; then
    echo "Closing $name process..."
    kill -s TERM $pid &> /dev/null || true
    wait "$pid" &> /dev/null
  fi
}

sleep_forever() {
    while true; do sleep 1000000; done
}

to_dec() {
    value=`echo $1 | awk '{print toupper($0)}'`
    echo "ibase=16; ${value}" | bc
}

relpath() {
  if [[ $1 =~ /* ]]; then
    # Works only if path is already absolute and do not contain ,
    echo "$1" | sed s,$PWD,.,g
  else
    # Print as-is
    echo $1
  fi
}

# public_key <key_file_path>
public_key() {
  printf $(cat "$1" | jq -r .public_key)
}