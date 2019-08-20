/*             Copyright (C)1990-2003 UPM-CLIP				*/
:- module(fixpo_ops,
	[ 
	    inexistent/2,
	    variable/2,
	    bottom/1,
	    singleton/2,
      get_singleton/2,
	    fixpoint_id/1,
	    fixpoint_id_reuse_prev/5,
	    fixpoint_id_reuse_prev_success/6,
	    fixp_id/1,
	    each_abs_sort/3,
	%    each_concrete/4,
	    each_project/6,
	    each_extend/6,
	    each_exit_to_prime/8,
	    each_unknown_call/4,
	    each_body_succ_builtin/12,
	    body_succ_meta/7,
	    applicable/3,
	    each_apply_trusted/7,
	    reduce_equivalent/3,
	    widen_succ/4,
	    decide_memo/6,
	    clause_applies/2,
	    abs_subset_/3,
	    restore_previous_analysis/1,
	    store_previous_analysis/1,
	    store_previous_analysis_completes/1,
	    store_previous_analysis_memo_tables/1,
	    reset_previous_analysis/1,
	    store_previous_analysis_aux_info/1,
	    compare_with_previous_analysis/3,
	    compare_completes_with_prev/3,
	    compare_memo_tables_with_prev/3,
	    remove_useless_info/1,
%	    remove_useless_info_get_init_calls/2,
	    complete_prev/7,
	    memo_table_prev/6,
	    collect_exported_completes/2,
	    each_identical_abstract/3,
	    copy_completes/1,
	    iter/1,
	    eliminate_bottoms_and_equivalents/3  % JNL
	],
	[assertions,datafacts,nativeprops,isomodes]).

