%% -------------------------------------------------------------------
%%
%% backend_test_util: Riak backend test utilities
%%
%% Copyright (c) 2007-2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(backend_test_util).

-include_lib("eunit/include/eunit.hrl").
-compile(export_all).


standard_test(BackendMod, Config) ->
    {spawn,
     [
      {setup,
       local,
       fun() -> setup({BackendMod, Config}) end,
       fun cleanup/1,
       fun(X) ->
               [basic_store_and_fetch(X),
                fold_buckets(X),
                fold_keys(X),
                delete_object(X),
                fold_objects(X),
                empty_check(X)
               ]
       end
      }]}.

make_test_bucket(Backend, Suffix) ->
    try
        Backend:backend_eunit_bucket(Suffix)
    catch error:undef ->
            <<"b", ($0 + Suffix):8>>
    end.

make_test_key(Backend, Suffix) ->
    try
        Backend:backend_eunit_key(Suffix)
    catch error:undef ->
            <<"k", ($0 + Suffix):8>>
    end.

make_bs_and_ks(Backend) ->
    {make_test_bucket(Backend, 1),
     make_test_bucket(Backend, 2),
     make_test_key(Backend, 1),
     make_test_key(Backend, 2)}.

basic_store_and_fetch({Backend, State}) ->
    {B1, B2, K1, K2} = make_bs_and_ks(Backend),
    {"basic store and fetch test",
     fun() ->
             ?assertMatch({ok, _},
                          Backend:put(B1, K1, [], <<"v1">>, State)),
             ?assertMatch({ok, _},
                          Backend:put(B2, K2, [], <<"v2">>, State)),
             ?assertMatch({ok,<<"v2">>, _},
                          Backend:get(B2, K2, State)),
             ?assertMatch({error, not_found, _},
                          Backend:get(B1, <<"k3">>, State))
     end
    }.

fold_buckets({Backend, State}) ->
    {B1, B2, _K1, _K2} = make_bs_and_ks(Backend),
    {"bucket folding test",
     fun() ->
             FoldBucketsFun =
                 fun(Bucket, Acc) ->
                         [Bucket | Acc]
                 end,

             ?assertEqual([B1, B2],
                           begin
                               {ok, Buckets1} =
                                   Backend:fold_buckets(FoldBucketsFun,
                                                        [],
                                                        [],
                                                        State),
                               lists:sort(Buckets1)
                           end)
     end
    }.

fold_keys({Backend, State}) ->
    {B1, B2, K1, K2} = make_bs_and_ks(Backend),
    {"key folding test",
     fun() ->
             FoldKeysFun =
                 fun(Bucket, Key, Acc) ->
                         [{Bucket, Key} | Acc]
                 end,
             FoldKeysFun1 =
                 fun(_Bucket, Key, Acc) ->
                         [Key | Acc]
                 end,
             FoldKeysFun2 =
                 fun(Bucket, Key, Acc) ->
                         case Bucket =:= B1 of
                             true ->
                                 [Key | Acc];
                             false ->
                                 Acc
                         end
                 end,
             FoldKeysFun3 =
                 fun(Bucket, Key, Acc) ->
                         case Bucket =:= B1 of
                             true ->
                                 Acc;
                             false ->
                                 [Key | Acc]
                         end
                 end,

             ?assertEqual([{B1, K1}, {B2, K2}],
                          begin
                              {ok, Keys1} =
                                  Backend:fold_keys(FoldKeysFun,
                                                    [],
                                                    [],
                                                    State),
                              lists:sort(Keys1)
                          end),
             ?assertEqual({ok, [K1]},
                          Backend:fold_keys(FoldKeysFun1,
                                            [],
                                            [{bucket, B1}],
                                            State)),
             ?assertEqual({ok, [K2]},
                          Backend:fold_keys(FoldKeysFun1,
                                            [],
                                            [{bucket, B2}],
                                            State)),
             ?assertEqual({ok, [K1]},
                          Backend:fold_keys(FoldKeysFun2, [], [], State)),
             ?assertEqual({ok, [K1]},
                          Backend:fold_keys(FoldKeysFun2,
                                            [],
                                            [{bucket, B1}],
                                            State)),
             ?assertEqual({ok, [K2]},
                          Backend:fold_keys(FoldKeysFun3, [], [], State)),
             ?assertEqual({ok, []},
                          Backend:fold_keys(FoldKeysFun3,
                                            [],
                                            [{bucket, B1}],
                                            State))
     end
    }.

delete_object({Backend, State}) ->
    {_B1, B2, _K1, K2} = make_bs_and_ks(Backend),
    {"object deletion test",
     fun() ->
             ?assertMatch({ok, _}, Backend:delete(B2, K2, [], State)),
             ?assertMatch({error, not_found, _},
                          Backend:get(B2, K2, State))
     end
    }.

fold_objects({Backend, State}) ->
    {B1, _B2, K1, _K2} = make_bs_and_ks(Backend),
    B3 = make_test_bucket(Backend, 3),
    K3 = make_test_key(Backend, 3),
    ObjFilter = fun(Os) -> [if is_binary(X) -> {BK, X};
                               true         -> {BK, riak_object:get_value(X)}
                            end || {BK, X} <- Os]
                end,
    {"object folding test",
     fun() ->
             FoldKeysFun =
                 fun(Bucket, Key, Acc) ->
                         [{Bucket, Key} | Acc]
                 end,
             FoldObjectsFun =
                 fun(Bucket, Key, Value, Acc) ->
                         [{{Bucket, Key}, Value} | Acc]
                 end,
             ?assertEqual([{B1, K1}],
                          begin
                              {ok, Keys} =
                                  Backend:fold_keys(FoldKeysFun,
                                                    [],
                                                    [],
                                                    State),
                              lists:sort(Keys)
                          end),

             ?assertEqual([{{B1,K1}, <<"v1">>}],
                          begin
                              {ok, Objects1} =
                                  Backend:fold_objects(FoldObjectsFun,
                                                       [],
                                                       [],
                                                       State),
                              lists:sort(ObjFilter(Objects1))
                          end),
             ?assertMatch({ok, _},
                          Backend:put(B3, K3, [], <<"v3">>, State)),
             ?assertEqual([{{B1,K1},<<"v1">>},
                           {{B3,K3},<<"v3">>}],
                          begin
                              {ok, Objects} =
                                  Backend:fold_objects(FoldObjectsFun,
                                                       [],
                                                       [],
                                                       State),
                              lists:sort(ObjFilter(Objects))
                          end)
     end
    }.

empty_check({Backend, State}) ->
    {B1, _B2, K1, _K2} = make_bs_and_ks(Backend),
    B3 = make_test_bucket(Backend, 3),
    K3 = make_test_key(Backend, 3),
    {"is_empty test",
     fun() ->
             ?assertEqual(false, Backend:is_empty(State)),
             ?assertMatch({ok, _}, Backend:delete(B1,K1, [], State)),
             ?assertMatch({ok, _}, Backend:delete(B3,K3, [], State)),
             ?assertEqual(true, Backend:is_empty(State))
     end
    }.

setup({BackendMod, Config}) ->
    %% Start the backend
    {ok, S} = BackendMod:start(42, Config),
    {BackendMod, S}.

cleanup({BackendMod, S}) ->
    ok = BackendMod:stop(S).
