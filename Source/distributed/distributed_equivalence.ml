open Term
open Process

module EquivJob =
struct
  type shareddata = unit

  type data_standard =
    {
      chosen_semantics : semantics;
      display_trace : bool;
      no_por : bool;
      por_gen : bool;
      distributed : bool;
      hash_channel : (string, int) Hashtbl.t;

      init_proc1 : Process.process;
      init_proc2 : Process.process;

      csys_set : Equivalence.symbolic_process Constraint_system.Set.t;
      frame_size : int
    }

  type data_determinate =
    {
      init_conf1 : Process_determinate.configuration;
      init_conf2 : Process_determinate.configuration;
      no_por_d : bool;
      por_gen_d : bool;
      distributed_d : bool;

      equiv_problem : Equivalence_determinate.equivalence_problem
    }

  type data_equivalence =
    | DStandard of data_standard
    | DDeterminate of data_determinate

  type output_attack =
    | OStandard of Equivalence.symbolic_process Constraint_system.t * Process.process * Process.process
    | ODeterminate of Equivalence_determinate.symbolic_process Constraint_system.t * Process_determinate.configuration * Process_determinate.configuration

  type job =
    {
      variable_counter : int;
      name_counter : int;
      all_tuples : symbol list;
      all_projections : (symbol * symbol list) list;
      all_constructors : symbol list;
      all_destructors : symbol list;
      number_of_constructors : int;
      number_of_destructors : int;
      number_of_symbols : int;
      stored_skeletons : Rewrite_rules.stored_skeleton list;
      stored_constructors : (symbol * Data_structure.Tools.stored_constructor) list;
      trs : Por.trs;

      data_equiv : data_equivalence;
    }

  type result =
    | Equivalent
    | Not_Equivalent of output_attack

  type command =
    | Kill
    | Continue

  let initialise () = ()

  let result_equivalence = ref Equivalent

  let evaluation job =
    Variable.set_up_counter job.variable_counter;
    Name.set_up_counter job.name_counter;
    Symbol.set_up_signature
      {
        Symbol.all_t = job.all_tuples;
        Symbol.all_p = job.all_projections;
        Symbol.all_c = job.all_constructors;
        Symbol.all_d = job.all_destructors;
        Symbol.nb_c = job.number_of_constructors;
        Symbol.nb_d = job.number_of_destructors;
        Symbol.nb_symb = job.number_of_symbols
      };
    Rewrite_rules.setup_stored_skeletons job.stored_skeletons;
    Data_structure.Tools.setup_stored_constructors job.stored_constructors;

    match job.data_equiv with
      | DStandard data ->
          Config.display_trace := data.display_trace;
          Config.no_por := data.no_por ;
          Config.por_gen := data.por_gen ;
          Config.distributed := data.distributed ;
          Por.hash_channel := data.hash_channel  ;
          let rec apply_rules trs csys_set frame_size f_next =
            Equivalence.apply_one_transition_and_rules_for_trace_equivalence data.chosen_semantics trs csys_set frame_size apply_rules f_next
          in

          begin try
            apply_rules job.trs data.csys_set data.frame_size (fun () -> ());
            Equivalent
          with
            | Equivalence.Not_Trace_Equivalent csys -> Not_Equivalent (OStandard (csys, data.init_proc1, data.init_proc2))
          end
      | DDeterminate data ->
         Config.distributed := data.distributed_d ;
         let rec apply_rules equiv_pbl f_next =
            Equivalence_determinate.apply_one_transition_and_rules equiv_pbl (fun eq_pbl_1 f_next_1 ->
              apply_rules eq_pbl_1 f_next_1
            ) f_next
          in

          begin try
            apply_rules data.equiv_problem (fun () -> ());
            Equivalent
          with
            | Equivalence_determinate.Not_Trace_Equivalent csys -> Not_Equivalent (ODeterminate (csys, data.init_conf1, data.init_conf2))
          end

  let digest result = match result with
    | Equivalent -> Continue
    | Not_Equivalent output_attack -> result_equivalence := Not_Equivalent output_attack; Kill

  type generated_jobs =
    | Jobs of job list
    | Result of result

  let generate_jobs job =
    Variable.set_up_counter job.variable_counter;
    Name.set_up_counter job.name_counter;
    Symbol.set_up_signature
      {
        Symbol.all_t = job.all_tuples;
        Symbol.all_p = job.all_projections;
        Symbol.all_c = job.all_constructors;
        Symbol.all_d = job.all_destructors;
        Symbol.nb_c = job.number_of_constructors;
        Symbol.nb_d = job.number_of_destructors;
        Symbol.nb_symb = job.number_of_symbols
      };
    Rewrite_rules.setup_stored_skeletons job.stored_skeletons;
    Data_structure.Tools.setup_stored_constructors job.stored_constructors;

    match job.data_equiv with
      | DStandard data ->
          Config.display_trace := data.display_trace;
          begin try
            let job_list = ref [] in
            Equivalence.apply_one_transition_and_rules_for_trace_equivalence data.chosen_semantics job.trs data.csys_set data.frame_size
              (fun trs_new csys_set_1 frame_size_1 f_next_1 ->
                job_list := { job with data_equiv = DStandard { data with csys_set = csys_set_1; frame_size = frame_size_1 }; variable_counter = Variable.get_counter (); name_counter = Name.get_counter (); trs = trs_new } :: !job_list;
                f_next_1 ()
              )
              (fun () -> ());
            if !job_list = []
            then Result Equivalent
            else Jobs !job_list
          with
            | Equivalence.Not_Trace_Equivalent csys -> Result (Not_Equivalent (OStandard (csys, data.init_proc1, data.init_proc2)))
          end
      | DDeterminate data ->
          begin try
            let job_list = ref [] in
            Equivalence_determinate.apply_one_transition_and_rules data.equiv_problem
              (fun equiv_pbl_1 f_next_1 ->
                job_list := { job with data_equiv = DDeterminate { data with equiv_problem = equiv_pbl_1 }; variable_counter = Variable.get_counter (); name_counter = Name.get_counter () } :: !job_list;
                f_next_1 ()
              )
              (fun () -> ());

            if !job_list = []
            then Result Equivalent
            else Jobs !job_list
          with
            | Equivalence_determinate.Not_Trace_Equivalent csys -> Result (Not_Equivalent (ODeterminate (csys, data.init_conf1, data.init_conf2)))
          end
