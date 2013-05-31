%%%-------------------------------------------------------------------
%%% @author Juan Jose Comellas <juanjo@comellas.org>
%%% @copyright (C) 2011-2012 Juan Jose Comellas
%%% @doc MercadoLibre API module to export results to files.
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(mlapi_export).
-author('Juan Jose Comellas <juanjo@comellas.org>').

-include("include/mlapi.hrl").

-export([search/3, my_orders/3]).

%% Limit imposed my MLAPI when returning paged results.
-define(DEFAULT_OFFSET, 0).
-define(DEFAULT_LIMIT, 50).
-define(DEFAULT_FORMAT, json).

-type paging_scheme()                           :: search | orders.
-type format()                                  :: json | csv.
-type option()                                  :: {paging_scheme, paging_scheme()} |
                                                   {include_nickname, boolean()} |
                                                   {format, format()} |
                                                   {offset, mlapi_offset()} |
                                                   {limit, mlapi_limit()}.


-spec search(file:filename() | file:io_device(), [mlapi_site_id()], [option()]) -> ok | {error, Reason :: term()} | no_return().
search(Filename, Args, Options) when is_list(Filename) ->
    {ok, File} = file:open(Filename, [write, binary]),
    Result = search(File, Args, Options),
    ok = file:close(File),
    Result;
search(File, [SiteId], Options) ->
    CacheArgs = filter_options(Options, [nickname, seller_id, category, q]),
    CacheOpts = filter_options(Options, [refresh]),
    FetchPage = fun (Offset, Limit) -> mlapi_cache:search(SiteId, [{offset, Offset}, {limit, Limit} | CacheArgs],
                                                          [{output_format, json_term}, {date_format, iso8601} | CacheOpts]) end,
    IncludeNickname = proplists:get_value(include_nickname, Options, false),
    FormatDoc = case proplists:get_value(format, Options, json) of
                    csv ->
                        case IncludeNickname of
                            true  -> fun encode_search_as_csv_with_nickname/2;
                            false -> fun encode_search_as_csv/2
                        end;
                    json ->
                        fun encode_ejson/2
                end,
    fetch_paged_response(File, FetchPage, FormatDoc, [{paging_scheme, search} | Options]).


-spec encode_search_as_csv(mlapi_pager:position(), mlapi:ejson()) -> iolist().
encode_search_as_csv(Position, Doc) when Position =:= first; Position =:= {first, last} ->
    Headers = [
               <<"ID">>, <<"Cantidad Vendida">>, <<"Precio">>, <<"Moneda">>, <<"Vendedor">>,
               <<"Tipo Publicacion">>, <<"Titulo">>, <<"Subtitulo">>, <<"Vencimiento">>, <<"Permalink">>
              ],
    [line_to_csv(Headers), encode_search_as_csv(Doc)];
encode_search_as_csv(_Position, Doc) ->
    encode_search_as_csv(Doc).

-spec encode_search_as_csv(mlapi:ejson()) -> iolist().
encode_search_as_csv(Doc) ->
    ItemFieldNames =
      [
       <<"id">>, <<"sold_quantity">>, <<"price">>, <<"currency_id">>, <<"seller.id">>,
       <<"listing_type_id">>, <<"title">>, <<"subtitle">>, <<"stop_time">>, <<"permalink">>
      ],
    line_to_csv([kvc:path(Name, Doc) || Name <- ItemFieldNames]).


%% @doc Return the CSV line corresponding to the JSON document to be exported
%%      including the nickname corresponding to the seller ID
-spec encode_search_as_csv_with_nickname(mlapi_pager:position(), mlapi:ejson()) -> iolist().
encode_search_as_csv_with_nickname(Position, Doc) when Position =:= first; Position =:= {first, last} ->
    Headers = [
               <<"ID">>, <<"Cantidad Vendida">>, <<"Precio">>, <<"Moneda">>, <<"Vendedor">>, <<"ID Vendedor">>,
               <<"Tipo Publicacion">>, <<"Titulo">>, <<"Subtitulo">>, <<"Vencimiento">>, <<"Permalink">>
              ],
    [line_to_csv(Headers), encode_search_as_csv_with_nickname(Doc)];
encode_search_as_csv_with_nickname(_Position, Doc) ->
    encode_search_as_csv_with_nickname(Doc).

-spec encode_search_as_csv_with_nickname(mlapi:ejson()) -> iolist().
encode_search_as_csv_with_nickname(Doc) ->
    SellerId = kvc:path([<<"seller">>, <<"id">>], Doc),
    Nickname = seller_nickname(SellerId),
    Items =
      [
       kvc:path(<<"id">>, Doc), kvc:path(<<"sold_quantity">>, Doc),
       kvc:path(<<"price">>, Doc), kvc:path(<<"currency_id">>, Doc),
       Nickname, SellerId,
       kvc:path(<<"listing_type_id">>, Doc), kvc:path(<<"title">>, Doc),
       kvc:path(<<"subtitle">>, Doc), kvc:path(<<"stop_time">>, Doc),
       kvc:path(<<"permalink">>, Doc)
      ],
    line_to_csv(Items).


