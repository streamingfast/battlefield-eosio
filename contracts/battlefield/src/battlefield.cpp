#include "battlefield.hpp"

void battlefield::dbins(name account)
{
    require_auth(account);

    print("dbins ran and you're authenticated");

    members member_table(_self, _self.value);
    member_table.emplace(account, [&](auto &row) {
        row.id = 1;
        row.account = "dbops1"_n;
        row.memo = "inserted billed to calling account";
        row.created_at = time_point_sec(current_time_point());
    });

    member_table.emplace(_self, [&](auto &row) {
        row.id = 2;
        row.account = "dbops2"_n;
        row.memo = "inserted billed to self";
        row.created_at = time_point_sec(current_time_point());
    });
}

void battlefield::dbinstwo(name account, uint64_t first, uint64_t second)
{
    require_auth(account);

    members member_table(_self, _self.value);
    member_table.emplace(account, [&](auto &row) {
        row.id = first;
        row.account = name(first);
        row.memo = "inserted billed to calling account";
        row.created_at = time_point_sec(current_time_point());
    });

    member_table.emplace(_self, [&](auto &row) {
        row.id = second;
        row.account = name(second);
        row.memo = "inserted billed to self";
        row.created_at = time_point_sec(current_time_point());
    });
}

void battlefield::dbupd(name account)
{
    require_auth(account);

    members member_table(_self, _self.value);
    auto index = member_table.template get_index<"byaccount"_n>();
    auto itr1 = index.find("dbops1"_n.value);
    auto itr2 = index.find("dbops2"_n.value);

    index.modify(itr1, _self, [&](auto &row) {
        row.memo = "updated row 1";
    });

    index.modify(itr2, account, [&](auto &row) {
        row.account = "dbupd"_n;
        row.memo = "updated row 2";
    });
}

void battlefield::dbrem(name account)
{
    require_auth(account);

    members member_table(_self, _self.value);
    auto index = member_table.template get_index<"byaccount"_n>();
    index.erase(index.find("dbops1"_n.value));
    index.erase(index.find("dbupd"_n.value));
}

void battlefield::dbremtwo(name account, uint64_t first, uint64_t second)
{
    require_auth(account);

    members member_table(_self, _self.value);
    auto index = member_table.template get_index<"byaccount"_n>();
    index.erase(index.find(name(first).value));
    index.erase(index.find(name(second).value));
}

void battlefield::dtrx(
    name account,
    bool fail_now,
    bool fail_later,
    bool fail_later_nested,
    uint32_t delay_sec,
    string nonce)
{
    require_auth(account);

    eosio::transaction deferred;
    uint128_t sender_id = (uint128_t(0x1122334455667788) << 64) | uint128_t(0x1122334455667788);
    deferred.actions.emplace_back(
        permission_level{_self, "active"_n},
        _self,
        "dtrxexec"_n,
        std::make_tuple(account, fail_later, fail_later_nested, nonce));
    deferred.delay_sec = delay_sec;
    deferred.send(sender_id, account, true);

    check(!fail_now, "forced fail as requested by action parameters");
}

void battlefield::dtrxcancel(name account)
{
    require_auth(account);

    uint128_t sender_id = (uint128_t(0x1122334455667788) << 64) | uint128_t(0x1122334455667788);
    cancel_deferred(sender_id);
}

void battlefield::dtrxexec(name account, bool fail, bool failNested, std::string nonce)
{
    print("dtrxexec start console log, before failing");

    require_auth(account);
    check(!fail, "dtrxexec instructed to fail");

    // FIXME: Unable to use `nestdtrxexec_action` due to https://github.com/EOSIO/eosio.cdt/issues/519
    eosio::action nested(
        std::vector<permission_level>({permission_level(_self, "active"_n)}),
        account,
        "nestdtrxexec"_n,
        std::make_tuple(failNested));
    nested.send();
}

