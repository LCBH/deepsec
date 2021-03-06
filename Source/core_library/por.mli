(** This module interfaces Porridge (generalized POR) with DeepSec *)

(** Abstract type for sets of symbolic traces to be explored *)
type trs
type actionA = Process.visAct

(** Need to be marshaled: Associates channel representation from DeepSec to channel representation of Porridge. *)
val hash_channel : (string, int) Hashtbl.t ref

(** Empty set of traces. *)
val emptySetTraces : trs

(** Returns true when a given term representing a In/Out(channel) in DeepSec is enable in the given set of traces. *)
val isEnable : Process.Trace.t -> trs -> (actionA option * trs) option

(** Returns continuation of traces after some DeepSec-action. Raise Not_found when the action is not enable. *)
val forwardTraces : actionA -> trs -> trs

(** [importProcess p] gives the LTS representation of a process [p]. *)
val importProcess : Process.expansed_process -> Porridge.Process.t

(** [importProcess lp1 lp2] compute the reduced set of traces to be explored associated to [[p1;0 || p2;0]]. *)
val computeTraces : Porridge.Process.t -> Porridge.Process.t -> trs

(** Display a set of symbolic traces *)
val displaySetTraces : trs -> unit

(** Display the action-LTS representation of an DeepSec-action. *)
val displayActPor : actionA -> string