:- doc(module,"This module contains operations which are common to 
	several of the different top-down fixpoint algorithms in PLAI.").

:- doc(stability, alpha).
:- doc(bug,"Predicates automatically introduced by remove
         disjuntions do not have LOC information. Thus messages
         related to them do not include line numbers.").

:- use_module(library(lists), [member/2]).
:- use_module(engine(io_basic), [nl/0]).
:- use_module(library(write), [writeq/1]).
:- use_module(ciaopp(p_unit/clause_db), [clause_locator/2]).
:- use_module(ciaopp(p_unit/program_keys), [decode_litkey/5, is_entrykey/1, orig_clause_id/2]).
:- use_module(ciaopp(plai/domains), [
	exit_to_prime/8,
	abs_sort/3,
	extend/6,
	eliminate_equivalent/3,
	compute_lub/3,
	glb/4,
	widen/4,
	unknown_call/4,
	project/6,
	body_succ_builtin/9,
	special_builtin/6,
	fixpoint_covered/3,
	abs_subset/3,
	less_or_equal_proj/5,
	identical_proj/5,
	less_or_equal/3,
	identical_abstract/3]).
:- use_module(ciaopp(plai/apply_assertions_old),
        [apply_trusted/7, apply_trusted_each/7]).

:- use_module(ciaopp(plai/apply_assertions), [apply_assrt_exit/7]).
:- use_module(ciaopp(plai/plai_db), [complete/7, memo_table/6]).
:- use_module(ciaopp(preprocess_flags), [current_pp_flag/2]).
:- use_module(ciaopp(p_unit), [language/1]).
:- use_module(ciaopp(p_unit/program_keys), [predkey_from_sg/2]).

:- use_module(typeslib(dumper), [dump_auxiliary_info/1, acc_auxiliary_info/2,
				 restore_auxiliary_info/2, imp_auxiliary_info/4]).

:- use_module(library(messages), [warning_message/3, warning_message/2]).
:- use_module(library(sort), [sort/2]).
:- use_module(library(aggregates), [findall/3]).
:- use_module(library(terms_vars), [varset/2]).

% TODO: move and unify these messages with plai_errors
inexistent(SgKey,ClId):- ClId = 0, !, % TODO: special case for exported? (no Loc)
	warning_message("Unknown predicate ~w",[SgKey]).
inexistent(SgKey,ClId):-
	find_lines_in_orig_prog(ClId,Loc),!,
	warning_message(Loc, "Unknown predicate ~w",[SgKey]).
inexistent(SgKey,ClId):-
	warning_message("Unknown predicate ~w in clause ~w",[SgKey,ClId]).

variable(SgKey,ClId):-
        find_lines_in_orig_prog(ClId,Loc), !,
        warning_message(Loc,"Variable in meta_call at ~w:
      the program should include the required entries",[SgKey]).
variable(SgKey,_ClId):- % Loc not found (probably because we are running incanal)
        warning_message("Variable in meta_call at ~w:
      the program should include the required entries",[SgKey]).

:- doc(find_lines_in_orig_prog(ClId,Loc), "Since the ClId may correspond to 
	a predicate version generated by partial evaluation, care must be taken
	to identify the original predicate in the program.").

find_lines_in_orig_prog(ClId,Loc):-
	clause_locator(ClId,Loc),!.
find_lines_in_orig_prog(ClId,Loc):-
	orig_clause_id(ClId,Orig_ClId),
	clause_locator(Orig_ClId,Loc).

bottom([]).
bottom(['$bottom']).

singleton(Prime,[Prime]). % TODO: choicepoints??
singleton('$bottom',[]).

get_singleton(Prime,[Prime]) :- !.
get_singleton('$bottom',[]).

%-------------------------------------------------------------------------

:- data fixp_id/1.

fixpoint_id(Id):-
	retract_fact(fixp_id(Id0)),
	Id is Id0+1,
	asserta_fact(fixp_id(Id)).
%-------------------------------------------------------------------------

:- export(fixpoint_get_new_id/5).
fixpoint_get_new_id(SgKey,AbsInt,Sg,Proj,Id) :-
        (current_pp_flag(reuse_fixp_id,on) ->
           fixpoint_id_reuse_prev(SgKey,AbsInt,Sg,Proj,Id)
        ;
            fixpoint_id(Id)
        ).

fixpoint_id_reuse_prev(SgKey,AbsInt,Sg,Proj,Id):-
	current_fact(complete_prev(SgKey,AbsInt,Subg,Proj1,_Prime1,NId,_Fs)),
	identical_proj(AbsInt,Sg,Proj,Subg,Proj1),!,
	Id = NId.
fixpoint_id_reuse_prev(_SgKey,AbsInt,_Sg,_Proj,Id):-
	fixpoint_id(NewId),
	(current_fact(complete_prev(_,AbsInt,_,_,_,NewId,_)) ->
	    fixp_id_new(Id)
	;
	    Id = NewId).

fixp_id_new(Id):-
	fixpoint_id(Id),
	\+ current_fact(complete_prev(_SgKey,_AbsInt,_Sg,_Proj,_,Id,_)),
	!.
fixp_id_new(Id):-
	fixp_id_new(Id).

%-------------------------------------------------------------------------
% for the checking fixpoints
fixpoint_id_reuse_prev_success(SgKey,AbsInt,Sg,Proj,Id,Prime):-
	current_fact(complete_prev(SgKey,AbsInt,Subg,Proj1,Prime1,NId,_Fs)),
	identical_proj(AbsInt,Sg,Proj,Subg,Proj1),!,
	Id = NId,
	each_abs_sort(Prime1,AbsInt,Prime).
%-------------------------------------------------------------------------

applicable(ListPrime,_AbsInt,Prime):- singleton(Prime,ListPrime), !.
applicable(ListPrime,AbsInt,Prime):- compute_lub(AbsInt,ListPrime,Prime).

reduce_equivalent([Prime],_AbsInt,LPrime):- !,
	singleton(Prime,LPrime).
reduce_equivalent(ListPrime0,AbsInt,ListPrime1):-
	eliminate_bottoms_and_equivalents(AbsInt,ListPrime0,ListPrime1).

%-------------------------------------------------------------------------

each_exit_to_prime([Exit],AbsInt,Sg,Hv,Head,Sv,ExtraInfo,LPrime):- !,
	exit_to_prime(AbsInt,Sg,Hv,Head,Sv,Exit,ExtraInfo,Prime),
	LPrime=[Prime].
each_exit_to_prime(LExit,AbsInt,Sg,Hv,Head,Sv,ExtraInfo,LPrime):-
	each_exit_to_prime0(LExit,AbsInt,Sg,Hv,Head,Sv,ExtraInfo,TmpLPrime),
	eliminate_bottoms_and_equivalents(AbsInt,TmpLPrime,LPrime).

each_exit_to_prime0([],_AbsInt,_Sg,_Hv,_Head,_Sv,_ExtraInfo,[]).
each_exit_to_prime0([Exit|LExit],AbsInt,Sg,Hv,Head,Sv,ExtraInfo,[Prime|LPrime]):-
	exit_to_prime(AbsInt,Sg,Hv,Head,Sv,Exit,ExtraInfo,Prime),
	each_exit_to_prime0(LExit,AbsInt,Sg,Hv,Head,Sv,ExtraInfo,LPrime).

each_abs_sort([ASub_u],AbsInt,LASub):- !,
	abs_sort(AbsInt,ASub_u,ASub),
	LASub=[ASub].
each_abs_sort(LASub_u,AbsInt,LASub):-
	each_abs_sort0(LASub_u,AbsInt,TmpLASub),
	sort(TmpLASub,LASub).

each_abs_sort0([],_AbsInt,[]).
each_abs_sort0([ASub_u|LASub],AbsInt,[ASub|LPrime]):-
	abs_sort(AbsInt,ASub_u,ASub),
	each_abs_sort0(LASub,AbsInt,LPrime).

%% each_concrete([],_,_AbsInt,[]).
%% each_concrete([Call|Calls],X,AbsInt,Concretes):-
%% 	concrete(AbsInt,X,Call,Concretes0),
%% 	append(Concretes0,Concretes1,Concretes),
%% 	each_concrete(Calls,X,AbsInt,Concretes1).

each_project([],_AbsInt,_Sg,_Sv,_HvFv_u,[]).
each_project([Exit|Exits],AbsInt,Sg,Sv,HvFv_u,[Prime|Primes]):-
	   project(AbsInt,Sg,Sv,HvFv_u,Exit,Prime),
	   each_project(Exits,AbsInt,Sg,Sv,HvFv_u,Primes).

each_extend(Sg,[Prime],AbsInt,Sv,Call,LSucc):- !,
	extend(AbsInt,Sg,Prime,Sv,Call,Succ),
	LSucc=[Succ].
each_extend(Sg,LPrime,AbsInt,Sv,Call,LSucc):-
	each_extend0(LPrime,Sg,AbsInt,Sv,Call,TmpLSucc),
	eliminate_bottoms_and_equivalents(AbsInt,TmpLSucc,LSucc).

each_extend0([],_,_AbsInt,_Sv,_Call,[]).
each_extend0([Prime|LPrime],Sg,AbsInt,Sv,Call,[Succ|LSucc]):-
	extend(AbsInt,Sg,Prime,Sv,Call,Succ),
	each_extend0(LPrime,Sg,AbsInt,Sv,Call,LSucc).

:- pred eliminate_bottoms_and_equivalents(AbsInt,TmpLSucc,LSucc) # 
     "When multi_success is turned on, @var{TmpLSucc} may contain 
      elements which are bottom. These can be safely removed from the 
      list of successes. Also, repeated elements in the list can also 
      be safely removed.".
eliminate_bottoms_and_equivalents(AbsInt,TmpLSucc,LSucc):-
	filter_out_bottoms(TmpLSucc,LSucc_nb),
	eliminate_equivalent(AbsInt,LSucc_nb,LSucc).

filter_out_bottoms([],[]).
filter_out_bottoms(['$bottom'|LSucc],LSucc_nb):-!,
	filter_out_bottoms(LSucc,LSucc_nb).
filter_out_bottoms([Succ|LSucc],LSucc_nb):-
	LSucc_nb = [Succ|MoreSucc],
	filter_out_bottoms(LSucc,MoreSucc).

each_unknown_call([],_AbsInt,_Sg,[]).
each_unknown_call([Call|Calls],AbsInt,Sg,[Succ|Succs]):-
	unknown_call(AbsInt,Sg,Call,Succ), % TODO: wrong? Sg vs Sv?
	each_unknown_call(Calls,AbsInt,Sg,Succs).

each_body_succ_builtin([],_,_T,_Tg,_,_,_Sg,_Sv,_HvFv_u,_F,_N,[]).
each_body_succ_builtin([Call|Calls],AbsInt,T,Tg,Vs,SgKey,Sg,Sv,HvFv_u,
	               F,N,[Succ|Succs]):-
	project(AbsInt,Sg,Sv,HvFv_u,Call,Proj),
	body_succ_builtin(AbsInt,T,Tg,Vs,Sv,HvFv_u,Call,Proj,Succ),!,
	project(AbsInt,Sg,Sv,HvFv_u,Succ,Prime),
	get_singleton(Prime,LPrime),
%  asserta_fact(complete(SgKey,AbsInt,Sg,Proj,LPrime,no,[(F,N)])),
  add_complete_builtin(SgKey,AbsInt,Sg,Proj,LPrime),
	each_body_succ_builtin(Calls,AbsInt,T,Tg,Vs,SgKey,Sg,Sv,HvFv_u,F,N,Succs).
% TODO: add table with the predicates that do not need complete
%       true, cut, fail

% TODO: move to plai_db?
add_complete_builtin(_SgKey,_AbsInt,_Sg,_Proj,_LPrime).
% Old version: It seems pointless to add completes for builtins since they are
% recomputed from scratch every time instead of using the complete
% add_complete_builtin(SgKey,AbsInt,Sg,Proj,_) :-
%         functor(Sg, F, A),
%         functor(Sg1, F, A),
%         current_fact(complete(SgKey,AbsInt,Sg1,Proj0,_LPrime,no,_OldFs)), % backtracking here
%         identical_proj(AbsInt,Sg,Proj,Sg1,Proj0), !.
% %        patch_parents(Ref,complete(SgKey,AbsInt,Sg,Proj,LPrime,no,Ps),F,N,Ps,OldFs),!.
% add_complete_builtin(SgKey,AbsInt,Sg,Proj,LPrime) :-
%         asserta_fact(complete(SgKey,AbsInt,Sg,Proj,LPrime,no,[])).
%         % Currently we are not storing any parents

each_identical_proj([],_Sg,_AbsInt,[],_Subg).
each_identical_proj([Prime|LPrime],Sg,AbsInt,[Succ|LSucc],Subg):-
	identical_proj(AbsInt,Sg,Prime,Subg,Succ),
	each_identical_proj(LPrime,Sg,AbsInt,LSucc,Subg).

each_less_or_equal_proj([],_Sg,_AbsInt,[],_Subg).
each_less_or_equal_proj([Prime|LPrime],Sg,AbsInt,[Succ|LSucc],Subg):-
	less_or_equal_proj(AbsInt,Sg,Prime,Subg,Succ),
	each_less_or_equal_proj(LPrime,Sg,AbsInt,LSucc,Subg).

%-----------------------------------------------------------------

each_apply_trusted(Proj,SgKey,Sg,Sv,AbsInt,ListPrime,LPrime):-
	current_pp_flag(multi_success,off), !,
	applicable(ListPrime,AbsInt,Prime0), % applicable computes the lub
  apply_assrt_exit(AbsInt,Sg,Sv,Proj,[Prime0],LPrime1,_), LPrime1 = [Prime1],
  ( apply_trusted(Proj,SgKey,Sg,Sv,AbsInt,Prime1,Prime) ->
	    true % old, only for comp with new implementation of trusts
	;
	    Prime = Prime1
	),
	get_singleton(Prime,LPrime).
each_apply_trusted(Proj,SgKey,Sg,Sv,AbsInt,ListPrime,LPrime):-
	apply_trusted_each(Proj,SgKey,Sg,Sv,AbsInt,ListPrime,LPrime).

%-----------------------------------------------------------------
:- pred widen_succ(+AbsInt,+Prime0,+Prime1,-LPrime) + not_fails.
widen_succ(AbsInt,Prime0,Prime1,LPrime):-
	current_pp_flag(multi_success,on), !,
	reduce_equivalent([Prime0,Prime1],AbsInt,LPrime).
widen_succ(AbsInt,Prime0,Prime1,Prime):-
	current_pp_flag(widen,on), !,
	singleton(P0,Prime0),     % to_see claudio
	singleton(P1,Prime1),     % to_see claudio
	singleton(P,Prime),       % to_see claudio
	widen(AbsInt,P0,P1,P), !. % for the singletons
widen_succ(AbsInt,Prime0,Prime1,Prime):-
	singleton(P0,Prime0),
	singleton(P1,Prime1),
	singleton(P,Prime),
	compute_lub(AbsInt,[P0,P1],P), !. % for the singletons

:- export(process_analyzed_clause/7).
:- pred process_analyzed_clause(AbsInt,Sg,Sv,Proj,TempPrime,Prime1,Prime) + not_fails
        #"Once a clause or a set of clauses, i.e., @var{ClKey} is a free
         variable, have been analyzed, this predicate will apply the success
         assertions or perform the widening.".
process_analyzed_clause(AbsInt,Sg,Sv,Proj,TempPrime,Prime0,Prime) :-
        apply_assrt_exit(AbsInt,Sg,Sv,Proj,Prime0,Prime1,yes), !,
        ( current_pp_flag(fixp_stick_to_success, on) ->
            Prime = TempPrime
        ;
            singleton(P0,Prime1),
            singleton(P1,TempPrime),
            singleton(P,Prime), 
            compute_lub(AbsInt,[P0,P1],P), ! % for the singletons
        ).
process_analyzed_clause(AbsInt,_,_,_,TempPrime,Prime1,NewPrime) :-
        widen_succ(AbsInt,TempPrime,Prime1,NewPrime).

%-----------------------------------------------------------------
% have to revise difflsign for recorded_internal!!!
decide_memo(difflsign,Key,NewN,Id,Vars_u,Exit):- !,
	( bottom(Exit) -> Exit0 = '$bottom' ; Exit = p(_,_,Exit0) ),
	asserta_fact(memo_table(Key,difflsign,NewN,Id,Vars_u,Exit0)).
%% ?????????????????
%% decide_memo(AbsInt,Key,NewN,Id,Vars_u,Exit):-
%% 	asserta_fact(pragma(Key,NewN,Id,Vars_u,Exit)),!,
%% 	asserta_fact(memo_table(Key,AbsInt,NewN,Id,Vars_u,Exit)).
decide_memo(AbsInt,Key,NewN,Id,Vars_u,Exit):-
	asserta_fact(memo_table(Key,AbsInt,NewN,Id,Vars_u,Exit)).

%------------------------------------------------------------------------%
% clause_applies(+,+)                                                    %
% clause_applies(Head,Sg)                                                %
% succeeds if Head of some clause matches goal Sg                        %
% the check is omitted if we are analyzing constraints                   %
%------------------------------------------------------------------------%

clause_applies(_Head,_Sg):-
	language(clp), !.
clause_applies(Head,Sg):-
	\+ \+ ( Head = Sg ).

%------------------------------------------------------------------------%

abs_subset_([NewPrime],AbsInt,[TempPrime]):- !,
	fixpoint_covered(AbsInt,TempPrime,NewPrime).
abs_subset_(AbsInt,NewPrime,TempPrime):-
	abs_subset(AbsInt,NewPrime,TempPrime).

%------------------------------------------------------------------------%

body_succ_meta(apply(F,_),AbsInt,Sv_u,HvFv_u,Call,Exits,Succ):- !,
	call_builtin(AbsInt,'ground/1',ground(F),Sv_u,HvFv_u,Call,Exits,Succ).
body_succ_meta(call(_),AbsInt,_Sv_u,_HvFv,_Call,Exits,[Succ]):- !,
	map_glb(Exits,AbsInt,Succ).
body_succ_meta(not(_),_AbsInt,_Sv_u,_HvFv,Call,_Exits,Succ):- !,
	Succ = Call.
body_succ_meta(Type,_AbsInt,_Sv_u,_HvFv,_Call,_Exits,Succ):-
	meta_call_check(Type), !,
	Succ = ['$bottom'].
body_succ_meta(Sg,AbsInt,Sv_u,HvFv_u,Call,Exits,Succ):-
	predkey_from_sg(Sg,SgKey),
	call_builtin(AbsInt,SgKey,Sg,Sv_u,HvFv_u,Call,Exits,Succ).

call_builtin(AbsInt,SgKey,Sg,Sv_u,HvFv_u,Call,Exits,Succ):-
	special_builtin(AbsInt,SgKey,Sg,Sg,Type,Cvars),
	sort(Sv_u,Sv),
	sort(HvFv_u,HvFv),
	meta_call_to_success(Exits,HvFv,Call,AbsInt,Sg,Type,Cvars,Sv,Succ).

meta_call_to_success([],_,_Call,_AbsInt,_Sg,_Type,_Cvs,_Vars,[]).
meta_call_to_success([Exit|Exits],HvFv,[Call|Calls],AbsInt,Sg,Type,Cvs,Sv,
	             [Succ|Succs]):-
	project(AbsInt,Sg,Sv,HvFv,Exit,Proj),
	body_succ_builtin(AbsInt,Type,Sg,Cvs,Sv,HvFv,Exit,Proj,PseudoSucc),
	extend_meta(Sg,AbsInt,PseudoSucc,HvFv,Call,Succ),
	meta_call_to_success(Exits,HvFv,Calls,AbsInt,Sg,Type,Cvs,Sv,Succs).

extend_meta(Sg,AbsInt,Prime0,HvFv,Call,Succ):-
	Sg = findall(_,_,Z), !,
	varset(Z,Zs),
	project(AbsInt,Sg,Zs,HvFv,Prime0,Prime),
	extend(AbsInt,Sg,Prime,Zs,Call,Succ).
extend_meta(_Sg,_AbsInt,Succ,_HvFv,_Call,Succ).

meta_call_check(findall(_,_,Z)):- \+ list_compat(Z).

list_compat(X):- var(X), !.
list_compat([]):- !.
list_compat([_|X]):- list_compat(X).

map_glb([],_AbsInt,'$bottom').
map_glb([Succ],_AbsInt,Succ) :- !.
map_glb([Exit1,Exit2|Exits],AbsInt,Succ):-
	glb(AbsInt,Exit1,Exit2,Succ0),
	map_glb([Succ0|Exits],AbsInt,Succ).

%------------------------------------------------------------------------%
:- doc(complete_prev(SgKey,AbsInt,Sg,Proj,Prime,Id,Parents),
	"The predicate @var{SgKey} has a variant success pattern 
	  @code{(Sg,Proj,Prime)} on the domain @var{AbsInt}. The and-or
	  graph node is @var{Id}, and is called from the program points
	  in list @var{Parents}.").
:- data complete_prev/7.

:- doc(memo_table_prev(PointKey,AbsInt,Id,Child,Vars_u,Call),
	"Before calling the goal at program point @var{PointKey}, 
	  there is a variant in which
	  @var{Call} on the domain @var{AbsInt} holds upon the program
	  clause variables @var{Vars_u}. These variables need be sorted
	  conveniently so that @var{Call} makes sense. The and-or graph
	  node that causes this is @var{Id} and the call originated to
	  the goal at this program point generates and-or graph node
	  @var{Child}.").
:- data memo_table_prev/6.

:- doc(store_previous_analysis_aux_info(AbsInt), "Copies auxiliary info of
	previous analysis.").
store_previous_analysis_aux_info(AbsInt):-
	reset_previous_analysis_aux_info,
	current_fact(complete_prev(_,AbsInt,_,C,D,_,_)),
	acc_auxiliary_info(AbsInt,[C|D]),
	fail.
store_previous_analysis_aux_info(AbsInt):-
	current_fact(memo_table_prev(_,AbsInt,_,_,_,E)),
	acc_auxiliary_info(AbsInt,E),
	fail.
store_previous_analysis_aux_info(_AbsInt):-
	dump_auxiliary_info(asserta_if_not_yet).

:- doc(store_previous_analysis(AbsInt), "Copies all existing
       analysis information for domain @var{AbsInt}. Subsequent analysis will
       reuse complete numbers whenever possible using
       @pred{fixpoint_id_reuse_prev/5}. This will later allow comparing 
       the current analysis results with that of a new analysis using
       @pred{compare_with_previous_analysis/1}.").
store_previous_analysis(AbsInt):-
	reset_previous_analysis(AbsInt),
	store_previous_analysis_completes_(AbsInt),
	store_previous_analysis_memo_tables_(AbsInt),
	dump_auxiliary_info(asserta_if_not_yet).

:- doc(store_previous_analysis_completes(AbsInt), "Like
	@pred{store_previous_analysis/1}, but it only stores
	information related to completes, and it does not clean up
	the alternate database before storing completes.").
store_previous_analysis_completes(AbsInt):-
	store_previous_analysis_completes_(AbsInt),
	dump_auxiliary_info(asserta_if_not_yet).

:- doc(store_previous_analysis_memo_tables(AbsInt), "Like
	@pred{store_previous_analysis/1}, but only stores information
	related to memo_tables, and it does not clean up
	the alternate database before storing memo_tables.").
store_previous_analysis_memo_tables(AbsInt):-
	store_previous_analysis_memo_tables_(AbsInt),
	dump_auxiliary_info(asserta_if_not_yet).

:- doc(reset_previous_analysis(AbsInt), "Cleans up alternate
	database for storing analysis information.").
reset_previous_analysis(AbsInt):-
	retractall_fact(complete_prev(_,AbsInt,_,_,_,_,_)),
	retractall_fact(memo_table_prev(_,AbsInt,_,_,_,_)),
	reset_previous_analysis_aux_info.

reset_previous_analysis_aux_info:-
	retractall_fact(aux(_)).

store_previous_analysis_completes_(AbsInt):-
%	remove_useless_info(AbsInt),
	copy_completes(AbsInt).

copy_completes(AbsInt):-
	current_fact(complete(A,AbsInt,B,C,D,E,F)),
	asserta_fact(complete_prev(A,AbsInt,B,C,D,E,F)),
	acc_auxiliary_info(AbsInt,[C|D]),
	fail.
copy_completes(_AbsInt).

store_previous_analysis_memo_tables_(AbsInt):-
	copy_memo_tables(AbsInt).

copy_memo_tables(AbsInt):-
	retractall_fact(memo_table_prev(_,_,_,_,_,_)),
	current_fact(memo_table(A,AbsInt,B,C,D,E)),
	asserta_fact(memo_table_prev(A,AbsInt,B,C,D,E)),
	acc_auxiliary_info(AbsInt,E),
	fail.
copy_memo_tables(_AbsInt).

:- data aux/1.

asserta_if_not_yet(X):- current_fact(aux(X)), !.
asserta_if_not_yet(X):- asserta_fact(aux(X)).

%------------------------------------------------------------------------%
restore_previous_analysis(AbsInt):-
	restore_auxiliary_info(restore_aux,Dict),
	restore_(AbsInt,Dict).

restore_(AbsInt,Dict):-
	retract_fact(complete_prev(SgKey,AbsInt,Sg,Proj0,Primes0,Id,Parents)),
	imp_auxiliary_info(AbsInt,Dict,[Proj0|Primes0],[Proj|Primes]),
	asserta_fact(complete_prev(SgKey,AbsInt,Sg,Proj,Primes,Id,Parents)),
	fail.
restore_(AbsInt,Dict):-
	retract_fact(memo_table_prev(A,AbsInt,B,C,D,E0)),
	imp_auxiliary_info(AbsInt,Dict,E0,E),
	asserta_fact(memo_table_prev(A,AbsInt,B,C,D,E)),
	fail.
restore_(_AbsInt,_Dict).

restore_aux(X):- retract_fact(aux(X)).

%------------------------------------------------------------------------%
:- doc(compare_with_previous_analysis(AbsInt,Flag,Direction),
"Issues warning messages if the analysis results just computed do not
coincide with those previously stored. In addition, the argument
@var{Flag} is unified with the atom @tt{error} if one or more errors
are found. @var{Flag} remains a variable if no errors are found. If
@var{Direction} is equal to '=' it issues warning messages when the
abstract substitutions are not identical, if Direction is equal to
'=<' it issues messages when the abstract substitutions are not less
or equal").

compare_proj('=',Prime,Sg,AbsInt,Prime1,Subg):- !,
	each_identical_proj(Prime,Sg,AbsInt,Prime1,Subg).
compare_proj('=<',Prime,Sg,AbsInt,Prime1,Subg):- !,
	each_less_or_equal_proj(Prime,Sg,AbsInt,Prime1,Subg).
compare_proj('>=',Prime,Sg,AbsInt,Prime1,Subg):-
	each_less_or_equal_proj(Prime1,Subg,AbsInt,Prime,Sg).

compare_abs('=',AbsInt,E,E1):- !, 
	each_abs_sort(E,AbsInt,E_s),
	each_abs_sort(E1,AbsInt,E1_s),
	identical_abstract(AbsInt,E_s,E1_s).
compare_abs('=<',AbsInt,E,E1):-
	each_abs_sort(E,AbsInt,E_s),
	each_abs_sort(E1,AbsInt,E1_s),
	less_or_equal(AbsInt,E_s,E1_s).
compare_abs('>=',AbsInt,E,E1):- % TODO:[new-resources] document
	each_abs_sort(E,AbsInt,E_s),
	each_abs_sort(E1,AbsInt,E1_s),
	less_or_equal(AbsInt,E1_s,E_s).

:- data error/0.

add_error:-
	current_fact(error),!.
add_error:-
	asserta_fact(error).

compare_with_previous_analysis(AbsInt,Flag,Direction):-
	compare_completes_with_prev(AbsInt,Flag,Direction),
	compare_memo_tables_with_prev(AbsInt,Flag,Direction).

compare_completes_with_prev(AbsInt,Flag,Direction):-
	retractall_fact(error),
	compare_all_completes(AbsInt,Direction),
	(current_fact(error) ->
	    Flag = error
	;
	    true
	),
	retractall_fact(error).

compare_all_completes(AbsInt,Direction):-
	current_fact(complete_prev(SgKey,AbsInt,Sg,Proj_u,Prime_u,Id,_Fs),Ref),
	Id \== no,
	abs_sort(AbsInt,Proj_u,Proj),
	((current_fact(complete(SgKey,AbsInt,Subg,Proj1,Prime1_u,Id,_Fs1),Ref2),
	  abs_sort(AbsInt,Proj1,Proj1_),
	  identical_proj(AbsInt,Sg,Proj,Subg,Proj1_)
	 ) ->
	  erase(Ref),
	  erase(Ref2),
	  each_abs_sort(Prime_u,AbsInt,Prime),
	  each_abs_sort(Prime1_u,AbsInt,Prime1),
	  ( compare_proj(Direction,Prime,Sg,AbsInt,Prime1,Subg)
%	    each_identical_proj(Prime,Sg,AbsInt,Prime1,Subg)
	  -> true
	   ; warning_message("different primes in ~w ~w",[SgKey,Id]),
%jcf
%	     warning_message("~w",[complete_prev(SgKey,AbsInt,Sg,Proj_u,Prime_u,Id,_Fs)]),
	     writeq(complete_prev(SgKey,AbsInt,Sg,Proj_u,Prime_u,Id,_Fs)),nl,
%	     warning_message("~w",[complete(SgKey,AbsInt,Subg,Proj1,Prime1_u,Id,_Fs1)]),
	     writeq(complete(SgKey,AbsInt,Subg,Proj1,Prime1_u,Id,_Fs1)),nl,
%jcf
	     add_error
	  )
	;
	  Complete=complete_prev(SgKey,AbsInt,Sg,Proj_u,Prime_u,Id,_Fs),
	  warning_message("missing complete ~w ~w:~n",[SgKey,Id]),
	  writeq(Complete),nl,
	  add_error
	),
	fail.
compare_all_completes(AbsInt,_):-
	current_fact(complete(SgKey,AbsInt,_B,_C,_D,Id,_F)),
	Id \== no,
	Complete=complete(SgKey,AbsInt,_B,_C,_D,Id,_F),
	warning_message("extra complete ~w ~w:~n",[SgKey,Id]),
	writeq(Complete),nl,
	add_error,
	fail.
compare_all_completes(_AbsInt,_).

compare_memo_tables_with_prev(AbsInt,Flag,Direction):-
	retractall_fact(error),
	compare_all_memo_tables(AbsInt,Direction),
	(current_fact(error) ->
	    Flag = error
	;
	    true
	),
	retractall_fact(error).

compare_all_memo_tables(AbsInt,Direction):-
	current_fact(memo_table_prev(Key,AbsInt,Id,C,D,E),Ref),
	(current_fact(memo_table(Key,AbsInt,Id,C1,D1,E1),Ref2) ->
	 erase(Ref),
	 erase(Ref2),
	 ((C1 = C, 
	   D1 = D,
%	   E1 = E
	   compare_abs(Direction,AbsInt,E,E1)  
            ) ->
	     true
	 ;
	     warning_message("different memo_tables ~w ~w ~w ~w ~w~n ~w ~w ~w",[Key,Id,C,D,E,C1,D1,E1])),
	     add_error
	;
	    warning_message("missing memo_table ~w ~w",[Key,Id]),
	    add_error),
	fail.
compare_all_memo_tables(AbsInt,_):-
	current_fact(memo_table(Key,AbsInt,Id,_C,_D,_E)),
	warning_message("extra memo table ~w ~w",[Key,Id]),
	add_error,
	fail.
compare_all_memo_tables(_AbsInt,_).

remove_useless_info(AbsInt):-
	remove_useless_info_get_init_calls(AbsInt,_Initial_Comp).

remove_useless_info_get_init_calls(AbsInt,Initial_Comp):-
	collect_exported_completes(AbsInt,Initial_Comp),
	mark_useful_completes(Initial_Comp,AbsInt,[],Used_Completes),
	remove_useless_completes(AbsInt,Used_Completes),
	remove_useless_memo_tables(AbsInt,Used_Completes).

collect_exported_completes(AbsInt,Initial_Comp):-
	findall((Fs,Id),(complete(_,AbsInt,_C,_D,_E,Id,Fs),Id\==no),Completes),
	filter_exported(Completes,Initial_Comp).

filter_exported([],[]).
filter_exported([(Fs,Id)|Completes],Initial_Comp):-
	(contains_exported(Fs) ->
	 Initial_Comp = [Id|More_Comp]
	;
	    Initial_Comp = More_Comp),
	filter_exported(Completes,More_Comp).

contains_exported([(Key,_)|_]):-
	is_entrykey(Key), !.
contains_exported([_|Fs]):-
	contains_exported(Fs).

mark_useful_completes([],_AbsInt,Visited,Visited).
mark_useful_completes([Id|Ids],AbsInt,Visited,Used_Completes):-
	member(Id,Visited),!,
	mark_useful_completes(Ids,AbsInt,Visited,Used_Completes).
mark_useful_completes([Id|Ids],AbsInt,Visited,Used_Completes):-
	findall(Son,(memo_table(_,AbsInt,Id,Son,_,_),Son\==no,Son\==Id),Other_Comp),
	mark_useful_completes(Other_Comp,AbsInt,[Id|Visited],Tmp_Visited),
	mark_useful_completes(Ids,AbsInt,Tmp_Visited,Used_Completes).

remove_useless_completes(AbsInt,Used_Completes):-
	current_fact(complete(A,AbsInt,C,D,E,Id,Fs),Ref),
	(Id = no ->
	    true
	;
	    (member(Id,Used_Completes) ->
	        filter_used(Fs,Used_Completes,NFs,Flag),
		(Flag == changed ->
		    erase(Ref),
		    asserta_fact(complete(A,AbsInt,C,D,E,Id,NFs))
		;
		    true)
	    ;
		erase(Ref)
%	    ,		note_message("removing complete ~w ~w",[A,Id])
	    )
        ),
        fail.
remove_useless_completes(_AbsInt,_Used_Completes).

:- doc(remove_useless_memo_tables(AbsInt,Used_Completes), "A
    memo_table is useless when it correspond to a complete which is no
    longer used. The Id = 0 indicates that this is a special
    memo_table generated by an entry point to analysis and it is thus
    not eliminated either.").

remove_useless_memo_tables(AbsInt,Used_Completes):-
	current_fact(memo_table(_Key,AbsInt,Id,_,_,_),Ref),
	Id > 0,
	(member(Id,Used_Completes) ->
	    true
	;
	    erase(Ref)
%	,    note_message("removing memo table ~w ~w",[Key,Id])
	),
        fail.
remove_useless_memo_tables(_AbsInt,_Used_Completes).

filter_used([],_Used_Completes,[],_Flag).
filter_used([(Father,Id)|Fs],Used_Completes,NFs,Flag):-
	member(Id,Used_Completes),!,
	NFs = [(Father,Id)|MoreFs],
	filter_used(Fs,Used_Completes,MoreFs,Flag).
filter_used([(Father,Id)|Fs],Used_Completes,NFs,Flag):-
	\+ decode_litkey(Father,_,_,_,_),!,
	NFs = [(Father,Id)|MoreFs],
	filter_used(Fs,Used_Completes,MoreFs,Flag).
filter_used([_|Fs],Used_Completes,NFs,Flag):-
	Flag = changed,
	filter_used(Fs,Used_Completes,NFs,changed).

each_identical_abstract([],_,[]).
each_identical_abstract([ASub1|A1s],AbsInt,[ASub2|A2s]):-
	identical_abstract(AbsInt,ASub1,ASub2),
	each_identical_abstract(A1s,_,A2s).

:- doc(iter(Id), "A fact of this predicate should be asserted by
      the fixpoint algorithm for those completes whose success
      substitution can only be achieved iterating more than once on
      the set of clauses for the predicate. It will be used in order
      to reduce the amount of information which is stored when dumping
      analysis info.").

:- data iter/1.
