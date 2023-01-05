%% ---------------------------------------------------------------------
%%
%% Copyright (c) 2023 TI Tokyo.  All Rights Reserved.
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
%% ---------------------------------------------------------------------

-module(hosted_stanchion_test).

-export([confirm/0]).

-include_lib("erlcloud/include/erlcloud_aws.hrl").

confirm() ->
    pass = confirm_in_pinned_mode(),
    pass = confirm_in_auto_mode(),
    pass.

confirm_in_auto_mode() ->
    {_Creds, {_RiakNodes, [RCS1, RCS2]}} =
        rtcs:setup(2, cs_config(auto)),
    %% standard setup has stanchion on rcs-dev1

    logger:info("Default setup has stanchion at the node that was brought up first (~s)", [RCS1]),
    ok                = verify_stancion_at_node(RCS1),
    no_stanchion_here = verify_stancion_at_node(RCS2),

    logger:info("Call create_user then verify stanchion is on node ~s", [RCS1]),
    rtcs_admin:create_user(RCS2, 2),
    ok = verify_stancion_at_node(RCS1),

    logger:info("Stop stanchion on ~s", [RCS1]),
    rpc:call(RCS1, stanchion_migration, stop_stanchion_here, []),

    logger:info("Verify that no node is running stanchion", []),
    no_stanchion_here = verify_stancion_at_node(RCS1),
    no_stanchion_here = verify_stancion_at_node(RCS2),

    logger:info("Call create_user again, at node ~s, and verify stanchion is on the same node", [RCS2]),
    rtcs_admin:create_user(RCS2, 3),
    no_stanchion_here = verify_stancion_at_node(RCS1),
    ok                = verify_stancion_at_node(RCS2),

    logger:info("Call create_user at node ~s, and verify stanchion is still on node ~s", [RCS1, RCS2]),
    rtcs_admin:create_user(RCS1, 4),
    no_stanchion_here = verify_stancion_at_node(RCS1),
    ok                = verify_stancion_at_node(RCS2),

    rt:teardown(),

    pass.

confirm_in_pinned_mode() ->
    {{AdminUserConfig, _Id}, {_RiakNodes, [RCS1, RCS2]}} =
        rtcs:setup(2, cs_config(riak_cs_only)),

    logger:info("Default setup has stanchion at the node that was brought up first (~s)", [RCS1]),
    ok                = verify_stancion_at_node(RCS1),
    no_stanchion_here = verify_stancion_at_node(RCS2),

    logger:info("Call create_user then verify stanchion is on node ~s", [RCS1]),
    rtcs_admin:create_user(RCS2, 2),
    ok = verify_stancion_at_node(RCS1),

    logger:info("Stop stanchion on ~s", [RCS1]),
    rpc:call(RCS1, stanchion_migration, stop_stanchion_here, []),

    logger:info("Verify that no node is running stanchion", []),
    no_stanchion_here = verify_stancion_at_node(RCS1),
    no_stanchion_here = verify_stancion_at_node(RCS2),

    %% trying to create a user, causing RCS2 to contact stanchion,
    %% will in turn cause it to try to spin it up locally, which will
    %% fail and bring down the node.
    logger:info("Try create_user at node ~s (port ~b) and see it crash", [RCS2, rtcs_config:cs_port(RCS2)]),
    ok = try_and_fail_create_user(AdminUserConfig#aws_config{s3_port = rtcs_config:cs_port(RCS2)}),
    pong = net_adm:ping(RCS2),

    rt:teardown(),

    pass.

try_and_fail_create_user(UserConfig) ->
    Resource = "/riak-cs/user",
    ReqBody = "{\"email\":\"email@addr.com\", \"name\":\"Name Nameson\"}",
    try
        erlcloud_s3:s3_request(
          UserConfig, post, "", Resource, [], "",
          {ReqBody, "application/json"}, []),
        fail
    catch
        error:{aws_error, {http_error, _S, _, _ResponseBody}} ->
            ok
    end.


verify_stancion_at_node(Node) ->
    case rpc:call(Node, supervisor, which_children, [stanchion_sup]) of
        [] ->
            no_stanchion_here;
        _Children when length(_Children) == 2 ->
            ok
    end.

cs_config(auto) ->
    [{cs, [{riak_cs, [{stanchion_hosting_mode, auto}]}]}];
cs_config(riak_cs_only) ->
    fun({_RiakNodes, [N1, N2]}) ->
            rtcs:set_advanced_conf(N1, [{riak_cs, [{stanchion_hosting_mode, riak_cs_with_stanchion}]}]),
            rtcs:set_advanced_conf(N2, [{riak_cs, [{stanchion_hosting_mode, riak_cs_only}]}])
    end.
