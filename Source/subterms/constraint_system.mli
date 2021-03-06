(** Operations on extended constraint systems *)

(** {% This module regroups all operations related to constraint systems and set of constraint systems. This include in particular the
    generation of most general solustions defined in~\citepaper{Definition}{def:most_general_solutions} and all the normalisation and
    and transformation rules described in~\citepaper{Section}{sec:normalisation_rule} and~\citepaper{Section}{sec:transformation rules}.%} *)

open Term

(** {2 Constraint systems} *)

(** {% Corresponds to the extended constraint system defined in~\citepaper{Definition}{def:extended constraint system}. Note that the constraint systems
    may contain some additional data of type ['a]. %}*)
type 'a t

(** The type [constraint_system] does not represents the unsatisfiable constraint system. Thus, when a function is able to detect an unsatisfiable
    constraint system, it raises the exception [Bot]. *)
exception Bot

(** {3 Access functions} *)

(** Retreive the additional data contained in the contraint system. *)
val get_additional_data : 'a t -> 'a

(** [get_substitution_solution at] {% $\C$ %} returns {% $\mguset{\equality{\Equn(\C)}}$ %} when [at = Prococol] and returns {% $\mguset{\equality{\Eqdeux(\C)}}$ %} when [at = Recipe].*)
val get_substitution_solution : ('a, 'b) atom -> 'c t -> ('a, 'b) Subst.t

(** [get_vars_with_list at] {% $\C$ %} [l] adds the variables in {% $\C$ %} in the list [l]. Note that it does not cover the potential variables in the additional data. The addition of a variable as the union of sets, i.e. there is no dupplicate in the resulting list. *)
val get_vars_with_list : ('a, 'b) atom -> 'c t -> ('a, 'b) variable list -> ('a, 'b) variable list

(** [get_names_with_list] {% $\C$ %} [l] adds the names in {% $\C$ %} in the list [l]. Note that it does not cover the potential names in the additional data. The addition of a name as the union of sets, i.e. there is no dupplicate in the resulting list..*)
val get_names_with_list : 'a t ->  name list -> name list

(** [get_axioms_with_list] {% $\C$ %} [l] adds the axiom in {% $\C$ %} in the list [l]. Note that it does not cover the potential axioms in the additional data. The addition of an axiom as the union of sets, i.e. there is no dupplicate in the resulting list..*)
val get_axioms_with_list : 'a t -> axiom list -> axiom list

(** {3 Generators} *)

(** [create_from_free_names data] {% $[\ax_{-n};\ldots; \ax_0]$ returns the contraint system $\C = \ecsys{\emptyset}{\emptyset}{\top}{\top}{\Solved}{\emptyset}{\emptyset}$
    where $\Solved = \\{ \dedfact{\ax_0}{k_0}; \dedfact{\ax_{-1}}{k_1}; \ldots; \dedfact{\ax_{-n}}{k_n} \\}$ where for all $i$, $k_i$ is associated to $\ax_{-i}$. %}
    @raise Internal_error if the names {% $k_0, \ldots, k_n$ are not all public. \highdebug %} *)
val empty : 'a -> 'a t

(** [add_basic_fact] {% $\C$~$\dedfact{\quanti{X}{i}}{t}$ returns the constraint system $\C[ \Df \mapsto \Df \cup \dedfact{\quanti{X}{i}}{t}; \InitInput \mapsto \InitInput \cup \{X\}]$. %}
    @raise Internal_error if {% $t\mguset{\equality{\Equn(\C)}} \neq t$ or $X \in \varsdeux{\C}$. %} *)
val add_basic_fact : 'a t -> BasicFact.t -> 'a t

(** [add_axiom] {% $\C$~$\ax_n$~$t$~$id$ returns the constraint system $\C'$ obtained from $\C$ and such that
    $\Phi(\C') = \Phi(\C) \cup \{ \ax_n \rightarrow t\}$ and $\USolved(\C') = \USolved(\C) \cup \\{ \dedfact{\ax_n}{t}\\}$.%}
    Note that the deduction formula added to {% $\USolved$ %} is given [id] as recipe equivalence.
    @raise Internal_error if {% $|\Phi(\C)| \neq n-1$ \highdebug %} *)
val add_axiom : 'a t -> axiom -> protocol_term -> 'a t

(** [add_disequations at] {% $\C$ %} [l] where the list [l] is {% $\phi_1$;\ldots; $\phi_n$ %} returns the constraint system
    {% $\C[\Equn \mapsto \Equn \wedge \bigwedge_{i=1}^n \phi_i]\Vnorm$ when %} [at = Protocol] and returns
    {% $\C[\Equn \mapsto \Equn \wedge \bigwedge_{i=1}^n \phi_i]\Vnorm$ when %} [at = Recipe].
    @raise Bot when the resulting constraint system is unsatisfiable. *)
val add_disequations : 'a t -> (Term.fst_ord, Term.name) Term.Diseq.t list -> 'a t

val add_private_channels : 'a t -> protocol_term list -> 'a t

(** Replace the additional data in the constraint system by the one given as argument. *)
val replace_additional_data : 'a t -> 'a -> 'a t

(** [apply_substitution] {% $\C$~$\sigma$ returns $\C\sigma\Vnorm$.%}
    @raise Bot if {% $\C\sigma\Vnorm = \bot$. %}
    @raise Internal_error if {% $\forall \sigma', \sigma \neq \Cmgu{\C}\sigma'$. \highdebug %} *)
val apply_substitution : 'a t -> (fst_ord, name) Subst.t -> 'a t

(** [instantiate_when_solved] {% $\C$ %} consider a constraint system {% $\C$ in solved form and extract a solution
    from $\C$ by instantiating all second-order variable in $\Df(\C)$ with fresh names.%}
    @raise Internal_error if {% $\C$ %} is not in solved form. *)
val instantiate_when_solved : 'a t -> (fst_ord, name) Subst.t * (snd_ord, axiom) Subst.t

(** {3 Display function} *)

val display : Display.output -> ?rho: display_renamings option -> ?hidden:bool -> ?id:int -> 'a t -> string

(** {2 Most general solustions} *)

(** This section focuses on computing the most general solutions of a constraint system. {% Compare to~\paper, %}there
    are a few differences of syntax.*)

(** {% In \citepaper{Definition}{def:most_general_solutions}, a most general solution is only a substitution of
    recipes. In the code, the most general solutions of a constraint system are represented as a substitution of recipe and a list of
    second order variables. Typically, the variables represents the variables of the substitutions that are not in
    the constraint system. Formally, given a constraint system $\C$, an element of type %} [most_general_solution] {% is a pair
    $(\Sigma,S)$ such that $\Sigma \in \mgs{\C}$ and $S = \varsdeux{\Sigma} \setminus \varsdeux{\C}$. %} *)
type mgs


(** {% In~\citepaper{Lemma}{lem:most_general_solutions}, we gives the conditions that ensures the existence of a finite
    set of most general unifier. The type%} [simple_constraint_system] represent the constraint systems that satisfiy these conditions. *)
type simple

(** [mgs] {% $\C$ returns a list of elements $(\Sigma,\sigma,\C')$ such that $\Sigma \in \mgs{\C}$, $\C' = \CApply{\Sigma}{\C}$
    and $\mguset{\C'} = \mguset{\C}\sigma$.%} *)
val mgs : simple -> mgs list

(** [one_mgs] {% $\C$ %} returns one element of the list returned by [most_general_solutions] {% $\C$ %}.
    @raise Not_found when [most_general_solutions] {% $\C$ %} returns the empty list. *)
val one_mgs : simple -> mgs option

(** {3 Access} *)

(** [get_vars_simple_with_list at] {% $\C$ %} [l] adds the variables in {% $\C$ %} in the list [l]. Note that it does not cover the potential variables in the additional data. The addition of a variable as the union of sets, i.e. there is no dupplicate in the resulting list. *)
val get_vars_simple_with_list : ('a, 'b) atom -> simple -> ('a, 'b) variable list -> ('a, 'b) variable list

(** [get_names_simple_with_list] {% $\C$ %} [l] adds the names in {% $\C$ %} in the list [l]. Note that it does not cover the potential names in the additional data. The addition of a name as the union of sets, i.e. there is no dupplicate in the resulting list..*)
val get_names_simple_with_list : simple ->  name list -> name list

(** [get_axioms_simple_with_list] {% $\C$ %} [l] adds the axiom in {% $\C$ %} in the list [l]. Note that it does not cover the potential axioms in the additional data. The addition of an axiom as the union of sets, i.e. there is no dupplicate in the resulting list..*)
val get_axioms_simple_with_list : simple -> axiom list -> axiom list

(** {3 Display functions} *)

val display_mgs : Display.output -> ?rho: display_renamings option -> mgs -> string

val display_simple : Display.output -> ?rho: display_renamings option -> ?hidden:bool -> ?id:int -> simple -> string

(** {2 Set of constraint systems} *)

module Set : sig

  (** An alias for the type of constraint systems. *)
  type 'a csys = 'a t

  (** The type of set of constraint systems. *)
  type 'a t

  (** The empty set of contraint system *)
  val empty : 'a t

  (** [add] {% $\C$~$S$ returns $S \cup \{ \C \}$. %}*)
  val add : 'a csys -> 'a t -> 'a t

  val optimise_snd_ord_recipes : 'a t -> 'a t

  val elements : 'a t -> 'a csys list

  (** [choose] {% $S$ returns one constraint system in $S$. %}
      @raise Internal_error if the set is empty. *)
  val choose : 'a t -> 'a csys

  (** [for_all f] {% $S$ %} returns [true] iff for all constraint system {% $\C \in S$, %} [f] {% $\C$ %} [= true].*)
  val for_all : ('a csys -> bool) -> 'a t -> bool

  val exists : ('a csys -> bool) -> 'a t -> bool

  val size : 'a t -> int

  (** Returns true if the set is empty. *)
  val is_empty : 'a t -> bool

  val find_representative : 'a t -> ('a csys -> bool) -> 'a csys * 'a csys

  (** [iter f] {% $S$ %} applies the function [f] to all constraint systems in {% $S$. %} Note that the order in which the constraint systems
      are passed onto [f] is unspecified. *)
  val iter : ('a csys -> unit) -> 'a t -> unit

  (** Displays the set of constraint systems by index the constraint systems as {% $\C_k, \C_{k+1}, \ldots$ where $k$ is the integer given as argument.
      The default value of $k$ is 1. %} *)
  val display: Display.output -> ?rho: display_renamings option -> ?id:int -> 'a t -> string
end

(** {2 Normalisation and transformatin rules} *)

module Rule : sig

  val apply_rules_after_input :
    bool -> ('a Set.t -> (unit -> unit) -> unit) -> 'a Set.t -> (unit -> unit) -> unit

  val apply_rules_after_output :
    bool -> ('a Set.t -> (unit -> unit) -> unit) -> 'a Set.t -> (unit -> unit) -> unit
end
