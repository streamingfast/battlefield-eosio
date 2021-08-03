#pragma once

// #ifndef CONTRACT_NAME
//     static_assert(false, "The CONTRACT_NAME define should have been set by build system, aborting");
// #endif

#include <algorithm>
#include <string>
#include <variant>

#include <eosio/eosio.hpp>
#include <eosio/crypto.hpp>
#include <eosio/asset.hpp>
#include <eosio/time.hpp>
#include <eosio/transaction.hpp>

using eosio::action;
using eosio::action_wrapper;
using eosio::asset;
using eosio::cancel_deferred;
using eosio::check;
using eosio::checksum256;
using eosio::const_mem_fun;
using eosio::contract;
using eosio::current_time_point;
using eosio::datastream;
using eosio::indexed_by;
using eosio::name;
using eosio::onerror;
using eosio::permission_level;
using eosio::print;
using eosio::time_point_sec;
using std::function;
using std::string;

class [[eosio::contract("battlefield")]] battlefield : public contract
{
public:
    typedef std::variant<uint16_t, string> varying_action;

    battlefield(name receiver, name code, datastream<const char *> ds)
        : contract(receiver, code, ds) {}

    [[eosio::action]] void
    dbins(name account);

    [[eosio::action]] void dbinstwo(name account, uint64_t first, uint64_t second);

    [[eosio::action]] void dbupd(name account);

    [[eosio::action]] void dbrem(name account);

    [[eosio::action]] void dbremtwo(name account, uint64_t first, uint64_t second);

    [[eosio::action]] void dtrx(
        name account,
        bool fail_now,
        bool fail_later,
        bool fail_later_nested,
        uint32_t delay_sec,
        string nonce);

    [[eosio::action]] void dtrxcancel(name account);

    [[eosio::action]] void dtrxexec(name account, bool fail, bool failNested, string nonce);

    [[eosio::action]] void nestdtrxexec(bool fail);

    [[eosio::action]] void nestonerror(bool fail);

    [[eosio::action]] void varianttest(varying_action value);

    [[eosio::action]] void producerows(uint64_t row_count);

    [[eosio::action]] void sktest(name action);

#if WITH_ONERROR_HANDLER == 1
    [[eosio::on_notify("eosio::onerror")]] void onerror(eosio::onerror data);
#endif

    /**
         * We are going to replicate the following creation order:
         *
         * ```
         * Legend:
         *  - a | Root Action
         *  - n | Notification (require_recipient)
         *  - c | Context Free Action Inline (send_context_free_inline)
         *  - i | Inline (send_inline)
         *
         *   Creation Tree
         *   a1
         *   ├── n1
         *   ├── i2
         *   |   ├── n4
         *   |   ├── n5
         *   |   ├── i3
         *   |   └── c3
         *   ├── n2
         *   |   ├── i1
         *   |   ├── c1
         *   |   └── n3
         *   └── c2
         *
         *   Execution Tree
         *   a1
         *   ├── n1
         *   ├── n2
         *   ├── n3
         *   ├── c2
         *   ├── c1
         *   ├── i2
         *   |   ├── n4
         *   |   ├── n5
         *   |   ├── c3
         *   |   └── i3
         *   └── i1
         * ```
         *
         * Consumer will pass the following information to create the hierarchy:
         *  - n1 The account notified in n1, must not have a contract
         *  - n2 The account notified in n2, must be an account with the
         *       battlefield account installed on it. Will accept the notification
         *       and will create i1, c1 and n3.
         *  - n3 The account notified in n3, must not have a contract, accessible
         *       through the notificiation of n2 (same context).
         *  - n4 The account notified in n4, must not have a contract
         *  - n5 The account notified in n5, must not have a contract
         *
         * The i1 and i3 will actually execute `inlineempty` with a tag of `"i1"`
         * and `"i3"` respectively.
         *
         * The c1, c2 and c3 will actually execute `eosio.null::nonce` with the
         * nonce being set to string `c1`, `c2` and `c3` respectively (which
         * renders as `026331`, `026332` and `026333` respectively in the
         * execution traces).
         *
         * The i2 will actually `require_recipient(n4)` and
         * `require_recipient(n5)` followed by a `inlineempty` with a tag of
         * `"i3"` and send `c3`
         */
    [[eosio::action]] void creaorder(name n1, name n2, name n3, name n4, name n5);

    [[eosio::on_notify("battlefield1::creaorder")]] void on_creaorder(name n1, name n2, name n3, name n4, name n5);

    [[eosio::action]] void inlineempty(string tag, bool fail);

    [[eosio::action]] void inlinedeep(
        string tag,
        name n4,
        name n5,
        string nestedInlineTag,
        bool nestedInlineFail,
        string nestedCfaInlineTag);

