#!/bin/bash

set -e

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

nodeos_pid=""
current_dir=`pwd`

function cleanup {
    if [[ $nodeos_pid != "" ]]; then
      echo "Closing nodeos process"
      kill -s TERM $nodeos_pid &> /dev/null || true
    fi

    cd $current_dir
    exit 0
}

function main() {
  target="$1"
  eos_bin="$2"

  if [[ ! -d "$ROOT/$target" ]]; then
    echo "The target dirctory '$ROOT/$target' does not exist, check first provided argument."
    exit 1
  fi

  if [[ ! -f $eos_bin ]]; then
    echo "The 'nodeos' binary received does not exist, check second provided argument."
    exit 1
  fi

  # Trap exit signal and clean up
  trap cleanup EXIT

  pushd $ROOT &> /dev/null

  deep_mind_log_file="./$target/deep-mind.dmlog"
  nodeos_log_file="./$target/nodeos.log"
  eosc_boot_log_file="eosc-boot.log"

  rm -rf "$ROOT/$target/blocks/" "$ROOT/$target/state/"

  extra_args=
  if [[ $DEEP_MIND == "true" ]]; then
    extra_args="--deep-mind"
  fi

  ($eos_bin $extra_args --data-dir="$ROOT/$target" --config-dir="$ROOT/$target" --genesis-json="$ROOT/$target/genesis.json" 1> $deep_mind_log_file 2> $nodeos_log_file) &
  nodeos_pid=$!

  export EOSC_GLOBAL_INSECURE_VAULT_PASSPHRASE=secure
  export EOSC_GLOBAL_API_URL=http://localhost:9898
  export EOSC_GLOBAL_VAULT_FILE="$ROOT/eosc-vault.json"

  echo "Booting $1 node with smart contracts ..."
  pushd $target
  eosc boot ../bootseq.yaml --reuse-genesis --api-url http://localhost:9898 1> /dev/null
  mv output.log ${eosc_boot_log_file}
  popd 1> /dev/null

  echo "Booting completed, launching test cases..."

  echo "Setting eosio.code permissions on contract accounts (Account for commit d8fa7c0, which shields from mis-used authority)"
  eosc system updateauth battlefield1 active owner "$ROOT"/perms/battlefield1_active_auth.yaml
  eosc system updateauth battlefield3 active owner "$ROOT"/perms/battlefield3_active_auth.yaml
  eosc system updateauth notified2 active owner "$ROOT"/perms/notified2_active_auth.yaml
  eosc system updateauth battlefield4 active owner "$ROOT"/perms/battlefield4_active_auth.yaml
  eosc system updateauth battlefield5 active owner "$ROOT"/perms/battlefield5_active_auth.yaml
  eosc system updateauth battlefield5 claimer active "$ROOT"/perms/battlefield5_claimer_auth.yaml
  eosc system updateauth battlefield5 day2day active "$ROOT"/perms/battlefield5_day2day_auth.yaml
  eosc system linkauth battlefield5 eosio regproducer day2day -p battlefield5@active
  eosc system linkauth battlefield5 eosio unregprod day2day -p battlefield5@active
  eosc system linkauth battlefield5 eosio claimrewards day2day -p battlefield5@active
  sleep 0.6

  eosc transfer eosio battlefield1 12345678 --memo "battlefield boot"
  eosc transfer eosio battlefield3 55 --memo "battlefield boot"
  eosc transfer eosio notified1 0.5 --memo "battlefield boot"
  eosc transfer eosio notified2 12345678 --memo "battlefield boot"
  eosc transfer eosio notified3 100 --memo "battlefield boot"
  eosc transfer eosio notified4 12345678 --memo "battlefield boot"
  sleep 0.6

  eosc system newaccount battlefield1 battlefield2 --auth-key EOS5MHPYyhjBjnQZejzZHqHewPWhGTfQWSVTWYEhDmJu4SXkzgweP --stake-cpu 1 --stake-net 1 --transfer
  sleep 0.6

  echo ""
  echo "Generating coverage transaction (those can be repeated to generate traffic)"
  set +e
  ./fill-repeatable.sh "$EOSC_GLOBAL_API_URL"
  if [[ "$?" != "0" ]]; then
    echo "Generation of repeatable transactions failed"
    exit 1
  fi
  set -e

  echo ""
  echo -n "Inserting secondary indexes"
  eosc tx create battlefield1 sktest '{"action":"insert"}' -p battlefield1
  sleep 0.6

  #
  ## Producer Schedule Change
  #

  echo ""
  echo -n "Using eosio.bios contract temporarly to set producers"
  eosc system setcontract eosio contracts/eosio.bios-1.5.2.wasm contracts/eosio.bios-1.5.2.abi
  sleep 0.6

  echo ""
  echo -n "Updating producers"
  eosc tx create eosio setprods '{"schedule": [{"producer_name": "eosio2", "block_signing_key":"EOS5MHPYyhjBjnQZejzZHqHewPWhGTfQWSVTWYEhDmJu4SXkzgweP"}]}' -p eosio@active
  sleep 1.8

  echo ""
  echo -n "Returning eosio contract to standard eosio.system contract"
  eosc system setcontract eosio contracts/eosio.system-1.5.2.wasm contracts/eosio.system-1.5.2.abi
  sleep 0.6

  #
  ## Protocol Features
  #

  known_features=`curl -s "$EOSC_GLOBAL_API_URL/v1/producer/get_supported_protocol_features" | jq -cr '.[]'`

  echo ""
  echo "Available protocol features"
  echo $known_features | jq -r '. | "- \(.specification[].value) (Digest \(.feature_digest))"'

  echo ""
  echo "Activating protocol features"
  curl -s -X POST "$EOSC_GLOBAL_API_URL/v1/producer/schedule_protocol_feature_activations" -d '{"protocol_features_to_activate": ["0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"]}' > /dev/null
  eosc system setcontract eosio contracts/eosio.system-1.7.0-rc1.wasm contracts/eosio.system-1.7.0-rc1.abi
  sleep 1.8

  # This activates all known protocol features (RAM correction operations, WebAuthN keys, WTMSIG blocks, etc)
  echo ""
  echo "Activating all protocol features"
  for feature in `echo $known_features | jq -c . | grep -v "0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"`; do
    digest=`echo "$feature" | jq -cr .feature_digest`
    eosc tx create eosio activate "{\"feature_digest\":\"$digest\"}" -p eosio@active
  done

  # Activating all protocol features requires around 6 blocks to complete, so let's give 7 for a small buffer
  sleep 3.6

  #
  ## WebAuthN keys
  #

  ## WebAuthN Generation
  #
  # The WebAuthN key generation involves a Browser. We have a quick Node.js server that
  # perform the general logic of getting a WebAuthN public/private key pair and signed and
  # hard-coded transaction for us.
  #
  # This requires first to have call the `yarn generate` key to generate a key (you will
  # need your YubiKey also to generate the key material).
  #
  # Once you have your public key (it gets copied to the clipboard on the generation),
  # the following snippets will work.
  #
  # @matt
  # WEBAUTHN_PUBLIC_KEY="PUB_WA_7qjMn38M4Q6s8wamMcakZSXLm4vDpHcLqcehnWKb8TJJUMzpEZNw41pTLk6Uhqp7p"
  # @stepd
  # WEBAUTHN_PUBLIC_KEY="PUB_WA_6GDu4dfQvfgGgKWvF51pS1HxewFf3e7LQeVh7GqKbX5P5ZrzN4gtBajXBdj6R9kDk"
  # @julien
  WEBAUTHN_PUBLIC_KEY="PUB_WA_69UgrAmzcfTKUvJ5vbQ41GsdPMjopig6kgo6nhgntzp9QZEziFsUVGVCu2m9Q1L5D"


  # if the account name change, it needs to be reflected in webauthn_signer/src/index.ts
  eosc system newaccount eosio battlefeeld4 --auth-key $WEBAUTHN_PUBLIC_KEY --stake-cpu 1 --stake-net 1 --transfer
  eosc transfer eosio battlefeeld4 "200.0000 EOS"
  sleep 0.6

  ## WebAuthN Signing
  #
  # Based on your previously generated public key, this will open a Browser, ask
  # and ask him to sign a transaction and send it to our local node, effectively
  # creating a transaction signed with a WebAuthN key
  #
  echo ""
  echo "About to push a WebAuthN signed transaction"
  cd webauthn_signer
  yarn -s run transfer
  sleep 0.6
  cd ..

  #
  ## WTMSIG blocks (EOSIO 2.0 protocol feature WTMSIG_BLOCK_SIGNATURES)
  #

  ## Producer Schedule
  #
  # A change to producer schedule was reported as a `NewProducers` field on the
  # the `BlockHeader` in EOSIO 1.x. In EOSIO 2.x, when feature `WTMSIG_BLOCK_SIGNATURES`
  # is activated, the `NewProducers` field is not present anymore and the schedule change
  # is reported through a `BlockHeaderExtension` on the the `BlockHeader` struct.
  #
  # Here, we simulate such change
  echo ""
  echo "About to test WTMSIG_BLOCK_SIGNATURES protocol feature"
  echo -n "Using eosio.bios contract temporarly to set producers"
  eosc system setcontract eosio contracts/eosio.bios-1.5.2.wasm contracts/eosio.bios-1.5.2.abi
  sleep 0.6

  echo ""
  echo -n "Updating producers"
  eosc tx create eosio setprods '{"schedule": [{"producer_name": "eosio3", "block_signing_key":"EOS5MHPYyhjBjnQZejzZHqHewPWhGTfQWSVTWYEhDmJu4SXkzgweP"}]}' -p eosio@active
  sleep 1.8

  echo ""
  echo -n "Returning eosio contract to standard eosio.system contract"
  eosc system setcontract eosio contracts/eosio.system-1.7.0-rc1.wasm contracts/eosio.system-1.7.0-rc1.abi
  sleep 0.6

  echo ""
  echo "About to produce transactions to populate a table with 100K rows, this takes roughly 2m to complete"
  create_100k_rows

  echo ""
  echo "Taking snapshot"
  curl -s -X POST "$EOSC_GLOBAL_API_URL/v1/producer/create_snapshot" > /dev/null
  sleep 15


  # Not required yet, but often leads to transaction max execution time reached, so will need some tweaks to config I guess...
  # echo ""
  # echo "Updating to latest system contracts"
  # eosc system setcontract eosio contracts/eosio.system-1.9.0.wasm contracts/eosio.system-1.9.0.abi
  # sleep 0.6

  # TODO: provoke a `soft_fail` transaction
  # TODO: provoke an `expired` transaction. How to do that? Too loaded and can't push it through?

  # Kill `nodeos` process
  echo ""
  echo "Exiting in 1 sec"
  sleep 1

  if [[ $nodeos_pid != "" ]]; then
    kill -s TERM $nodeos_pid &> /dev/null || true
    sleep 0.5
  fi

  if [[ $DEEP_MIND == "true" ]]; then
    # Print Deep Mind Statistics
    set +ex
    echo "Statistics"
    echo " Blocks: `cat "$deep_mind_log_file" | grep "ACCEPTED_BLOCK" | wc -l | tr -d ' '`"
    echo " Transactions: `cat "$deep_mind_log_file" | grep "APPLIED_TRANSACTION" | wc -l | tr -d ' '`"
    echo ""
    echo " Creation Op: `cat "$deep_mind_log_file" | grep "CREATION_OP" | wc -l | tr -d ' '`"
    echo " Database Op: `cat "$deep_mind_log_file" | grep "DB_OP" | wc -l | tr -d ' '`"
    echo " Deferred Transaction Op: `cat "$deep_mind_log_file" | grep "DTRX_OP" | wc -l | tr -d ' '`"
    echo " Feature Op: `cat "$deep_mind_log_file" | grep "FEATURE_OP" | wc -l | tr -d ' '`"
    echo " Permission Op: `cat "$deep_mind_log_file" | grep "PERM_OP" | wc -l | tr -d ' '`"
    echo " Resource Limits Op: `cat "$deep_mind_log_file" | grep "RLIMIT_OP" | wc -l | tr -d ' '`"
    echo " RAM Op: `cat "$deep_mind_log_file" | grep "RAM_OP" | wc -l | tr -d ' '`"
    echo " RAM Correction Op: `cat "$deep_mind_log_file" | grep "RAM_CORRECTION_OP" | wc -l | tr -d ' '`"
    echo " Table Op: `cat "$deep_mind_log_file" | grep "TBL_OP" | wc -l | tr -d ' '`"
    echo " Transaction Op: `cat "$deep_mind_log_file" | grep "TRX_OP" | wc -l | tr -d ' '`"
    echo ""
  fi

  echo "Inspect log files"
  if [[ $DEEP_MIND == "true" ]]; then
    echo " Deep Mind logs: cat $deep_mind_log_file"
  fi
  echo " Nodeos logs: cat $nodeos_log_file"
  echo " eosc boot logs: cat $target/$eosc_boot_log_file"
  echo ""
}

# create_100k_rows will launch enough transactions to fill a table with a least 100K rows
# and will also wait enough for all transactions created here to be processed as expected
create_100k_rows() {
  for ((i=1;i<=400;i++)); do
    eosc tx create -f battlefield1 producerows '{"row_count":250}' -p battlefield1 > /dev/null
  done
  sleep 15
}

main $@