seller_nickname(SellerId) when is_integer(SellerId) ->
    case mlapi_cache:user(SellerId) of
        {error, _Reason} ->
            <<>>;
        User ->
            case kvc:path(<<"nickname">>, User) of
                Nickname when is_binary(Nickname) ->
                    Nickname;
                _Error ->
                    <<>>
            end
    end.


-spec my_orders(file:filename() | file:io_device(), [], [option()]) -> ok | {error, Reason :: term()}.
my_orders(Filename, Args, Options) when is_list(Filename) ->
    {ok, File} = file:open(Filename, [write, binary]),
    Result = my_orders(File, Args, Options),
    ok = file:close(File),
    Result;
my_orders(File, [], Options) ->
    CacheArgs = filter_options(Options, [access_token, feedback_status, payment_status, seller, shipping_status, sort]),
    CacheOpts = filter_options(Options, [refresh]),
    FetchPage = fun (Offset, Limit) -> mlapi_cache:my_orders([{offset, Offset}, {limit, Limit} | CacheArgs],
                                                             [{output_format, json_term}, {date_format, iso8601} | CacheOpts]) end,
    FormatDoc = case proplists:get_value(format, Options) of
                    csv  -> fun encode_order_as_csv/2;
                    json -> fun encode_ejson/2
                end,
    fetch_paged_response(File, FetchPage, FormatDoc, [{paging_scheme, orders} | Options]).


-spec encode_order_as_csv(mlapi_pager:position(), mlapi:ejson()) -> iolist().
encode_order_as_csv(Position, Doc) when Position =:= first; Position =:= {first, last} ->
    Headers = [
               <<"ID">>, <<"Fecha Oferta">>,
               <<"Apodo Comprador">>, <<"Nombre Comprador">>, <<"Email Comprador">>, <<"Telefono Comprador">>,
               <<"Fecha Calificacion">>, <<"Estado Calificacion">>,
               <<"ID Item">>, <<"Titulo">>, <<"Cantidad">>, <<"Precio Unitario">>, <<"Moneda">>
              ],
    [line_to_csv(Headers), encode_order_as_csv(Doc)];
encode_order_as_csv(_Position, Doc) ->
    encode_order_as_csv(Doc).


