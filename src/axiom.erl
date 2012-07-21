-module(axiom).
-export([start/1, init/3, handle/2, terminate/2]).
-record(state, {handler}).

-include_lib("cowboy/include/http.hrl").
-include_lib("axiom/include/response.hrl").

start(Handler) ->
	start(Handler, []).

start(Handler, Options) ->
	application:start(cowboy),
	application:load(axiom),
	Dispatch = [{get_option(host, Options), [{get_option(path, Options), ?MODULE, [Handler]}]}],
	cowboy:start_listener(
		axiom_listener,
		get_option(nb_acceptors, Options),
		cowboy_tcp_transport, [{port, get_option(port, Options)}],
		cowboy_http_protocol, [{dispatch, Dispatch}]
	).

init({tcp, http}, Req, [Handler]) ->
	{ok, Req, #state{handler = Handler}}.

terminate(_Req, _State) ->
    ok.

get_option(Opt, Options) ->
	case proplists:get_value(Opt, Options) of
		undefined -> application:get_env(?MODULE, Opt);
		Else -> Else
	end.

handle(Req, State) ->
	Request = [{params,
			element(1, cowboy_http_req:body_qs(Req)) ++
			element(1, cowboy_http_req:qs_vals(Req))} |
		lists:zip(record_info(fields, http_req), tl(tuple_to_list(Req)))],
	Method = proplists:get_value(method, Request),
	Path = proplists:get_value(path, Request),
	Handler = State#state.handler,
	Resp = try
		process_response(Handler:handle(Method, Path, Request))
	catch
		error:function_clause ->
			#response{status = 404, body = <<"<h1>404 - Not Found</h1>">>}
	end,
	{ok, Response} = cowboy_http_req:reply(Resp#response.status,
		Resp#response.headers, Resp#response.body, Req),
	{ok, Response, State}.

process_response(Resp) when is_binary(Resp) ->
	#response{body=Resp};

process_response(Resp) when is_tuple(Resp) ->
	Resp;

process_response(Resp) when is_list(Resp) ->
	Status = case proplists:get_value(status, Resp) of
		undefined -> #response.status;
		S when is_integer(S) -> S
	end,
	Headers = case proplists:get_value(headers, Resp) of
		undefined -> #response.headers;
		H when is_list(H) -> H
	end,
	Body = case proplists:get_value(body, Resp) of
		undefined -> #response.body;
		B when is_binary(B) -> B
	end,
	#response{status = Status, headers = Headers, body = Body}.

