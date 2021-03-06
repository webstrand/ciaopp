:- module(gather_modes, [gather_modes/4, gather_modes_simple/4,
            vartypes_to_modes/2],
        [assertions, nativeprops, datafacts, ciaopp(ciaopp_options)]).

%% A first shot at an input/output modes analysis

%% Works with "standard" analyses and translates inferred modes to directives
%% Directives are interleaved with the predicate definitions,
%% and include also "measure" directives

%% An argument is input if it is ground in every call to the procedure
%% An argument is output if it is not input and it is ground in every
%% successful return from the procedure

:- use_module(ciaopp(infer/infer),              [get_info/5, type2measure/3]).
:- use_module(ciaopp(infer/infer_db),           [inferred/3]).
:- use_module(ciaopp(infer/gather_modes_basic), [translate_to_modes/2, get_metric/2]).
:- if(defined(has_ciaopp_extra)).
:- use_module(resources(res_assrt_defs/resources_lib),
        [get_measures_assrt/2, get_modes_assrt/2]).
:- else.
get_modes_assrt(_,_) :- fail. % (default)
:- endif.

:- use_module(ciaopp(p_unit/program_keys), [first_key/2, null_directive_key/1,
    is_directive/3, is_clause/4, lit_ppkey/3, get_predkey/3,
    predkey_from_sg/2]).
:- use_module(ciaopp(p_unit), [type_of_goal/2, entry_assertion/3]).
:- use_module(ciaopp(p_unit/itf_db), [curr_module/1]).
:- use_module(library(assertions/assrt_lib), [assertion_body/7]).
:- use_module(ciaopp(p_unit/clause_db)).
:- use_module(ciaopp(p_unit/assrt_db)).
:- use_module(library(hiordlib), [maplist/3, maplist/4]).
:- use_module(ciaopp(preprocess_flags), [current_pp_flag/2]).
:- use_module(ciaopp(ciaopp_log), [pplog/2]).

:- use_module(engine(internals), [module_concat/3]).
:- use_module(engine(runtime_control), [module_split/3]).
:- use_module(library(lists),           [member/2, append/3, length/2]).
:- use_module(library(sets),            [ord_member/2]).
:- use_module(library(sort),            [sort/2]).
:- use_module(library(terms_vars),      [varset/2]).
:- use_module(library(vndict),          [create_dict/2]).
:- use_module(library(aggregates)).
:- use_module(library(messages)).
:- use_module(library(terms)).