-spec encode_order_as_csv(mlapi:ejson()) -> iolist().
encode_order_as_csv(Order) ->
    Buyer = kvc:path(<<"buyer">>, Order),
    FirstName = kvc:path(<<"first_name">>, Buyer),
    LastName = kvc:path(<<"last_name">>, Buyer),
    Phone = case kvc:path(<<"phone.area_code">>, Buyer) of
                AreaCode when is_atom(AreaCode); AreaCode =:= <<>>; AreaCode =:= <<" ">> ->
                    bstr:bstr(kvc:path(<<"phone.number">>, Buyer));
                AreaCode ->
                    Number = bstr:bstr(kvc:path(<<"phone.number">>, Buyer)),
                    <<$(, AreaCode/binary, ") ", Number/binary>>
            end,
    Feedback = kvc:path(<<"feedback.sent">>, Order),
    ReversedLine1 = [
                     kvc:path(<<"concretion_status">>, Feedback),
                     kvc:path(<<"date_created">>, Feedback),
                     Phone,
                     kvc:path(<<"email">>, Buyer),
                     <<FirstName/binary, " ", LastName/binary>>,
                     kvc:path(<<"nickname">>, Buyer),
                     kvc:path(<<"date_created">>, Order),
                     kvc:path(<<"id">>, Order)
                    ],
    ItemFieldNames = [<<"item.id">>, <<"item.title">>, <<"quantity">>, <<"unit_price">>, <<"currency_id">>],
    Line = case kvc:path(<<"order_items">>, Order) of
               [Item] ->
                   lists:foldl(fun (Path, Acc1) -> [kvc:path(Path, Item) | Acc1] end, ReversedLine1, ItemFieldNames);
               [] ->
                   ReversedLine1
           end,
    reversed_line_to_csv(Line).


-spec encode_ejson(mlapi_pager:position(), mlapi:ejson()) -> iolist().
encode_ejson(first, Doc) ->
    [<<"[\n">>, jsx:encode(Doc), <<",\n">>];
encode_ejson({first, last}, Doc) ->
    [<<"[\n">>, jsx:encode(Doc), <<"\n]\n">>];
encode_ejson(middle, Doc) ->
    [jsx:encode(Doc), <<",\n">>];
encode_ejson(last, Doc) ->
    [jsx:encode(Doc), <<"\n]\n">>].


-spec fetch_paged_response(file:io_device(), FetchPage :: fun(), FormatDoc :: fun(), [option()]) -> ok | mlapi:error().
fetch_paged_response(File, FetchPage, FormatDoc, Options) when is_function(FetchPage), is_function(FormatDoc) ->
    PagingScheme = proplists:get_value(paging_scheme, Options),
    Offset       = proplists:get_value(offset, Options, ?DEFAULT_OFFSET),
    Limit        = proplists:get_value(limit, Options, ?DEFAULT_LIMIT),
    {ok, Pager}  = mlapi_pager:start_link([{paging_scheme, PagingScheme}, {fetch_page, FetchPage}, {offset, Offset}, {limit, Limit}]),
    fetch_pages(File, Pager, FormatDoc).


-spec fetch_pages(file:io_device(), Pager :: pid(), FormatDoc :: fun()) -> ok | mlapi:error().
fetch_pages(File, Pager, FormatDoc) ->
    case mlapi_pager:next(Pager) of
        {error, _Reason} = Error ->
            Error;
        {Position, Page} ->
            case kvc:path(<<"results">>, Page) of
                [] ->
                    {error, {results_not_found, Page}};
                Results ->
                    ok = write_page(File, Position, FormatDoc, Results),
                    if
                        Position =:= first orelse Position =:= middle ->
                            fetch_pages(File, Pager, FormatDoc);
                        true ->
                            ok
                    end
            end
    end.


%% @doc Write a page of results from MLAPI to disk, formatting them before before
%%      writing them. When called, the formatting function FormatDoc is told whether
%%      the document is the first one (first), one in the middle (middle) or the last
%%      one (last). If there is only one document the formatting function is told
%%      that it is the first and last one at the same time ({first, last}).
-spec write_page(file:io_device(), mlapi_pager:position(), FormatDoc :: fun(), [mlapi:ejson()]) -> ok | {error, Reason :: term()}.
write_page(File, {first, last}, FormatDoc, [Head]) ->
    %% A single page with a single element.
    ok = file:write(File, FormatDoc({first, last}, Head));
write_page(File, {first, last}, FormatDoc, [Head | Tail]) ->
    %% A single page with multiple elements.
    ok = file:write(File, FormatDoc(first, Head)),
    write_last_page(File, FormatDoc, Tail);
write_page(File, first, FormatDoc, [Head | Tail]) ->
    ok = file:write(File, FormatDoc(first, Head)),
    write_middle_page(File, FormatDoc, Tail);
write_page(File, last, FormatDoc, Results) ->
    write_last_page(File, FormatDoc, Results);
write_page(File, middle, FormatDoc, Results) ->
    write_middle_page(File, FormatDoc, Results).


-spec write_middle_page(file:io_device(), FormatDoc :: fun(), [mlapi:ejson()]) -> ok | {error, Reason :: term()}.
write_middle_page(File, FormatDoc, [Head | Tail]) ->
    ok = file:write(File, FormatDoc(middle, Head)),
    write_middle_page(File, FormatDoc, Tail);
write_middle_page(_File, _FormatDoc, []) ->
    ok.


-spec write_last_page(file:io_device(), FormatDoc :: fun(), [mlapi:ejson()]) -> ok | {error, Reason :: term()}.
write_last_page(File, FormatDoc, [Head]) ->
    ok = file:write(File, FormatDoc(last, Head));
write_last_page(File, FormatDoc, [Head | Tail]) ->
    ok = file:write(File, FormatDoc(middle, Head)),
    write_last_page(File, FormatDoc, Tail).


-spec filter_options([tuple()], [atom()]) -> [tuple()].
filter_options(Options, ValidNames) ->
    [Option || {Name, _Value} = Option <- Options, lists:member(Name, ValidNames)].


-spec line_to_csv([term()]) -> iolist().
line_to_csv(Line) ->
    line_to_csv(Line, []).

line_to_csv([Value | Tail], Acc) when is_number(Value); is_boolean(Value) ->
    %% Numbers and booleans don't carry double quotes around them.
    line_to_csv(Tail, [$,, mlapi:to_binary(Value) | Acc]);
line_to_csv([Value | Tail], Acc) ->
    line_to_csv(Tail, [$,, $", mlapi:to_binary(Value), $" | Acc]);
line_to_csv([], Acc) ->
    lists:reverse([$\n | tl(Acc)]).


-spec reversed_line_to_csv([term()]) -> iolist().
reversed_line_to_csv(Line) ->
    reversed_line_to_csv(Line, [$\n]).

reversed_line_to_csv([Field | Tail], Acc) when is_number(Field); is_boolean(Field) ->
    %% Numbers and booleans don't carry double quotes around them.
    reversed_line_to_csv(Tail, [$,, mlapi:to_binary(Field) | Acc]);
reversed_line_to_csv([Field | Tail], Acc) ->
    reversed_line_to_csv(Tail, [$,, $", mlapi:to_binary(Field), $" | Acc]);
reversed_line_to_csv([], Acc) ->
    tl(Acc).