void battlefield::nestdtrxexec(bool fail)
{
    print("Nested inline within dtrxexec");

    check(!fail, "dtrxexec instructed to fail");
}

void battlefield::nestonerror(bool fail)
{
    print("Nested inline within onerror handler");

    members member_table(_self, _self.value);
    member_table.emplace(_self, [&](auto &row) {
        row.id = member_table.available_primary_key();
        row.account = "nestonerror"_n;
        row.memo = "from nested onerror handler";
        row.created_at = time_point_sec(current_time_point());
    });

    check(!fail, "nestonerror instructed to fail");
}

#if WITH_ONERROR_HANDLER == 1
// Must match signature of dtrxexec above
struct dtrxexec_data
{
    name account;
    bool fail;
    bool failNested;
    std::string nonce;
};

void battlefield::onerror(eosio::onerror data)
{
    print("Called on error handler\n");

    members member_table(_self, _self.value);
    member_table.emplace(_self, [&](auto &row) {
        row.id = member_table.available_primary_key();
        row.account = "onerror"_n;
        row.memo = "from onerror handler";
        row.created_at = time_point_sec(current_time_point());
    });

    eosio::transaction trx = data.unpack_sent_trx();
    eosio::action action = trx.actions[0];

    auto action_data = action.data_as<dtrxexec_data>();
    print("Extracted ", action_data.nonce, " \n");

    if (action_data.nonce == "f")
    {
        check(false, "onerror instructed to fail");
    }
    else
    {
        print("Data nonce was not f", "\n");
    }

    // Let's re-use account passed to `dtrxexec` directly
    //
    // FIXME: Unline `creaorder`, `notified4` and `notified5` are hard-coded here, if they
    //        were pass to `dtrxexec`, we could re-use them here...
    inlinedeep_action inline_deep(action_data.account, {_self, "active"_n});

    inline_deep.send(action_data.nonce, "notified4"_n, "notified5"_n, string("i3"), false, string("c3"));

    // FIXME: Unable to use `nestonerror_action` due to https://github.com/EOSIO/eosio.cdt/issues/519
    eosio::action nestedSuccess(
        std::vector<permission_level>({permission_level(_self, "active"_n)}),
        action_data.account,
        "nestonerror"_n,
        std::make_tuple(false));
    nestedSuccess.send();

    if (action_data.nonce == "nf")
    {
        // FIXME: Unable to use `nestonerror_action` due to https://github.com/EOSIO/eosio.cdt/issues/519
        eosio::action nestedFail(
            std::vector<permission_level>({permission_level(_self, "active"_n)}),
            action_data.account,
            "nestonerror"_n,
            std::make_tuple(true));
        nestedFail.send();
    }
}
#endif

void battlefield::creaorder(name n1, name n2, name n3, name n4, name n5)
{
    require_recipient(n1);

    inlinedeep_action i2(_first_receiver, {_self, "active"_n});
    i2.send(string("i2"), n4, n5, string("i3"), false, string("c3"));

    require_recipient(n2);

    action c2(std::vector<permission_level>(), "eosio.null"_n, "nonce"_n, std::make_tuple(string("c2")));
    c2.send_context_free();
}

void battlefield::on_creaorder(name n1, name n2, name n3, name n4, name n5)
{
    // TODO: Would a pre_dispatch hook be preferable?
    // We are actually dealing with a notifiction on creaorder, let's allow it only for n2
    if (_self != n2)
    {
        return;
    }

    // Dealing with n2 notification, send i1 and notify n3
    inlineempty_action i1(_first_receiver, {_self, "active"_n});
    i1.send(string("i1"), false);

    action c1(std::vector<permission_level>(), "eosio.null"_n, "nonce"_n, std::make_tuple(string("c1")));
    c1.send_context_free();

    require_recipient(n3);
}

void battlefield::inlineempty(string tag, bool fail)
{
    check(!fail, "inlineempty instructed to fail");
}