end


module DistribEquivalence = Distrib.Distrib(EquivJob)

let trace_equivalence semantics proc1 proc2 trs =

  (*** Initialise skeletons ***)

  Rewrite_rules.initialise_skeletons ();
  Data_structure.Tools.initialise_constructor ();

  (*** Generate the initial constraint systems ***)

  let symb_proc_1 =
    {
      Equivalence.origin_process = Equivalence.Left;
      Equivalence.current_process = proc1;
      Equivalence.trace = Trace.empty
    }
  and symb_proc_2 =
    {
      Equivalence.origin_process = Equivalence.Right;
      Equivalence.current_process = proc2;
      Equivalence.trace = Trace.empty
    }
  in

  let csys_1 = Constraint_system.empty symb_proc_1 in
  let csys_2 = Constraint_system.empty symb_proc_2 in

  (**** Generate the initial set ****)

  let csys_set_1 = Constraint_system.Set.add csys_1 Constraint_system.Set.empty in
  let csys_set_2 = Constraint_system.Set.add csys_2 csys_set_1 in

  let setting = Symbol.get_settings () in
  let v_counter = Variable.get_counter () in
  let n_counter = Name.get_counter () in

  let data_standard =
    {
      EquivJob.chosen_semantics = semantics;
      EquivJob.display_trace = !Config.display_trace;
      EquivJob.no_por = !Config.no_por;
      EquivJob.por_gen = !Config.por_gen;
      EquivJob.distributed = !Config.distributed;
      EquivJob.hash_channel = !Por.hash_channel;

      EquivJob.init_proc1 = proc1;
      EquivJob.init_proc2 = proc2;

      EquivJob.csys_set = csys_set_2;
      EquivJob.frame_size = 0;
    }
  in

  let job =
    {
      EquivJob.variable_counter = v_counter;
      EquivJob.name_counter = n_counter;
      EquivJob.all_tuples = setting.Term.Symbol.all_t;
      EquivJob.all_projections = setting.Term.Symbol.all_p;
      EquivJob.all_constructors = setting.Term.Symbol.all_c;
      EquivJob.all_destructors = setting.Term.Symbol.all_d;
      EquivJob.number_of_constructors = setting.Term.Symbol.nb_c;
      EquivJob.number_of_destructors = setting.Term.Symbol.nb_d;
      EquivJob.number_of_symbols = setting.Term.Symbol.nb_symb;
      EquivJob.stored_skeletons = Rewrite_rules.retrieve_stored_skeletons ();
      EquivJob.stored_constructors = Data_structure.Tools.retrieve_stored_constructors ();
      EquivJob.trs = trs;
      
      EquivJob.data_equiv = EquivJob.DStandard data_standard;
    }
  in

  Printf.printf "Starting distributed computing...\n%!";

  (**** Launch the jobs in parallel ****)

  EquivJob.result_equivalence := EquivJob.Equivalent;

  DistribEquivalence.compute_job () job;

  (**** Return the result of the computation ****)

  match !EquivJob.result_equivalence with
    | EquivJob.Equivalent -> Equivalence.Equivalent, proc1, proc2
    | EquivJob.Not_Equivalent (EquivJob.OStandard(csys, init_proc1, init_proc2)) -> ((Equivalence.Not_Equivalent csys), init_proc1, init_proc2)
    | _ -> Config.internal_error "[distributed_equivalence.ml >> trace_equivalence] We should expect an output for standard equivalence."

