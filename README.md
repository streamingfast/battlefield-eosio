## EOSIO - Battlefield

A repository containing contracts and scripts to effectively testing
all aspects of our EOSIO instrumentation.

This repository assumes you have the following tool in available
globally through your terminal:

- nodeos (Deep mind enabled)

### Comparing New Version of EOSIO

If you want to ensure that a new version of our EOSIO Deep Mind
aware binary is valid against the previously saved valid baseline
version called the `oracle`, ensure that `nodeos` in your `PATH` points
to the new version to test then run:

    ./bin/compare_vs_oracle.sh eos-2.x

**Note** It's possible to specify directly the `nodeos` binary to use by overriding the environment variable `NODEOS_BIN` something like `NODEOS_BIN=/work/debug/nodeos ./bin/compare_vs_oracle.sh eos-2.x`.

If there is any diff, you will be asked to check the differences using
`diff`.

You will also prompted to accept the changes as the new oracle data files,
which you can answer `Yes` to update the oracle with the newly generated run.

**Important** Great care must be taken when accepting a new version to ensure the
changes are correct. Think about previous versions and other supported Geth forks when
taking your decision

### Regenerating Oracle Data

**Not ported from our internal repository yet**