void battlefield::inlinedeep(
    string tag,
    name n4,
    name n5,
    string nestedInlineTag,
    bool nestedInlineFail,
    string nestedCfaInlineTag)
{
    require_recipient(n4);
    require_recipient(n5);

    inlineempty_action nested(_first_receiver, {_self, "active"_n});
    nested.send(nestedInlineTag, nestedInlineFail);

    action cfaNested(std::vector<permission_level>(), "eosio.null"_n, "nonce"_n, std::make_tuple(nestedCfaInlineTag));
    cfaNested.send_context_free();
}

void battlefield::varianttest(varying_action value)
{
    std::visit([](auto &&arg) {
        using T = std::decay_t<decltype(arg)>;
        if constexpr (std::is_same_v<T, uint16_t>)
        {
            print("Called uint16_t variant", arg, "\n");
        }
        else if constexpr (std::is_same_v<T, std::string>)
        {
            print("Called string variant", arg, "\n");
        }
    },
               value);

    variers variant_table(_self, _self.value);
    variant_table.emplace(_self, [&](auto &row) {
        row.id = variant_table.available_primary_key();
        row.creation_number = 0xFFFFFFFF00;

        if (value.index() == 0)
        {
            row.variant_field = std::get<uint16_t>(value);
        }
        else
        {
            row.variant_field = int32_t(std::get<string>(value).length());
        }
    });
}

void battlefield::producerows(uint64_t row_count)
{
    variers variant_table(_self, _self.value);

    for (uint64_t i = 0; i < row_count; ++i)
    {
        variant_table.emplace(_self, [&](auto &row) {
            row.id = variant_table.available_primary_key();
            row.creation_number = i;

            if (i % 5 == 0)
            {
                row.variant_field = int32_t(i);
            }
            else if (i % 4 == 0)
            {
                row.variant_field = uint32_t(i);
            }
            else if (i % 3 == 0)
            {
                row.variant_field = uint16_t(i);
            }
            else if (i % 2 == 0)
            {
                row.variant_field = int8_t(i);
            }
        });
    }
}