    // Inline action wrappers (so we can construct them in code)
    using nestdtrxexec_action = action_wrapper<"nestdtrxexec"_n, &battlefield::nestdtrxexec>;
    using nestonerror_action = action_wrapper<"nestonerror"_n, &battlefield::nestonerror>;
    using inlineempty_action = action_wrapper<"inlineempty"_n, &battlefield::inlineempty>;
    using inlinedeep_action = action_wrapper<"inlinedeep"_n, &battlefield::inlinedeep>;

private:
    struct [[eosio::table]] member_row
    {
        uint64_t id;
        name account;
        asset amount;
        string memo;
        time_point_sec created_at;
        time_point_sec expires_at;

        auto primary_key() const { return id; }
        uint64_t by_account() const { return account.value; }
    };

    typedef eosio::multi_index<
        "member"_n, member_row,
        indexed_by<"byaccount"_n, const_mem_fun<member_row, uint64_t, &member_row::by_account>>>
        members;

    struct [[eosio::table]] variant_row
    {
        uint64_t id;
        std::variant<int8_t, uint16_t, uint32_t, int32_t> variant_field;
        uint64_t creation_number;

        auto primary_key() const { return id; }
    };

    typedef eosio::multi_index<"variant"_n, variant_row> variers;

    // condary_index_db_functions< double >
    // struct secondary_index_db_functions< eosio::fixed_bytes< 32 > >
    // struct secondary_index_db_functions< long double >
    // struct secondary_index_db_functions< uint128_t >
    // struct secondary_index_db_functions< uint64_t >

    struct [[eosio::table]] sk_row
    {
        uint64_t id;
        uint64_t i64;
        uint128_t i128;
        double d64;
        long double d128;
        checksum256 c256;
        uint64_t unrelated;

        auto primary_key() const { return id; }
        uint64_t by_i64() const { return i64; }
        uint128_t by_i128() const { return i128; }
        double by_d64() const { return d64; }
        long double by_d128() const { return d128; }
        checksum256 by_c256() const { return c256; }
    };

    typedef eosio::multi_index<"sk.i"_n, sk_row, indexed_by<"i"_n, const_mem_fun<sk_row, uint64_t, &sk_row::by_i64>>> sk_i64;
    typedef eosio::multi_index<"sk.ii"_n, sk_row, indexed_by<"ii"_n, const_mem_fun<sk_row, uint128_t, &sk_row::by_i128>>> sk_i128;
    typedef eosio::multi_index<"sk.d"_n, sk_row, indexed_by<"d"_n, const_mem_fun<sk_row, double, &sk_row::by_d64>>> sk_d64;
    typedef eosio::multi_index<"sk.dd"_n, sk_row, indexed_by<"dd"_n, const_mem_fun<sk_row, long double, &sk_row::by_d128>>> sk_d128;
    typedef eosio::multi_index<"sk.c"_n, sk_row, indexed_by<"c"_n, const_mem_fun<sk_row, checksum256, &sk_row::by_c256>>> sk_c256;

    typedef eosio::multi_index<"sk.multi"_n, sk_row,
                               indexed_by<"i.1"_n, const_mem_fun<sk_row, uint64_t, &sk_row::by_i64>>,
                               indexed_by<"ii.1"_n, const_mem_fun<sk_row, uint128_t, &sk_row::by_i128>>,
                               indexed_by<"d.1"_n, const_mem_fun<sk_row, double, &sk_row::by_d64>>,
                               indexed_by<"dd.1"_n, const_mem_fun<sk_row, long double, &sk_row::by_d128>>,
                               indexed_by<"c.1"_n, const_mem_fun<sk_row, checksum256, &sk_row::by_c256>>,
                               indexed_by<"i.2"_n, const_mem_fun<sk_row, uint64_t, &sk_row::by_i64>>,
                               indexed_by<"ii.2"_n, const_mem_fun<sk_row, uint128_t, &sk_row::by_i128>>,
                               indexed_by<"d.2"_n, const_mem_fun<sk_row, double, &sk_row::by_d64>>,
                               indexed_by<"dd.2"_n, const_mem_fun<sk_row, long double, &sk_row::by_d128>>,
                               indexed_by<"c.2"_n, const_mem_fun<sk_row, checksum256, &sk_row::by_c256>>,
                               indexed_by<"i.3"_n, const_mem_fun<sk_row, uint64_t, &sk_row::by_i64>>,
                               indexed_by<"ii.3"_n, const_mem_fun<sk_row, uint128_t, &sk_row::by_i128>>,
                               indexed_by<"d.3"_n, const_mem_fun<sk_row, double, &sk_row::by_d64>>,
                               indexed_by<"dd.3"_n, const_mem_fun<sk_row, long double, &sk_row::by_d128>>,
                               indexed_by<"c.3"_n, const_mem_fun<sk_row, checksum256, &sk_row::by_c256>>,
                               indexed_by<"i.4"_n, const_mem_fun<sk_row, uint64_t, &sk_row::by_i64>>>
        sk_multi;
};
