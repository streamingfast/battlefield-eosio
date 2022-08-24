#!/bin/bash

set -e

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

current_dir=`pwd`

function cleanup {
  cd $current_dir
}

function main() {
  eos_api_url="$1"
  if [[ "$eos_api_url" == "" ]]; then
    echo "The first argument should be the EOSIO API url to reach to generate the transaction"
    exit 1
  fi
  shift

  # Trap exit signal and clean up
  trap cleanup EXIT
  pushd $ROOT &> /dev/null

  echo "Generating transactions..."

  export EOSC_GLOBAL_INSECURE_VAULT_PASSPHRASE=secure
  export EOSC_GLOBAL_API_URL="$eos_api_url"
  export EOSC_GLOBAL_VAULT_FILE="$ROOT/eosc-vault.json"

  eosc transfer eosio battlefield1 1 --memo "memo ${TAG}"
  eosc transfer eosio battlefield3 1 --memo "memo ${TAG}"
  eosc transfer eosio notified1 1 --memo "memo ${TAG}"
  eosc transfer eosio notified3 1 --memo "memo ${TAG}"
  sleep 0.6

  eosc tx create battlefield1 dbins '{"account": "battlefield1"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 dbupd '{"account": "battlefield2"}' -p battlefield2
  sleep 0.6

  eosc tx create battlefield1 dbrem '{"account": "battlefield1"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 dtrx '{"account": "battlefield1", "fail_now": false, "fail_later": false, "fail_later_nested": false, "delay_sec": 1, "nonce": "1"}' -p battlefield1
  eosc tx create battlefield1 dtrxcancel '{"account": "battlefield1"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 dtrx '{"account": "battlefield1", "fail_now": true, "fail_later": false, "fail_later_nested": false, "delay_sec": 1, "nonce": "1"}' -p battlefield1 || true
  sleep 0.6
  echo "The error message you see above ^^^ is OK, we were expecting the transaction to fail, continuing...."

  # `send_deferred` with `replace_existing` enabled, to test `MODIFY` clauses.
  eosc tx create battlefield1 dtrx '{"account": "battlefield1", "fail_now": false, "fail_later": false, "fail_later_nested": false, "delay_sec": 1, "nonce": "1"}' -p battlefield1
  eosc tx create battlefield1 dtrx '{"account": "battlefield1", "fail_now": false, "fail_later": false, "fail_later_nested": false, "delay_sec": 1, "nonce": "2"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 dtrx '{"account": "battlefield1", "fail_now": false, "fail_later": true, "fail_later_nested": false, "delay_sec": 1, "nonce": "1"}' -p battlefield1
  echo ""
  echo "Waiting for the transaction to fail (no onerror handler)..."
  sleep 1.1

  eosc tx create battlefield1 dtrx '{"account": "battlefield1", "fail_now": false, "fail_later": false, "fail_later_nested": true, "delay_sec": 1, "nonce": "2"}' -p battlefield1
  echo ""
  echo "Waiting for the transaction to fail (no onerror handler)..."
  sleep 1.1

  eosc tx create battlefield3 dtrx '{"account": "battlefield3", "fail_now": false, "fail_later": true, "fail_later_nested": false, "delay_sec": 1, "nonce": "1"}' -p battlefield3
  echo ""
  echo "Waiting for the transaction to fail (with onerror handler that succeed)..."
  sleep 1.1

  eosc tx create battlefield3 dtrx '{"account": "battlefield3", "fail_now": false, "fail_later": true, "fail_later_nested": false, "delay_sec": 1, "nonce": "f"}' -p battlefield3
  echo ""
  echo "Waiting for the transaction to fail (with onerror handler that failed)..."
  sleep 1.1

  eosc tx create battlefield3 dtrx '{"account": "battlefield3", "fail_now": false, "fail_later": true, "fail_later_nested": false, "delay_sec": 1, "nonce": "nf"}' -p battlefield3
  echo ""
  echo "Waiting for the transaction to fail (with onerror handler that failed inside a nested action)..."
  sleep 1.1

  eosc tx create battlefield1 dbinstwo '{"account": "battlefield1", "first": 100, "second": 101}' -p battlefield1
  # This TX will do one DB_OPERATION for writing, and the second will fail. We want our instrumentation NOT to keep that DB_OPERATION.
  eosc tx create --delay-sec=1 battlefield1 dbinstwo '{"account": "battlefield1", "first": 102, "second": 100}' -p battlefield1
  echo ""
  echo "Waiting for the transaction to fail, yet attempt to write to storage"
  sleep 1.1

  eosc tx create battlefield1 dbremtwo '{"account": "battlefield1", "first": 100, "second": 101}' -p battlefield1

  # This TX will show a delay transaction (deferred) that succeeds
  eosc tx create --delay-sec=1 eosio.token transfer '{"from": "eosio", "to": "battlefield1", "quantity": "1.0000 EOS", "memo":"push delayed trx"}' -p eosio
  sleep 1.1

  # This is to see how the RAM_USAGE behaves, when a deferred hard_fails. Does it refund the deferred_trx_remove ? What about the other RAM tweaks? Any one them saved?
  eosc tx create battlefield1 dbinstwo '{"account": "battlefield1", "first": 200, "second": 201}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 dbremtwo '{"account": "battlefield1", "first": 200, "second": 201}' -p battlefield1

  echo ""
  echo "Create a delayed and cancel it (in same block) with 'eosio:canceldelay'"
  eosc tx create --delay-sec=3600 battlefield1 dbins '{"account": "battlefield1"}' -p battlefield1 --write-transaction /tmp/delayed.json
  ID=`eosc tx id /tmp/delayed.json`
  eosc tx push /tmp/delayed.json
  eosc tx cancel battlefield1 $ID
  rm /tmp/delayed.json || true

  sleep 0.6

  echo ""
  echo "Create a delayed and cancel it (in different block) with 'eosio:canceldelay'"
  eosc tx create --delay-sec=3600 battlefield1 dbins '{"account": "battlefield1"}' -p battlefield1 --write-transaction /tmp/delayed.json
  ID=`eosc tx id /tmp/delayed.json`
  eosc tx push /tmp/delayed.json
  sleep 1.1

  eosc tx cancel battlefield1 $ID
  rm /tmp/delayed.json || true
  sleep 0.6

  echo ""
  echo -n "Create auth structs, updateauth to create, updateauth to modify, deleteauth to test AUTH_OPs"
  eosc system updateauth battlefield2 ops active EOS7f5watu1cLgth3ub1uAnsGkHq1F6PhauScBg6rJGUfe79MgG9Y # random key
  sleep 0.6

  eosc system updateauth battlefield2 ops active EOS5MHPYyhjBjnQZejzZHqHewPWhGTfQWSVTWYEhDmJu4SXkzgweP # back to safe key
  sleep 0.6

  eosc system linkauth battlefield2 eosio.token transfer ops
  sleep 0.6

  eosc system unlinkauth battlefield2 eosio.token transfer
  sleep 0.6

  eosc system deleteauth battlefield2 ops
  sleep 0.6

  echo ""
  echo -n "Create a creational order different than the execution order"
  ## We use the --force-unique flag so a context-free action exist in the transactions traces tree prior our own,
  ## creating a multi-root execution traces tree.
  eosc tx create --force-unique battlefield1 creaorder '{"n1": "notified1", "n2": "notified2", "n3": "notified3", "n4": "notified4", "n5": "notified5"}' -p battlefield1
  sleep 0.6

  ## Series of test for variant support

  eosc tx create battlefield1 varianttest '{"value":["uint16",12]}' -p battlefield1
  eosc tx create battlefield1 varianttest '{"value":["string","this is a long value"]}' -p battlefield1
  sleep 0.6

  ## Series of test for secondary keys

  eosc tx create battlefield1 sktest '{"action":"insert"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 sktest '{"action":"update.sk"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 sktest '{"action":"update.ot"}' -p battlefield1
  sleep 0.6

  eosc tx create battlefield1 sktest '{"action":"remove"}' -p battlefield1
  sleep 0.6
}

main "$@"