:- doc(bug, "The predicate add_mode_declaration_/10 has two versions: (a)
gathering mode information by using type information, and (b) gathering
mode information by using mode information. If granularity is used, then it
cannot be gathered from mode information because this info is inferred from
program points and granularity works on a transformed program which does
not preserve the order of those program points. -JNL").

%----------------------------------------------------------------------------

% :- use_package(andprolog).
% TODO: copied from andprolog_ops.pl (fixme)
:- op(950, xfy, [&]).

%--------------------------------------------------------------------------

:- pred gather_modes/4 :: (list * list * list * list) + not_fails.

gather_modes(Cls0, Ds0, Cls, Ds) :-
    findall(ca(ND, DD), gather_cost_args_modes(ND, DD), L),
    maplist((''(ca(ND, DD), ND, DD) :- true), L, Cls3, Ds3),
    append(Cls0, Cls3, Cls4),
    append(Ds0,  Ds3,  Ds4),
    gather_entry_modes(Cls3),
    remove_dead_code(Cls4, Ds4, Cls1, Ds1),
    gather_modes_info(Cls1, Ds1),
    gather_modes_output(Cls1, Ds1, Cls2, Ds2),
    gather_measures(Cls2, Ds2, Cls, Ds).

usable_status(true).
usable_status(trust).

gather_cost_args_modes(NewDirect, DD) :-
    usable_status(Status),
    assertion_read(Pred, _, Status, comp, Body, _, _, _, _),
    assertion_body(Pred, _, _Call, _, Comp, _, Body),
    ( member('resources_props:cost_args'(_Goal, Modes), Comp) ->
        functor(Pred, F, A),
        mode_declaration(F, A, Modes, _K, NewDirect, DD)
    ).

gather_modes_simple(Cls0, Ds0, Cls, Ds) :-
    gather_entry_modes(Cls0),
    gather_modes_info(Cls0, Ds0),
    gather_modes_output(Cls0, Ds0, Cls, Ds).

gather_entry_modes(Cls) :-
    entry_assertion(Goal, _, _),
    functor(Goal, F, A),
    \+ member(directive(mode(F/A, _)) :_Key, Cls),
    get_info(ground, pred, _Key, Goal, (GndI, GndO)),
    gather_modes_info_goal(Goal, GndI, GndO),
    fail.
gather_entry_modes(_).

remove_dead_code(Cls0, Ds0, Cls, Ds) :-
    (source_clause(_, directive(module(_, Exports0, _)), _) -> true ; true),
    (
        var(Exports0) ->
        pplog(infer, ['All predicates exported so there is no dead code']),
        Cls = Cls0, Ds = Ds0
    ;
        findall(F/A, (entry_assertion(Goal, _, _), functor(Goal, F, A)),
            Exports, Exports1),
        curr_module(Module),
        maplist(([Module] -> ''(F0/A, F/A) :- module_concat(Module,F0,F)),
                Exports0, 
                Exports1),
        clauses_to_deps(Cls0, Deps0, []),
        remove_deps(Exports, Deps0, Deps),
        deps_to_prednames(Deps, Preds0),
        sort(Preds0, Preds),
        remove_clauses(Preds, Cls0, Ds0, Cls, Ds),
        (
            Preds \== [] ->
            pplog(infer, ['Removing unreachable predicates: ', ''(Preds)])
        ;
            true
        )
    ).

deps_to_prednames([],               []).
deps_to_prednames([dep(A, B)|Deps], [A, B|Preds]) :-
    deps_to_prednames(Deps, Preds).

remove_clauses([],           Cls,  Ds,  Cls, Ds).
remove_clauses([Pred|Preds], Cls0, Ds0, Cls, Ds) :-
    remove_pred(Cls0, Ds0, Pred, Cls1, Ds1),
    remove_clauses(Preds, Cls1, Ds1, Cls, Ds).

remove_pred([],                [],      _,   [],      []).
remove_pred([Clause|Program0], [D|Ds0], F/A, Program, Ds) :-
    (
        is_clause(Clause, Head, _, _),
        functor(Head, F, A) ->
        Program = Program1,
        Ds = Ds1
    ;
        Program = [Clause|Program1],
        Ds = [D|Ds1]
    ),
    remove_pred(Program0, Ds0, F/A, Program1, Ds1).

clauses_to_deps([],               Deps,  Deps).
clauses_to_deps([Clause|Program], Deps0, Deps) :-
    clause_to_dep(Clause, Deps0, Deps1),
    clauses_to_deps(Program, Deps1, Deps).

clause_to_dep(Clause, Deps0, Deps) :-
    is_clause(Clause, Head, Body, _) ->
    functor(Head, F, A),
    body_to_dep(Body, F, A, Deps0, Deps)
    ;
    Deps = Deps0.

body_to_dep((LitPPKey, Body), F, A, [dep(F/A, FL/AL)|Deps0], Deps) :-
    !,
    lit_ppkey(LitPPKey, Lit, _PPKey),
    functor(Lit, FL, AL),
    body_to_dep(Body, F, A, Deps0, Deps).
body_to_dep(LitPPKey, F, A, [dep(F/A, FL/AL)|Deps], Deps) :-
    lit_ppkey(LitPPKey, Lit, _PPKey),
    functor(Lit, FL, AL).

:- export(remove_deps/3).
remove_deps([],               Dependencies,  Dependencies).
remove_deps([Export|Exports], Dependencies0, Dependencies) :-
    remove_using_dep(Dependencies0, Export, Dependencies2, Useds0,
        Exports),
    sort(Useds0, Useds),
    remove_deps(Useds, Dependencies2, Dependencies).

remove_using_dep([], _, [], Useds, Useds).
remove_using_dep([Dependency|Dependencies0], Export, Dependencies, Useds0,
        Useds) :-
    (
        Dependency = dep(_, Export) ->
        Dependencies = Dependencies1,
        Useds0 = Useds1
    ;
        Dependency = dep(Export, Used) ->
        Dependencies = Dependencies1,
        Useds0 = [Used|Useds1]
    ;
        Dependencies = [Dependency|Dependencies1],
        Useds0 = Useds1
    ),
    remove_using_dep(Dependencies0, Export, Dependencies1, Useds1, Useds).

%--------------------------------------------------------------------------
% First entry point: collect mode info in the database

gather_modes_info([],           []).
gather_modes_info([Clause|Cls], [D|Ds]) :-
    ( is_clause(Clause, Head, Body, ClauseId) ->
        gather_modes_info_clause(Head, Body, D, ClauseId)
    ;
        true
    ),
    gather_modes_info(Cls, Ds).

:- pred gather_modes_info_clause/4 + not_fails.

gather_modes_info_clause(_Head, true, _, _ClauseId) :- !.
gather_modes_info_clause(_Head, Body, D, ClauseId) :- !,
    D = dic(Vars, _),
    gather_modes_info_body(Body, ClauseId, Vars).
gather_modes_info_clause(_, _, _, _).

gather_modes_info_body((A, !), K1, Vars) :-
    !,
    gather_modes_info_body(A, K1, Vars).
gather_modes_info_body((A & !), K1, Vars) :-
    !,
    gather_modes_info_body(A, K1, Vars).
gather_modes_info_body((A, B), K1, Vars) :-
    !,
    first_key(B, K0),
    gather_modes_info_body(A, K0, Vars),
    gather_modes_info_body(B, K1, Vars).
gather_modes_info_body((A & B), K1, Vars) :-
    !,
    first_key(B, K0),
    gather_modes_info_body(A, K0, Vars),
    gather_modes_info_body(B, K1, Vars).
gather_modes_info_body((!),     _K,   _Vars) :- !.
gather_modes_info_body((! : !), _K,   _Vars) :- !.
gather_modes_info_body((A:Key), Key1, Vars) :-
    % Kludge to avoid backtracking: -- EMM
    (get_info(ground, point, Key,  Vars, GndI) -> true ; true),
    (get_info(ground, point, Key1, Vars, GndO) -> true ; true),
    gather_modes_info_goal(A, GndI, GndO).

gather_modes_info_goal(A, GndI, GndO) :-
    predkey_from_sg(A, Name),
    functor(A, F, Arity),
    get_actual_info(Name, F, Arity, Info),
    decide_on_each_arg(Info, 1, A, GndI, GndO, InfoO),
    put_actual_info(Name, F, Arity, InfoO).

%--------------------------------------------------------------------------

decide_on_each_arg([],     _, _, _,    _,    []).
decide_on_each_arg([I|Is], N, A, GndI, GndO, [Io|Ios]) :-
    N1 is N+1,
    decide_on_one_arg(I, N, A, GndI, GndO, Io),
    decide_on_each_arg(Is, N1, A, GndI, GndO, Ios).

decide_on_one_arg(n/n, _, _, _, _, n/n) :-
    !.
decide_on_one_arg(y/n, N, A, GndI, _GndO, I/n) :-
    !,
    arg(N, A, ArgN),
    varset(ArgN, Nvars),
    decide_on_arg_mode(Nvars, GndI, I).
decide_on_one_arg(n/y, N, A, _GndI, GndO, n/I) :-
    !,
    arg(N, A, ArgN),
    varset(ArgN, Nvars),
    decide_on_arg_mode(Nvars, GndO, I).
decide_on_one_arg(y/y, N, A, GndI, GndO, Ii/Io) :-
    arg(N, A, ArgN),
    varset(ArgN, Nvars),
    decide_on_arg_mode(Nvars, GndI, Ii),
    decide_on_arg_mode(Nvars, GndO, Io).

decide_on_arg_mode(Nvars, Gnd, y) :-
    all_member_vars(Nvars, Gnd),
    !.
decide_on_arg_mode(_vars, _Gnd, n).

%--------------------------------------------------------------------------

get_actual_info(Pred, F, A, Info) :-
    current_fact(inferred(modes, Pred, mode(F, A, Info)), Ref),
    !,
    erase(Ref).
get_actual_info(_, _, Arity, Info) :-
    length(Info, Arity),
    everything_is_possible(Info).

everything_is_possible([]).
everything_is_possible([y/y|Info]) :-
    everything_is_possible(Info).

put_actual_info(Pred, F, A, Info) :-
    asserta_fact(inferred(modes, Pred, mode(F, A, Info))).

all_member_vars([],     _).
all_member_vars([X|Xs], L) :-
    ord_member(X, L),
    all_member_vars(Xs, L).

%--------------------------------------------------------------------------
gather_modes_output(Program, Dic, NewProgram, NewDic) :-
    gather_modes_output_(Program, Dic, 0, NewProgram, NewDic).

gather_modes_output_([],               [],      _,  [],         []).
gather_modes_output_([Clause|Program], [Dc|Ds], K0, NewProgram, NewDs) :-
    is_clause(Clause, Head, _B, _Id),
    functor(Head, F, A),
    K0 \== F/A,
    !,
    add_mode_declaration(F, A, Clause, Dc, K0, K, NewProgram, NewProgram0,
        NewDs, NewDs0),
    gather_modes_output_(Program, Ds, K, NewProgram0, NewDs0).
gather_modes_output_([Clause|Program], [D|Ds], K, [Clause|NewProgram],
        [D|NewDs]) :-
    gather_modes_output_(Program, Ds, K, NewProgram, NewDs).

% dead code is suppressed so that caslog does not complain
%% Commented out Nov 24, 2004 -PLG 
%% add_mode_declaration(F,A,Clause,Dc,_K0,K,NewProgram,NewProgram0,NewDs,NewDs0):-
%%      get_predkey(F,A,Pred),
%%      current_fact(inferred(modes,Pred,mode(F,A,Info)),Ref), !,
%%      erase(Ref),
%%      translate_to_modes(Info,Modes),
%%      K = F/A,
%%      D = mode(K,Modes),
%%      create_dict(D,DD),
%%      null_directive_key(DK),
%%         is_directive(NewDirect, D, DK),
%%      NewProgram=[NewDirect,Clause|NewProgram0],
%%      NewDs=[DD,Dc|NewDs0].

% Currently we are not removing supposed dead code, because such code
% could have a call to a literal not implemented in the current module
% (builtins or library predicates) and have assertions about the
% relevant information for the cost analysis, and eventually it could
% not have mode declaration (2009-18-05) -- EMM.
add_mode_declaration(F, A, Clause, Dc, _K0, K, NewProgram, NewProgram0, NewDs,
        NewDs0) :-
    add_mode_declaration_(F, A, Clause, Dc, _K0, K, NewProgram,
        NewProgram0, NewDs, NewDs0),
    !.
add_mode_declaration(_F, _A, Clause, Dc, K, K, [Clause|NewProgram], NewProgram,
        [Dc|NewDs], NewDs).

add_mode_declaration_(F, A, Clause, Dc, _K0, K, NewProgram, NewProgram0, NewDs,
        NewDs0) :-
    get_predkey(F, A, Pred),
    !,
    ( current_pp_flag(para_grain, gr) ->
        % This version is needed for granularity
        current_fact(inferred(vartypes, Pred, Vartypes)),
        vartypes_to_modes(Vartypes, Modes) % Not used. 
        % Use translate_to_modes/2 instead. 
        % -PLG (9-feb-05)
    ;
        % This version is needed for resources 
        (
            get_modes_assrt(F/A, Modes) ->
            true
            % Modes should not be inferred from vartypes.
            % ; 
            %  current_fact(inferred(vartypes,Pred,Vartypes)), 
            %  vartypes_to_modes(Vartypes,Modes)
        ;
            current_fact(inferred(modes, Pred, mode(F, A, Info)), _Ref) ->
            % erase(Ref), % Do not erase mode info.
            translate_to_modes(Info, Modes)
        )
    ),
    %
    do_add_mode_declaration(F, A, Clause, Modes, Dc, K, NewProgram,
        NewProgram0, NewDs, NewDs0).

do_add_mode_declaration(F, A, Clause, Modes, Dc, K, NewProgram, NewProgram0,
        NewDs, NewDs0) :-
    mode_declaration(F, A, Modes, K, NewDirect, DD),
    NewProgram=[NewDirect, Clause|NewProgram0],
    NewDs=[DD, Dc|NewDs0].

mode_declaration(F, A, Modes, K, NewDirect, DD) :-
    K = F/A,
    D = mode(K, Modes),
    create_dict(D, DD),
    null_directive_key(DK),
    is_directive(NewDirect, D, DK).

%--------------------------------------------------------------------------


%% Not used. -PLG (9-feb-05)
%% 
%% %----------------------------------------------------------------------------
%% 
vartypes_to_modes(Vartypes, Modes) :-
    copy_term(Vartypes, Vartypes0),
    Vartypes0 = vartype(Goal, Call, _Succ),
    vartype_names(Call),
    functor(Goal, _, A),
    vartypes_to_modes_(0, A, Goal, Modes).

vartype_names([T|Ts]) :-
    (type_of_goal(builtin(BT), T) -> true; BT = T),
    BT =.. [F, V|R], % TODO: use prop_unapply? (JF)
    V =.. [F|R],
    vartype_names(Ts).
vartype_names([]).

vartypes_to_modes_(A, A, _VarType, []).
vartypes_to_modes_(N, A, VarType,  Modes) :- N < A, !,
    N1 is N+1,
    arg(N1, VarType, T),
    Modes=[M|Modes0],
    vartype2mode(T, M),
    vartypes_to_modes_(N1, A, VarType, Modes0).

vartype2mode('term_typing:var', '-') :- !.
vartype2mode(var,               '-') :- !.
vartype2mode(_,                 '+').

%% 
%% %----------------------------------------------------------------------------

% translate types (from Rul) to measures

:- push_prolog_flag(multi_arity_warnings, off).

gather_measures(Program, Dic, NewProgram, NewDic) :-
    gather_measures(Program, Dic, 0, NewProgram, NewDic).


% This code reads the measure assertions from 'native_props:size'/2. 
% From now on it is suppressed because the measure assertions will be
% :- use_module(infercost(init/builtin), [enum_trusted_facts/2]).
% read from 'native_props:size_metric'/3.  - JNL (03-feb-07)
% read_asr_measure(Pred, Measure) :-
%       enum_trusted_facts(Pred, st(Pred,_,_,Measure,_,_,_,_,_,_)),!.

gather_measures([],               [],      _,  [],          []).
gather_measures([Clause|Program], [Dc|Ds], K0, NewProgram0, NewDs0) :-
    gather_measure(Clause, Dc, K0, NewProgram0, NewDs0, NewProgram, NewDs),
    gather_measures(Program, Ds, K0, NewProgram, NewDs).

:- if(defined(has_ciaopp_extra)).
gather_measure(Clause, Dc, K0, NewProgram0, NewDs0, NewProgram, NewDs) :-
    is_directive(NewDirect, D, DK),
    is_clause(Clause, Head, _B, _Id),
    functor(Head, F, A),
    K0 \== F/A,
    get_predkey(F, A, Key),
    module_split(F, _, F0),
    functor(Goal0, F0, A),
    functor(Goal,  F,  A),
    debug_message(
        "Recovering measure information from assertion for ~w ~w",
        [Key, Measures1]),
    ( get_info(regtypes, pred, Key, Goal, (_Call, Succ_Type)) ->
        type2measure(Goal, Succ_Type, Measures0),
        debug_message(
            "Recovering measure information from types for ~w ~w",
            [Key, Measures0]),
        (
            read_asr_measure(Goal0, Measures1) ->
            apply_glb_measures(Measures0, Measures1, Key, Measures)
        ;
            Measures = Measures0
        ),
        debug_message("Applying the glb operation for ~w ~w",
            [Key, Measures])
    ;
        read_asr_measure(Goal0, Measures)
    ),
    K = F/A,
    D = measure(K, Measures),
    create_dict(D, DD),
    null_directive_key(DK) ->
    NewProgram0 = [NewDirect, Clause|NewProgram],
    NewDs0 = [DD, Dc|NewDs]
    ;
    NewProgram0 = [Clause|NewProgram],
    NewDs0 = [Dc|NewDs].
:- else.
gather_measure(Clause, Dc, _K0, NewProgram0, NewDs0, NewProgram, NewDs) :-
    NewProgram0 = [Clause|NewProgram],
    NewDs0 = [Dc|NewDs].
:- endif.

:- pop_prolog_flag(multi_arity_warnings).


:- if(defined(has_ciaopp_extra)).
% Obtain measure assertions from ':- measure(F/A,Measure)'
read_asr_measure(Goal, Measures) :-
    functor(Goal, F, A),
    get_measures_assrt(F/A, Measures), !.
% Obtain measure assertions from 'size_metric(Var,Metric)'
read_asr_measure(Goal, Measures) :-
    assertion_of(Goal, _M, trust, _Type, (_::_:_=>_+Props#_), _Dict,
        _Source, _LB, _LE), !,
    Goal =.. [_|Vars],
    get_measures_assrt(Vars, Props, Measures), !.
% read_asr_measure(_Goal,[]):-!.

get_measures_assrt([],         _,     []).
get_measures_assrt([Var|Vars], Props, [M|Ms]) :-
    get_size_metric_assrt(Props, Var, M),
    get_measures_assrt(Vars, Props, Ms).

get_size_metric_assrt([],                            _,   null).
get_size_metric_assrt([size_metric(_, Var, M0)|_Ps], Arg, M) :-
    get_metric(M0, M),
    Var == Arg, !.
get_size_metric_assrt([_|Ps], Arg, M) :-
    get_size_metric_assrt(Ps, Arg, M).

% apply_glb_measures(M1s,M2,Ms)
% M1s is a list of measures inferred by the analysis and 
% M2s is a list of measures provided by the user.
apply_glb_measures([],       [],       _Key, []).
apply_glb_measures(Measures, [],       _Key, Measures).
apply_glb_measures([M1|M1s], [M2|M2s], Key,  [M|Ms]) :-
    apply_glb_measures_(M1, M2, Key, M),
    apply_glb_measures(M1s, M2s, Key, Ms).

% NOTE: I have defined another measure called 'null'. Actually, it is not a
% measure, it is only a way of keeping track when the user does not give
% information for a particular variable. Only when the measure of a variable
% is 'null', the information inferred by the analysis is taken into
% consideration. - JNL (03-feb-07)

% apply_glb_measures(M1,M2,Key,M)
% M1 measure inferred by analysis and M2 measure given by user  
apply_glb_measures_(M1,  null, _Key, M1) :- !.
apply_glb_measures_(_M1, M2,   _Key, M2) :- !.
:- endif.
