:- module(fixpo_check_di,
	[ query/8,
	  init_fixpoint/0,
	  cleanup_fixpoint/1,
	  entry_to_exit/7
	],
	[assertions, datafacts, isomodes, nativeprops]).

:- use_package(.(notrace)). % inhibits the tracing
:- use_package(spec(no_debug)).

:- doc(title,"A Fixpoint Checker").

:- doc(author, "Germ@'{a}n Puebla").

:- doc(module," This module contains the implementation of an
	algorithm for checking that an existing analysis result (set
	of completes) is indeed an analysis fixpoint for the
	program. Can be used for proof-carrying-code.").

:- doc(stability, devel).
:- doc(bug, "ignores completes generated by meta-calls").

:- include(fixpo_dx_common).


:- use_module(ciaopp(plai/fixpo_ops), [fixpoint_id_reuse_prev_success/6, 
	                        each_identical_abstract/3]).

:- use_module(library(messages), [error_message/1]).

:- use_module(library(lists), [member/2]).

%------------------------------------------------------------------------%
:- doc(bug,"Check analysis of meta_calls works after introducing
        fixpoint_reuse_prev_id/5").
%------------------------------------------------------------------------%

%------------------------------------------------------------------------%
%                                                                        %
%                          started: 1/10/2003                            %
%              programmer :    A. G. Puebla Sanchez                      %
%------------------------------------------------------------------------%

:- doc(init_fixpoint/0,"Cleanups the database of analysis of
	temporary information.").
init_fixpoint:-
	trace_fixp:cleanup,
	set_pp_flag(widen,off). % TODO: fix!

%------------------------------------------------------------------------%
% call_to_success(+,+,+,+,+,+,-,-,+,+)                                   %
% call_to_success(SgKey,Call,Proj,Sg,Sv,AbsInt,Succ,F,N,NewN)            %
% It obtains the Succ for a given Sg and Call.                           %
%  This fixpoint algorithm uses the information in complete even if it   %
% is not really complete. Whenever a change in a complete is detected    %
% analysis starts for each clause that uses that complete from the       %
% literal that uses the complete. This makes incremental analysis        %
% in a bottom-up way. Each change in a complete forces a re-analysis of  %
% all the completes that used it and so recursively. The danger of       %
% bottom-up strategy is that it can re-analyse completes that may not be %
% needed. This introduces extra-work. The advantaje of bottom-up strategy%
% over top-down is that if the effect of the change is local, the        %
% analysis time will be small in general.                                %
%------------------------------------------------------------------------%
call_to_success(SgKey,Call,Proj,Sg,Sv,AbsInt,_ClId,Succ,F,N,Id) :-
	current_fact(complete(SgKey,AbsInt,Subg,Proj1,Prime1,Id,Fs),Ref),
	identical_proj(AbsInt,Sg,Proj,Subg,Proj1),!,
	reuse_complete(Ref,SgKey,Proj,Sg,AbsInt,F,N,Id,Fs,Prime1,Prime),
	each_extend(Sg,Prime,AbsInt,Sv,Call,Succ).
call_to_success(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,Succ,F,N,Id) :-
	init_fixpoint0(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,Prime),
	each_extend(Sg,Prime,AbsInt,Sv,Call,Succ).


reuse_complete(Ref,SgKey,Proj,Sg,AbsInt,F,N,Id,Fs,Prime1,Prime):-
	each_abs_sort(Prime1,AbsInt,Prime),
	check_if_parent_needed(Fs,F,N,NewFs,Flag),
	(Flag == needed ->
	    erase(Ref),
	    asserta_fact(complete(SgKey,AbsInt,Sg,Proj,Prime,Id,NewFs))
	;
	    true).

init_fixpoint0(SgKey,Call,Proj0,Sg,Sv,AbsInt,ClId,F,N,Id,Prime):-
	current_pp_flag(widen,on),
	current_pp_flag(multi_success,off),
	widen_call(AbsInt,SgKey,Sg,F,N,Proj0,Proj), !,
	init_fixpoint1(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,Prime).
init_fixpoint0(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,Prime):-
	init_fixpoint_(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,Prime).

init_fixpoint1(SgKey,_Call,Proj,Sg,_Sv,AbsInt,_ClId,F,N,Id,Prime):-
	current_fact(complete(SgKey,AbsInt,Subg,Proj1,Prime1,Id,Fs),Ref),
	identical_proj(AbsInt,Sg,Proj,Subg,Proj1),!,
	reuse_complete(Ref,SgKey,Proj,Sg,AbsInt,F,N,Id,Fs,Prime1,Prime).
init_fixpoint1(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,Prime):-	
	init_fixpoint_(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,Prime).

init_fixpoint_(SgKey,Call,Proj,Sg,Sv,AbsInt,_ClId,F,N,Id,Prime):-
	bagof(X, Y^X^(trans_clause(SgKey,Y,X)),Clauses), !,
	(fixpoint_id_reuse_prev_success(SgKey,AbsInt,Sg,Proj,Id,TmpPrime) ->
	    asserta_fact(complete(SgKey,AbsInt,Sg,Proj,TmpPrime,Id,[])),
	    compute(Clauses,SgKey,Sg,Sv,Call,Proj,AbsInt,TmpPrime,_,Id)

	;
	    error_message("certificate check failed: missing entry in analysis answer table"),
	    asserta_fact(complete(SgKey,AbsInt,Sg,Proj,['$bottom'],Id,[])),
	    compute(Clauses,SgKey,Sg,Sv,Call,Proj,AbsInt,['$bottom'],_,Id)),
	current_fact(complete(SgKey,AbsInt,Sg,_,Prime_u,Id,Fs2),Ref),
	reuse_complete(Ref,SgKey,Proj,Sg,AbsInt,F,N,Id,Fs2,Prime_u,Prime).
init_fixpoint_(SgKey,_Call,Proj,Sg,Sv,AbsInt,ClId,F,N,Id,LPrime) :-
	apply_trusted0(Proj,SgKey,Sg,Sv,AbsInt,ClId,Prime), !,
	fixpoint_id_reuse_prev_success(SgKey,AbsInt,Sg,Proj,Id,TmpPrime),
	singleton(Prime,LPrime),
	asserta_fact(complete(SgKey,AbsInt,Sg,Proj,LPrime,Id,[(F,N)])),
	(each_identical_abstract(LPrime,AbsInt,TmpPrime) ->
	    true
	;
	    error_message("certificate check failed: wrong analysis results due to trusts")).
init_fixpoint_(SgKey,_Call,_Proj,_Sg,_Sv,_AbsInt,ClId,_F,_N,_Id,Bot) :-
	bottom(Bot),
	inexistent(SgKey,ClId).

%------------------------------------------------------------------------
% check_if_parent_needed(+,+,+,-,-)
% check_if_parent_needed(Old_parents,F,N,NewParents,Flag)
% This way if inserting parents makes them be in the same order as they were inserted 
% thus avoiding having to reverse the list of parents

check_if_parent_needed([],F,N,[(F,N)],needed).
check_if_parent_needed([(F,N)|Fs],F,N,[(F,N)|Fs],not):-!.
check_if_parent_needed([(F1,N1)|Fs],F,N,[(F1,N1)|NewFs],Flag):-
	check_if_parent_needed(Fs,F,N,NewFs,Flag).

%-------------------------------------------------------------------------
% compute(+,+,+,+,+,+,+,+).                                              %
% compute(Clauses,SgKey,Sg,Sv,Proj,AbsInt,TempPrime,Id)                  %
% It analyses each recursive clause. After each clause, we check if the  %
% new Prime substitution is more general than it was when the previous   %
% clause was analyzed. In this case we execute compute_each_change.      %
% Note that the prime in the corresponding complete may have been modified
% due to a compute_each_change and be more general than TempPrime. This is
% the reason why call_to_success does not trust the Prime computed here  %
% and looks for it in the complete. No compute_each_change is needed     %
% because if compute_each_change has updated the complete it has already %
% recursively called compute_each_change for this complete.              %
%-------------------------------------------------------------------------

compute([],_,_,_,_,_,_,Prime,Prime,_).
compute([Clause|Rest],SgKey,Sg,Sv,Call,Proj,AbsInt,TempPrime,Prime,Id) :-
	do_cl(Clause,SgKey,Sg,Sv,Call,Proj,AbsInt,Id,TempPrime,Prime1),
	compute(Rest,SgKey,Sg,Sv,Call,Proj,AbsInt,Prime1,Prime,Id).



do_cl(Clause,SgKey,Sg,Sv,Call,Proj,AbsInt,Id,TempPrime,Prime):-
	Clause=clause(Head,Vars_u,K,Body),
	clause_applies(Head,Sg), !, 
	varset(Head,Hv),
	sort(Vars_u,Vars),
	ord_subtract(Vars,Hv,Fv),
	process_body(Body,K,AbsInt,Sg,SgKey,Hv,Fv,Vars_u,Head,Sv,Call,Proj,TempPrime,Prime,Id).

do_cl(_,_,_,_,_,_,_,_,Primes,Primes).

process_body(Body,K,AbsInt,Sg,SgKey,Hv,Fv,_Vars_u,Head,Sv,Call,Proj,TempPrime,Prime,Id):-
	Body = g(_,[],'$built'(_,true,_),'true/0',true),!,
	Help=(Sv,Sg,Hv,Fv,AbsInt),
	fixpoint_trace('visit fact',Id,_N,K,Head,Proj,Help),
	call_to_success_fact(AbsInt,Sg,Hv,Head,K,Sv,Call,Proj,One_Prime,_Succ),
	singleton(One_Prime,Prime1),
	fixpoint_trace('exit fact',Id,_N,K,Head,Prime,Help),
	each_apply_trusted(Proj,SgKey,Sg,Sv,AbsInt,Prime1,Prime2),
	widen_succ(AbsInt,TempPrime,Prime2,NewPrime),
	decide_re_analyse(AbsInt,TempPrime,NewPrime,Prime,SgKey,Sg,Id,Proj).
process_body(Body,K,AbsInt,Sg,SgKey,Hv,Fv,Vars_u,Head,Sv,_Call,Proj,TempPrime,Prime,Id):-
	call_to_entry(AbsInt,Sv,Sg,Hv,Head,not_provided,Fv,Proj,Entry,ExtraInfo),
%	erase_previous_memo_tables_and_parents(Body,K,Id),
% not needed as it is the first time this clause is analysed (?)
	fixpoint_trace('visit clause',Id,_N,K,Head,Entry,Body),
	singleton(Entry,LEntry),
	entry_to_exit(Body,K,LEntry,Exit,Vars_u,AbsInt,Id),
	fixpoint_trace('exit clause',Id,_N,K,Head,Exit,_),
	each_exit_to_prime(Exit,AbsInt,Sg,Hv,Head,Sv,ExtraInfo,Prime1),
	each_apply_trusted(Proj,SgKey,Sg,Sv,AbsInt,Prime1,Prime2),
	widen_succ(AbsInt,TempPrime,Prime2,NewPrime),
	decide_re_analyse(AbsInt,TempPrime,NewPrime,Prime,SgKey,Sg,Id,Proj).

%-------------------------------------------------------------------------
% body_succ(+,+,-,+,-,+,+,+,+)                                           %
% body_succ(Call,[Key,Sv,(I1,I2,Sg)],Succ,Hv,Fv,AbsInt,NewN)             %
% First, the lub between the abstract call substitution and the already  %
% computed information for this program point (if any) is computed. Then %
% the lub is recordered.                                                 %
% If the abstract call substitution is bottom (case handled by the first %
% clause) the success abstract substitution is also bottom and nothing   %
% more is needed. Otherwise (second clause) the computation of the       %
% success abstract substitution procceeds.                               %
%-------------------------------------------------------------------------

body_succ(Call,Atom,Succ,HvFv_u,AbsInt,_ClId,ParentId,no):- 
	bottom(Call), !,
%	bottom(Succ),
	Succ = Call,
	Atom=g(Key,_Av,_I,_SgKey,_Sg),
	asserta_fact(memo_table(Key,AbsInt,ParentId,no,HvFv_u,Succ)).
body_succ(Call,Atom,Succ,HvFv_u,AbsInt,ClId,ParentId,Id):- 
	Atom=g(Key,Sv,Info,SgKey,Sg),
	fixpoint_trace('visit goal',ParentId,ClId,Key,Sg,Call,AbsInt),
	body_succ0(Info,SgKey,Sg,Sv,HvFv_u,Call,Succ,AbsInt,ClId,Key,ParentId,Id),
	fixpoint_trace('exit goal',Id,ParentId,(SgKey,Key),Sg,Succ,AbsInt),
	decide_memo(AbsInt,Key,ParentId,Id,HvFv_u,Call).
%% 	change_son_if_necessary(Id,Key,ParentId,HvFv_u,Call,AbsInt).


% change_son_if_necessary(no,_,_,_,_,_):-!.
% change_son_if_necessary(NewId,Key,NewN,Vars_u,Call,AbsInt):-
%         current_fact(memo_table(Key,AbsInt,NewN,Id,_,_),Ref),
%         (Id = NewId ->
%             true
%         ;
%             erase(Ref),
%             decide_memo(AbsInt,Key,NewN,NewId,Vars_u,Call)).            




%-------------------------------------------------------------------------



% if Prime computed for this clause is not more general than the 
% information we already had there is no need to compare with the info
% in complete which will always be more general (and no compute_change needed)
decide_re_analyse(AbsInt,TempPrime,NewPrime,Prime,_SgKey,_Sg,_Id,_Proj):-
%w	write(r),
%%	write(user,'identical abstract'),nl(user),
	abs_subset_(NewPrime,AbsInt,TempPrime),!,
	Prime = NewPrime.
decide_re_analyse(AbsInt,_TempPrime,NewPrime,Prime,SgKey,Sg,Id,Proj):-
%w	write(n),
	current_fact(complete(SgKey,AbsInt,Sg,_,OldPrime_u,Id,Fs),Ref),
	each_abs_sort(OldPrime_u,AbsInt,OldPrime),
	widen_succ(AbsInt,OldPrime,NewPrime,Prime), 
 	(abs_subset_(Prime,AbsInt,OldPrime)->
%	    write(user,'OK, no change needed'),write(user,Fs),nl(user)
	    true
	;
%%	    write(user,'lub needed '),nl(user),
	    erase(Ref),
	    asserta_fact(complete(SgKey,AbsInt,Sg,Proj,Prime,Id,Fs)),
	    error_message("certificate check failed: incorrect answer table entry")).

%% check compute_each_change([],_AbsInt).
%% check compute_each_change([(Literal,Id)|Changes],AbsInt):-
%% check 	decode_litkey(Literal,N,A,Cl,_),
%% check 	get_predkey(N,A,SgKey),
%% check 	current_fact(complete(SgKey,AbsInt,Sg,Proj1,TempPrime1,Id,_),_),!,
%% check 	varset(Sg,Sv),
%% check 	abs_sort(AbsInt,Proj1,Proj),
%% check 	each_abs_sort(TempPrime1,AbsInt,TempPrime),
%% check 	current_fact(memo_table(Literal,AbsInt,Id,_,Vars_u,Entry),_),
%% check 	each_abs_sort(Entry,AbsInt,S_Entry),
%% check 	make_atom([N,A,Cl],Clid),
%% check 	trans_clause(SgKey,_,clause(Head,Vars_u,Clid,Body)),
%% check 	advance_in_body(Literal,Body,NewBody),
%% check 	varset(Head,Hv),
%% check 	sort(Vars_u,Vars),
%% check 	ord_subtract(Vars,Hv,Fv),
%% check 	call_to_entry(AbsInt,Sv,Sg,Hv,Head,not_provided,Fv,Proj,_,ExtraInfo),
%% check 	erase_previous_memo_tables_and_parents(NewBody,AbsInt,Clid,Id),
%% check 	entry_to_exit(NewBody,Clid,S_Entry,Exit,Vars_u,AbsInt,Id),
%% check 	each_exit_to_prime(Exit,AbsInt,Sg,Hv,Head,Sv,ExtraInfo,Prime1),
%% check 	each_apply_trusted(Proj,SgKey,Sg,Sv,AbsInt,Prime1,Prime2),
%% check 	widen_succ(AbsInt,TempPrime,Prime2,NewPrime),
%% check 	decide_re_analyse(AbsInt,TempPrime,NewPrime,_,SgKey,Sg,Id,Proj),
%% check 	compute_each_change(Changes,AbsInt).
%% check compute_each_change([_|Changes],AbsInt):- % no complete stored. Nothing
%% check 	compute_each_change(Changes,AbsInt). %need be recomputed.

% RFlag not needed (second argument). Kept for compatibility with dd.
each_call_to_success([Call],_,SgKey,Sg,Sv,HvFv_u,AbsInt,ClId,Succ,F,N,Id):- !,
	project(AbsInt,Sg,Sv,HvFv_u,Call,Proj),
	call_to_success(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,Succ,F,N,Id).
each_call_to_success(LCall,_,SgKey,Sg,Sv,HvFv_u,AbsInt,ClId,LSucc,F,N,Id):-
	each_call_to_success0(LCall,SgKey,Sg,Sv,HvFv_u,AbsInt,ClId,LSucc,F,N,Id).

each_call_to_success0([],_SgK,_Sg,_Sv,_HvFv,_AbsInt,_ClId,[],_F,_N,_NN).
each_call_to_success0([Call|LCall],SgKey,Sg,Sv,HvFv_u,AbsInt,ClId,LSucc,F,N,NewN):-
	project(AbsInt,Sg,Sv,HvFv_u,Call,Proj),
	call_to_success(SgKey,Call,Proj,Sg,Sv,AbsInt,ClId,LSucc0,F,N,_Id),
	append(LSucc0,LSucc1,LSucc),
	each_call_to_success0(LCall,SgKey,Sg,Sv,HvFv_u,AbsInt,ClId,LSucc1,F,N,NewN).


widen_call(AbsInt,SgKey,Sg,F1,Id0,Proj1,Proj):-
	( current_pp_flag(widencall,off) -> fail ; true ),
	widen_call0(AbsInt,SgKey,Sg,F1,Id0,[Id0],Proj1,Proj), !,
	fixpoint_trace('result of widening',Id0,F1,SgKey,Sg,Proj,_).

widen_call0(AbsInt,SgKey,Sg,F1,Id0,Ids,Proj1,Proj):-
	widen_call1(AbsInt,SgKey,Sg,F1,Id0,Ids,Proj1,Proj).
widen_call0(AbsInt,SgKey,Sg,F1,Id0,Ids,Proj1,Proj):-
	current_pp_flag(widencall,com_child),
	widen_call2(AbsInt,SgKey,Sg,F1,Id0,Ids,Proj1,Proj).


widen_call1(AbsInt,SgKey,Sg,F1,Id0,Ids,Proj1,Proj):-
	current_fact(complete(SgKey0,AbsInt,Sg0,Proj0,_Prime0,Id0,Fs0)),
	( SgKey=SgKey0,
	  member((F1,_NewId0),Fs0)
	-> Sg0=Sg,
	   abs_sort(AbsInt,Proj0,Proj0_s),
	   abs_sort(AbsInt,Proj1,Proj1_s),
	   widencall(AbsInt,Proj0_s,Proj1_s,Proj)
	 ; member((_F1,NewId0),Fs0),
	   \+ member(NewId0,Ids),
	   widen_call1(AbsInt,SgKey,Sg,F1,NewId0,[NewId0|Ids],Proj1,Proj)
	).

widen_call2(AbsInt,SgKey,Sg,F1,_Id,_Ids,Proj1,Proj):-
	current_fact(complete(SgKey,AbsInt,Sg0,Proj0,_Prime0,_,Fs0)),
	member((F1,_Id0),Fs0),
	Sg0=Sg,
%	same_fixpoint_ancestor(Id0,[Id0],AbsInt),
	abs_sort(AbsInt,Proj0,Proj0_s),
	abs_sort(AbsInt,Proj1,Proj1_s),
	widencall(AbsInt,Proj0_s,Proj1_s,Proj).



%-------------------------------------------------------------------------

:- doc(query(AbsInt,QKey,Query,Qv,RFlag,N,Call,Succ),
	"The success pattern of @var{Query} with @var{Call} is
         @var{Succ} in the analysis domain @var{AbsInt}. The predicate
         called is identified by @var{QKey}, and @var{RFlag} says if it
         is recursive or not. The goal @var{Query} has variables @var{Qv},
         and the call pattern is uniquely identified by @var{N}.").

query(AbsInt,QKey,Query,Qv,_RFlag,N,Call,Succ) :-
	project(AbsInt,Query,Qv,Qv,Call,Proj),
	fixpoint_trace('init fixpoint',N,N,QKey,Query,Proj,_),
	call_to_success(QKey,Call,Proj,Query,Qv,AbsInt,0,Succ,N,0,Id),
	!,
 	fixpoint_trace('exit goal',_Id,query(N),(QKey,QKey),Query,Succ,AbsInt),
	asserta_fact(memo_table(N,AbsInt,0,Id,Qv,Succ)).
query(_AbsInt,_QKey,_Query,_Qv,_RFlag,_N,_Call,_Succ):-
% should never happen, but...
	error_message("SOMETHING HAS FAILED!"),
	fail.
