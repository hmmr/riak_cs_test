%% ---------------------------------------------------------------------
%%
%% Copyright (c) 2007-2016 Basho Technologies, Inc.  All Rights Reserved.
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
-module(rtcs_exec).
-compile(export_all).
-compile(nowarn_export_all).

start_cs_and_stanchion_nodes(NodeList, Vsn) ->
    lists:map(fun({_CSNode, RiakNode, _Stanchion}) ->
                      N = rtdev:node_id(RiakNode),
                      start_stanchion(Vsn),
                      start_cs(N, Vsn);
                 ({_CSNode, RiakNode}) ->
                      N = rtcs_dev:node_id(RiakNode),
                      start_cs(N, Vsn)
              end, NodeList).

stop_cs_and_stanchion_nodes(NodeList, Vsn) ->
    lists:map(fun({CSNode, RiakNode, Stanchion}) ->
                      N = rtcs_dev:node_id(RiakNode),
                      stop_cs(N, Vsn),
                      stop_stanchion(Vsn),
                      rt:wait_until_unpingable(CSNode),
                      rt:wait_until_unpingable(Stanchion);
                 ({CSNode, RiakNode}) ->
                      N = rtcs_dev:node_id(RiakNode),
                      stop_cs(N, Vsn),
                      rt:wait_until_unpingable(CSNode)
              end, NodeList).

start_all_nodes(NodeList, Vsn) ->
    lists:map(fun({CSNode, RiakNode, _Stanchion}) ->
                      N = rtdev:node_id(RiakNode),
                      rtdev:run_riak(N, rtcs_dev:relpath(
                                          rtdev:node_version(
                                            rtdev:node_id(RiakNode))), "start"),
                      rt:wait_for_service(RiakNode, riak_kv),
                      start_stanchion(Vsn),
                      start_cs(CSNode, Vsn);
                 ({CSNode, RiakNode}) ->
                      N = rtcs_dev:node_id(RiakNode),
                      rtdev:run_riak(N, rtcs_dev:relpath(rtcs_dev:node_version(N)), "start"),
                      rt:wait_for_service(RiakNode, riak_kv),
                      start_cs(CSNode, Vsn)
              end, NodeList).

stop_all_nodes(NodeList, Vsn) ->
    lists:map(fun({CSNode, RiakNode, Stanchion}) ->
                      stop_cs(CSNode, Vsn),
                      stop_stanchion(Vsn),
                      rtcs_dev:stop(RiakNode),
                      rt:wait_until_unpingable(CSNode),
                      rt:wait_until_unpingable(Stanchion),
                      rt:wait_until_unpingable(RiakNode);
                 ({CSNode, RiakNode}) ->
                      stop_cs(CSNode, Vsn),
                      rtcs_dev:stop(RiakNode),
                      rt:wait_until_unpingable(CSNode),
                      rt:wait_until_unpingable(RiakNode)
              end, NodeList).

start_cs(N) -> start_cs(N, current).

start_cs(N, Vsn) ->
    Exec = node_executable(N, Vsn),
    lager:info("Running ~s start", [Exec]),
    R = os:cmd(Exec ++ " start"),
    rtcs:maybe_load_intercepts(N),
    R.

stop_cs(N) -> stop_cs(N, current).

stop_cs(N, Vsn) ->
    Exec = node_executable(N, Vsn),
    lager:info("Running ~s stop", [Exec]),
    os:cmd(Exec ++ " stop").


node_executable(Node) ->
    node_executable(Node, current).
node_executable(Node, Vsn) ->
    NodePath = rtcs_dev:node_path(Node, Vsn),
    WhichRiak = rtdev:which_riak(rtcs_dev:cluster_devpath(Node, Vsn)),
    lists:flatten(io_lib:format("~s/bin/~s", [NodePath, WhichRiak])).


riakcmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s ~s", [riak_binpath(Path, N), Cmd])).

riakcscmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s ~s", [riakcs_binpath(Path, N), Cmd])).

riakcs_statuscmd(Path, N) ->
    lists:flatten(io_lib:format("~s-admin status", [riakcs_binpath(Path, N)])).

riakcs_switchcmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s-admin stanchion ~s", [riakcs_binpath(Path, N), Cmd])).

riakcs_gccmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s-admin gc ~s", [riakcs_binpath(Path, N), Cmd])).

riakcs_accesscmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s-admin access ~s", [riakcs_binpath(Path, N), Cmd])).

riakcs_storagecmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s-admin storage ~s", [riakcs_binpath(Path, N), Cmd])).

riakcs_debugcmd(Path, N, Cmd) ->
    lists:flatten(io_lib:format("~s-debug ~s", [riakcs_binpath(Path, N), Cmd])).

stanchioncmd(Path, Cmd) ->
    lists:flatten(io_lib:format("~s ~s", [stanchion_binpath(Path), Cmd])).

stanchion_statuscmd(Path) ->
    lists:flatten(io_lib:format("~s-admin status", [stanchion_binpath(Path)])).

riak_bitcaskroot(Prefix, N) ->
    io_lib:format("~s/dev/dev~b/data/bitcask", [Prefix, N]).

riak_binpath(Prefix, N) ->
    io_lib:format("~s/dev/dev~b/bin/riak", [Prefix, N]).

riakcs_home(Prefix, N) ->
    io_lib:format("~s/dev/dev~b/riak-cs", [Prefix, N]).

riakcs_binpath(Prefix, N) ->
    io_lib:format("~s/dev/dev~b/riak-cs/bin/riak-cs", [Prefix, N]).