void battlefield::sktest(name action)
{
    // It's expected to have those called on a certain order

    sk_i64 sk_i64_table(_self, _self.value);
    sk_i128 sk_i128_table(_self, _self.value);
    sk_d64 sk_d64_table(_self, _self.value);
    sk_d128 sk_d128_table(_self, _self.value);
    sk_c256 sk_c256_table(_self, _self.value);
    sk_multi sk_multi_table(_self, _self.value);

    if (action == "insert"_n)
    {
        sk_i64_table.emplace(_self, [&](auto &row) {
            row.id = sk_i64_table.available_primary_key();
            row.i64 = uint64_t(row.id + 1);
        });

        sk_i128_table.emplace(_self, [&](auto &row) {
            row.id = sk_i128_table.available_primary_key();
            row.i128 = uint128_t(row.id + 2);
        });

        sk_d64_table.emplace(_self, [&](auto &row) {
            row.id = sk_d64_table.available_primary_key();
            row.d64 = double(row.id) + 3.1;
        });

        sk_d128_table.emplace(_self, [&](auto &row) {
            row.id = sk_d128_table.available_primary_key();
            row.d128 = (long double)(row.id) + (long double)(4.6);
        });

        sk_c256_table.emplace(_self, [&](auto &row) {
            row.id = sk_c256_table.available_primary_key();

            uint128_t end = uint128_t(0xFFAABB00DDEE1122) << 64 | uint128_t(0x0033445500FFAA22);
            std::array<uint128_t, 2> words = {row.id + 5, end};

            row.c256 = checksum256(words);
        });

        sk_multi_table.emplace(_self, [&](auto &row) {
            row.id = sk_multi_table.available_primary_key();
            row.i64 = uint64_t(row.id + 1);
            row.i128 = uint128_t(row.id + 2);
            row.d64 = double(row.id) + 3.1;
            row.d128 = (long double)(row.id) + (long double)(4.6);
        });
    }
    else if (action == "update.sk"_n)
    {
        auto sk_i64_id = uint64_t(sk_i64_table.available_primary_key() - 1) + 1;
        auto sk_i64_index = sk_i64_table.template get_index<"i"_n>();
        auto itr_sk_i64 = sk_i64_index.require_find(sk_i64_id);
        sk_i64_index.modify(itr_sk_i64, _self, [](auto &row) {
            row.i64 = row.i64 + 1;
        });

        auto sk_i128_id = uint128_t(sk_i128_table.available_primary_key() - 1) + 2;
        auto sk_i128_index = sk_i128_table.template get_index<"ii"_n>();
        auto itr_sk_i128 = sk_i128_index.require_find(sk_i128_id);
        sk_i128_index.modify(itr_sk_i128, _self, [](auto &row) {
            row.i128 = row.i128 + 2;
        });

        auto sk_d64_id = double(sk_d64_table.available_primary_key() - 1) + 3.1;
        auto sk_d64_index = sk_d64_table.template get_index<"d"_n>();
        auto itr_sk_d64 = sk_d64_index.require_find(sk_d64_id);
        sk_d64_index.modify(itr_sk_d64, _self, [](auto &row) {
            row.d64 = row.d64 + 3.2;
        });

        auto sk_d128_id = (long double)(sk_d128_table.available_primary_key() - 1) + 4.6;
        auto sk_d128_index = sk_d128_table.template get_index<"dd"_n>();
        auto itr_sk_d128 = sk_d128_index.require_find(sk_d128_id);
        sk_d128_index.modify(itr_sk_d128, _self, [](auto &row) {
            row.d128 = row.d128 + 4.7;
        });

        uint128_t end = uint128_t(0xFFAABB00DDEE1122) << 64 | uint128_t(0x0033445500FFAA22);
        std::array<uint128_t, 2> words = {(sk_c256_table.available_primary_key() - 1) + 5, end};

        auto sk_c256_id = checksum256(words);
        auto sk_c256_index = sk_c256_table.template get_index<"c"_n>();
        auto itr_sk_c256 = sk_c256_index.require_find(sk_c256_id);
        sk_c256_index.modify(itr_sk_c256, _self, [](auto &row) {
            uint128_t end = uint128_t(0xFFAABB00DDEE1122) << 64 | uint128_t(0x0033445500FFAA22);
            std::array<uint128_t, 2> words = {row.id + 10, end};

            row.c256 = checksum256(words);
        });

        auto sk_multi_id = sk_multi_table.available_primary_key() - 1;
        auto itr_multi = sk_multi_table.require_find(sk_multi_id);
        sk_multi_table.modify(itr_multi, _self, [](auto &row) {
            row.i64 = row.i64 + 1;
            row.i128 = row.i128 + 2;
            row.d64 = row.d64 + 3.2;
            row.d128 = row.d128 + 4.7;
        });
    }
    else if (action == "update.ot"_n)
    {
        auto sk_i64_id = uint64_t(sk_i64_table.available_primary_key() - 1) + 1 + 1;
        auto sk_i64_index = sk_i64_table.template get_index<"i"_n>();
        auto itr_sk_i64 = sk_i64_index.require_find(sk_i64_id);
        sk_i64_index.modify(itr_sk_i64, _self, [](auto &row) {
            row.unrelated = row.id + 1;
        });

        auto sk_i128_id = uint128_t(sk_i128_table.available_primary_key() - 1) + 2 + 2;
        auto sk_i128_index = sk_i128_table.template get_index<"ii"_n>();
        auto itr_sk_i128 = sk_i128_index.require_find(sk_i128_id);
        sk_i128_index.modify(itr_sk_i128, _self, [](auto &row) {
            row.unrelated = row.id + 2;
        });

        auto sk_d64_id = double(sk_d64_table.available_primary_key() - 1) + 3.1 + 3.2;
        auto sk_d64_index = sk_d64_table.template get_index<"d"_n>();
        auto itr_sk_d64 = sk_d64_index.require_find(sk_d64_id);
        sk_d64_index.modify(itr_sk_d64, _self, [](auto &row) {
            row.unrelated = row.id + 3;
        });

        auto sk_d128_id = (long double)(sk_d128_table.available_primary_key() - 1) + 4.6 + 4.7;
        auto sk_d128_index = sk_d128_table.template get_index<"dd"_n>();
        auto itr_sk_d128 = sk_d128_index.require_find(sk_d128_id);
        sk_d128_index.modify(itr_sk_d128, _self, [](auto &row) {
            row.unrelated = row.id + 4;
        });

        uint128_t end = uint128_t(0xFFAABB00DDEE1122) << 64 | uint128_t(0x0033445500FFAA22);
        std::array<uint128_t, 2> words = {(sk_c256_table.available_primary_key() - 1) + 10, end};

        auto sk_c256_id = checksum256(words);
        auto sk_c256_index = sk_c256_table.template get_index<"c"_n>();
        auto itr_sk_c256 = sk_c256_index.require_find(sk_c256_id);
        sk_c256_index.modify(itr_sk_c256, _self, [](auto &row) {
            row.unrelated = row.id + 5;
        });

        auto sk_multi_id = sk_multi_table.available_primary_key() - 1;
        auto itr_multi = sk_multi_table.require_find(sk_multi_id);
        sk_multi_table.modify(itr_multi, _self, [](auto &row) {
            row.unrelated = row.id + 6;
        });
    }
    else if (action == "remove"_n)
    {
        auto sk_i64_id = uint64_t(sk_i64_table.available_primary_key() - 1) + 1 + 1;
        auto sk_i64_index = sk_i64_table.template get_index<"i"_n>();
        auto itr_sk_i64 = sk_i64_index.require_find(sk_i64_id);
        sk_i64_index.erase(itr_sk_i64);

        auto sk_i128_id = uint128_t(sk_i128_table.available_primary_key() - 1) + 2 + 2;
        auto sk_i128_index = sk_i128_table.template get_index<"ii"_n>();
        auto itr_sk_i128 = sk_i128_index.require_find(sk_i128_id);
        sk_i128_index.erase(itr_sk_i128);

        auto sk_d64_id = double(sk_d64_table.available_primary_key() - 1) + 3.1 + 3.2;
        auto sk_d64_index = sk_d64_table.template get_index<"d"_n>();
        auto itr_sk_d64 = sk_d64_index.require_find(sk_d64_id);
        sk_d64_index.erase(itr_sk_d64);

        auto sk_d128_id = (long double)(sk_d128_table.available_primary_key() - 1) + 4.6 + 4.7;
        auto sk_d128_index = sk_d128_table.template get_index<"dd"_n>();
        auto itr_sk_d128 = sk_d128_index.require_find(sk_d128_id);
        sk_d128_index.erase(itr_sk_d128);

        uint128_t end = uint128_t(0xFFAABB00DDEE1122) << 64 | uint128_t(0x0033445500FFAA22);
        std::array<uint128_t, 2> words = {(sk_c256_table.available_primary_key() - 1) + 10, end};

        auto sk_c256_id = checksum256(words);
        auto sk_c256_index = sk_c256_table.template get_index<"c"_n>();
        auto itr_sk_c256 = sk_c256_index.require_find(sk_c256_id);
        sk_c256_index.erase(itr_sk_c256);

        auto sk_multi_id = sk_multi_table.available_primary_key() - 1;
        auto itr_multi = sk_multi_table.require_find(sk_multi_id);
        sk_multi_table.erase(itr_multi);
    }
    else
    {
        eosio::check(false, "The action must be one of insert, update.ot, update.sk or remove");
    }
}