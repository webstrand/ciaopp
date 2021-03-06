%% %% VD general version of lub used for printing the output
%% :- export(compute_lub_general/3).
%% compute_lub_general(frdef,ListASub,LubASub) :- !, frdef_compute_lub_general(ListASub,LubASub).
%% compute_lub_general(def,ListASub,LubASub) :- !, def_compute_lub(ListASub,LubASub).
%% compute_lub_general(aeq,ListASub,LubASub) :- !, aeq_compute_lub(ListASub,LubASub).
%%
%% frdef_compute_lub_general(ListASub,ListASub).
%%
%% :- export(do_compute_lub/3).

%% do_compute_lub(AbsInt,SubstList,Subst) :- AbsInt = frdef, !, compute_lub_general(AbsInt,SubstList,Subst).

do_compute_lub(AbsInt,SubstList,Subst):-
    ( AbsInt = fr ; AbsInt = fd ), !, % TODO: fd vs frdef?
    compute_lub_general(AbsInt,SubstList,Subst).
do_compute_lub(AbsInt,SubstList,Subst):-
    there_is_delay, !,
    del_compute_lub(SubstList,AbsInt,Subst).
do_compute_lub(AbsInt,SubstList,Subst):-
    compute_lub_(AbsInt,SubstList,Subst).

compute_lub_general(_,_,_). % TODO: simplify? remove? (was in pool.pl)
fake_fd_extend(_,_,_,_). % TODO: simplify? remove? (was in pool.pl) % TODO: fd vs frdef?
fake_fr_extend(_,_,_,_). % TODO: simplify? remove? (was in pool.pl)

compute_lub_(_AbsInt,[],'$bottom'):- !.
compute_lub_(AbsInt,SubstList,Subst):-
    compute_lub(AbsInt,SubstList,Subst).

join_if_needed(fd,Proj,Prime,_Sg,Sv,Join):- !, % TODO: fd vs frdef?
    fake_fd_extend(Prime,Sv,Proj,Join).
join_if_needed(fr,Proj,Prime,_Sg,Sv,Join):- !,
    fake_fr_extend(Prime,Sv,Proj,Join).
join_if_needed(_,_,Prime,_,_,Prime).

free_vars_in_asub(depthk,Vars,Info,FVars):- !,
    varset(Info,AllVars),
    ord_subtract(AllVars,Vars,FVars).
free_vars_in_asub(sha,Vars,Info,FVars):- !,
    varset(Info,AllVars),
    ord_subtract(AllVars,Vars,FVars).
free_vars_in_asub(_AbsInt,_Vars,_Info,[]).