riakcs_etcpath(Prefix, N) ->
    io_lib:format("~s/dev/dev~b/riak-cs/etc", [Prefix, N]).

riakcs_libpath(Prefix, N) ->
    io_lib:format("~s/dev/dev~b/riak-cs/lib", [Prefix, N]).

riakcs_logpath(Prefix, N, File) ->
    io_lib:format("~s/dev/dev~b/riak-cs/log/~s", [Prefix, N, File]).

stanchion_binpath(Prefix) ->
    io_lib:format("~s/dev/stanchion/bin/stanchion", [Prefix]).

stanchion_etcpath(Prefix) ->
    io_lib:format("~s/dev/stanchion/etc", [Prefix]).

repair_gc_bucket(N, Options) -> repair_gc_bucket(N, Options, current).

repair_gc_bucket(N, Options, Vsn) ->
    Prefix = rtcs_config:devpath(cs, Vsn),
    RepairScriptWild = string:join([riakcs_libpath(Prefix, N), "riak_cs*",
                                    "priv/tools/repair_gc_bucket.erl"] , "/"),
    [RepairScript] = filelib:wildcard(RepairScriptWild),
    Cmd = riakcscmd(Prefix, N, "escript " ++ RepairScript ++
                        " " ++ Options),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

exec_priv_escript(N, Command, Options) ->
    exec_priv_escript(N, Command, Options, cs).

exec_priv_escript(N, Command, Options, ByWhom) ->
    ExecuterPrefix = rtcs_config:devpath(ByWhom, current),
    EscriptPath = filename:join(["priv", "tools", "internal", Command]),
    Cmd = case ByWhom of
              cs ->
                  riakcscmd(ExecuterPrefix, N, "escript " ++ EscriptPath ++ " " ++ Options);
              riak ->
                  riakcmd(ExecuterPrefix, N, "escript " ++ EscriptPath ++ " " ++ Options)
          end,
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

switch_stanchion_cs(N, Host, Port) -> switch_stanchion_cs(N, Host, Port, current).

switch_stanchion_cs(N, Host, Port, Vsn) ->
    SubCmd = io_lib:format("switch ~s ~p", [Host, Port]),
    Cmd = riakcs_switchcmd(rtcs_config:devpath(cs, Vsn), N, SubCmd),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

show_stanchion_cs(N) -> show_stanchion_cs(N, current).

show_stanchion_cs(N, Vsn) ->
    Cmd = riakcs_switchcmd(rtcs_config:devpath(cs, Vsn), N, "show"),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

start_stanchion() -> start_stanchion(current).

start_stanchion(Vsn) ->
    Cmd = stanchioncmd(rtcs_config:devpath(stanchion, Vsn), "start"),
    lager:info("Running ~s", [Cmd]),
    R = os:cmd(Cmd),
    rtcs:maybe_load_intercepts(rtcs:stanchion_node()),
    R.

stop_stanchion() -> stop_stanchion(current).

stop_stanchion(Vsn) ->
    Cmd = stanchioncmd(rtcs_config:devpath(stanchion, Vsn), "stop"),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

flush_access(N) -> flush_access(N, current).

flush_access(N, Vsn) ->
    Cmd = riakcs_accesscmd(rtcs_config:devpath(cs, Vsn), N, "flush"),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

gc(N, SubCmd) -> gc(N, SubCmd, current).

gc(N, SubCmd, Vsn) ->
    Cmd = riakcs_gccmd(rtcs_config:devpath(cs, Vsn), N, SubCmd),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

calculate_storage(N) -> calculate_storage(N, current).

calculate_storage(N, Vsn) ->
    Cmd = riakcs_storagecmd(rtcs_config:devpath(cs, Vsn), N, "batch -r"),
    lager:info("Running ~s", [Cmd]),
    os:cmd(Cmd).

enable_proxy_get(SrcN, Vsn, SinkCluster) ->
    rtdev:run_riak_repl(SrcN, rtcs_config:devpath(riak, Vsn),
                        "proxy_get enable " ++ SinkCluster).

disable_proxy_get(SrcN, Vsn, SinkCluster) ->
    rtdev:run_riak_repl(SrcN, rtcs_config:devpath(riak, Vsn),
                        "proxy_get disable " ++ SinkCluster).

%% TODO: this is added as riak-1.4 branch of riak_test/src/rtcs_dev.erl
%% throws out the return value. Let's get rid of these functions when
%% we entered to Riak CS 2.0 dev, updating to riak_test master branch
cmd(Cmd, Opts) ->
    cmd(Cmd, Opts, rt_config:get(rt_max_wait_time)).

cmd(Cmd, Opts, WaitTime) ->
    lager:info("Command: ~s", [Cmd]),
    lager:info("Options: ~p", [Opts]),
    Port = open_port({spawn_executable, Cmd},
                     [in, exit_status, binary,
                      stream, stderr_to_stdout,{line, 200} | Opts]),
    get_cmd_result(Port, WaitTime).

get_cmd_result(Port, WaitTime) ->
    receive
        {Port, {data, {Flag, Line}}} when Flag =:= eol orelse Flag =:= noeol ->
            lager:info(Line),
            get_cmd_result(Port, WaitTime);
        {Port, {exit_status, 0}} ->
            ok;
        {Port, {exit_status, Status}} ->
            {error, {exit_status, Status}};
        {Port, Other} ->
            lager:warning("Other data from port: ~p", [Other]),
            get_cmd_result(Port, WaitTime)
    after WaitTime ->
            {error, timeout}
    end.