let trace_equivalence_determinate conf1 conf2 =

  (*** Initialise skeletons ***)

  Rewrite_rules.initialise_skeletons ();
  Data_structure.Tools.initialise_constructor ();

  (*** Generate the initial constraint systems ***)

  let symb_proc_1 =
    {
      Equivalence_determinate.origin_process = Equivalence_determinate.Left;
      Equivalence_determinate.configuration = Process_determinate.clean_inital_configuration conf1;
    }
  and symb_proc_2 =
    {
      Equivalence_determinate.origin_process = Equivalence_determinate.Right;
      Equivalence_determinate.configuration = Process_determinate.clean_inital_configuration conf2;
    }
  in
  let else_branch =
    Process_determinate.exists_else_branch_initial_configuration symb_proc_1.Equivalence_determinate.configuration ||
    Process_determinate.exists_else_branch_initial_configuration symb_proc_2.Equivalence_determinate.configuration in

  let comp_conf1, comp_conf2 = Process_determinate.compress_initial_configuration symb_proc_1.Equivalence_determinate.configuration symb_proc_2.Equivalence_determinate.configuration in

  let symb_proc_1' = { symb_proc_1 with Equivalence_determinate.configuration = comp_conf1 }
  and symb_proc_2' = { symb_proc_2 with Equivalence_determinate.configuration = comp_conf2 } in

  let csys_1 = Constraint_system.empty symb_proc_1' in
  let csys_2 = Constraint_system.empty symb_proc_2' in

  (**** Generate the initial set ****)

  let csys_set_1 = Constraint_system.Set.add csys_1 Constraint_system.Set.empty in
  let csys_set_2 = Constraint_system.Set.add csys_2 csys_set_1 in

  let setting = Symbol.get_settings () in
  let v_counter = Variable.get_counter () in
  let n_counter = Name.get_counter () in

  let equiv_pbl = Equivalence_determinate.initialise_equivalence_problem else_branch csys_set_2 in

  let data =
    {
      EquivJob.init_conf1 = conf1;
      EquivJob.init_conf2 = conf2;
      EquivJob.no_por_d = !Config.no_por;
      EquivJob.por_gen_d = !Config.por_gen;
      EquivJob.distributed_d = !Config.distributed;
      EquivJob.equiv_problem = equiv_pbl
    }
  in

  let job =
    {
      EquivJob.variable_counter = v_counter;
      EquivJob.name_counter = n_counter;
      EquivJob.all_tuples = setting.Term.Symbol.all_t;
      EquivJob.all_projections = setting.Term.Symbol.all_p;
      EquivJob.all_constructors = setting.Term.Symbol.all_c;
      EquivJob.all_destructors = setting.Term.Symbol.all_d;
      EquivJob.number_of_constructors = setting.Term.Symbol.nb_c;
      EquivJob.number_of_destructors = setting.Term.Symbol.nb_d;
      EquivJob.number_of_symbols = setting.Term.Symbol.nb_symb;
      EquivJob.stored_skeletons = Rewrite_rules.retrieve_stored_skeletons ();
      EquivJob.stored_constructors = Data_structure.Tools.retrieve_stored_constructors ();
      EquivJob.trs = Por.emptySetTraces;

      EquivJob.data_equiv = EquivJob.DDeterminate data ;
    }
  in

  Printf.printf "Starting distributed computing...\n%!";

  (**** Launch the jobs in parallel ****)

  EquivJob.result_equivalence := EquivJob.Equivalent;

  DistribEquivalence.compute_job () job;

  (**** Return the result of the computation ****)

  match !EquivJob.result_equivalence with
    | EquivJob.Equivalent -> Equivalence_determinate.Equivalent, conf1, conf2
    | EquivJob.Not_Equivalent (EquivJob.ODeterminate (csys, init_proc1, init_proc2)) -> ((Equivalence_determinate.Not_Equivalent csys), init_proc1, init_proc2)
    | _ -> Config.internal_error "[distributed_equivalence.ml >> trace_equivalence_determinate] We should expect an output for determinate equivalence."
