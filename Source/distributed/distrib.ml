open Extensions

(** This is the module type for a task that need to be computed *)
module type TASK =
  sig
    (** [shareddata] is a type for data needed by all the computation*)
    type shareddata

    (** This is the type of a job *)
    type job

    (** This is the type for the result of one job computation*)
    type result

    type command =
      | Kill
      | Continue

    (** The function [initialise] will be run only once by the child processes when they are created. *)
    val initialise : shareddata -> unit

    (** The function [evaluation job] will be run the child processes. The argument [job] is read from the standard input channel, i.e., [stdin]
        of the child process and the result is output on its standard channel, i.e. [stdout]. Note that for this reasons, it is important
        that the function [evaluation] never write or read anything respectively on its standard output channel and from its standard input channel. *)
    val evaluation : (unit -> bool) -> (job list -> unit) -> job -> result

    (** Upon receiving a result [r] from a child process, the master process will run [digest r job_l] where [job_l] is the reference toward the list of jobs.
        The purpose of this function is to allow the master process to update the job lists depending of the result it received from the child processes. *)
    val digest : result -> command
  end

module Distrib = functor (Task:TASK) ->
struct

    type request =
      | ComputeJob of Task.job
      | JobList
      | OK

    type reply_worker =
      | Result of Task.result
      | AddJobList of Task.job list

    (****** Setting up the workers *******)

    let workers = ref []

    let local_workers n = workers := ("./worker",n) :: !workers

    let add_distant_worker machine path n =
      if path.[(String.length path) - 1] = '/'
      then workers := (Printf.sprintf "ssh %s %sworker" machine path, n) :: !workers
      else workers := (Printf.sprintf "ssh %s %s/worker" machine path, n) :: !workers

    (****** The workers' main function ******)

    let check_request = ref (Unix.time ())

    (*let _ = Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> check_request := true))*)

    (** The stdin should be non blocking *)
    let is_request_received () =
      if Unix.time () -. !check_request > 2.
      then
        begin
          begin try
            begin match ((input_value stdin):request) with
              | JobList -> true
              | _ -> Config.internal_error "[distrib.ml] The worker should not receive a compute job request at that moment."
            end
          with
            | Sys_blocked_io -> check_request := Unix.time (); false
          end
        end
      else false

    let send_jobs job_list =
      output_value stdout (AddJobList job_list);
      flush stdout;
      Unix.clear_nonblock Unix.stdin;
      let _ = input_value stdin in
      Unix.set_nonblock Unix.stdin;
      check_request := Unix.time ()


      (*check_request := false;
      ignore (Unix.alarm 1)*)

    let worker_main () =

      let shared = ((input_value stdin):Task.shareddata) in
      Task.initialise shared;

      try
        while true do
          match input_value stdin with
            | ComputeJob job ->
                Unix.set_nonblock Unix.stdin;
                let result = Task.evaluation is_request_received send_jobs job in
                Unix.clear_nonblock Unix.stdin;
                output_value stdout (Result result);
                flush stdout
            | _ -> ()
        done
      with
        | End_of_file -> ()
        | x -> raise x

    (****** The server main function *******)

    let compute_job shared job_list =

      let job_list_ref = ref job_list in

      let rec create_processes = function
        | [] -> []
        | (_,0)::q -> create_processes q
        | (proc,n)::q ->
            let (in_ch,out_ch) = Unix.open_process proc in
            output_value out_ch shared;
            flush out_ch;
            (in_ch,out_ch)::(create_processes ((proc,n-1)::q))
      in

      let processes_in_out_ch = create_processes !workers in

      let processes_in_Unix_out_ch = List.map (fun (x,y) -> Unix.descr_of_in_channel x,y) processes_in_out_ch in

      let active_processes = ref [] in
      let idle_processes = ref (List.map fst processes_in_Unix_out_ch) in

      begin try

        while !active_processes <> [] || !job_list_ref <> [] do
          (*** Send jobs to idle worker when jobs are available ***)
          while !idle_processes <> [] && !job_list_ref <> [] do
            let in_ch_unix = List.hd !idle_processes in
            let out_ch = List.assoc in_ch_unix processes_in_Unix_out_ch in
            output_value out_ch (ComputeJob (List.hd !job_list_ref));
            flush out_ch;
            idle_processes := List.tl !idle_processes;
            job_list_ref := List.tl !job_list_ref;
            active_processes := in_ch_unix :: !active_processes;
          done;

          Printf.printf "\x0dNumber of active process : %d, Current job : %d             %!" (List.length !active_processes) (List.length !job_list_ref);

          (*** If not enough jobs for the number of worker ***)

          if !idle_processes <> [] && !job_list_ref = []
          then
            begin
              List.iter (fun in_ch_unix ->
                let out_ch = List.assoc in_ch_unix processes_in_Unix_out_ch in
                output_value out_ch JobList;
                flush out_ch;
              ) !active_processes;

              let tmp_active_process = !active_processes in

              List.iter (fun in_Unix_ch ->
            	  let in_ch = Unix.in_channel_of_descr in_Unix_ch in
                match input_value in_ch with
                  | AddJobList job_list ->
                      job_list_ref := List.rev_append job_list !job_list_ref;
                      let out_ch = List.assoc in_Unix_ch processes_in_Unix_out_ch in
                      output_value out_ch OK;
                      flush out_ch
                  | Result result ->
                      begin
                    	  match Task.digest result with
                          | Task.Kill -> raise Not_found
                          | Task.Continue ->
                              active_processes := List.filter_unordered (fun x -> x <> in_Unix_ch) !active_processes;
                              idle_processes := in_Unix_ch :: !idle_processes
                      end
            	) tmp_active_process

            end
          else
            begin

              (*** Wait answer from workers ***)

              let (available_in_Unix_ch,_,_) = Unix.select !active_processes [] [] (-1.) in

              List.iter (fun in_Unix_ch ->
            	  let in_ch = Unix.in_channel_of_descr in_Unix_ch in
                let value_in = input_value in_ch in
                match value_in with
                  | AddJobList _ -> Printf.printf "Should not happen\n%!"
                  | Result result ->
                      begin
                    	  match Task.digest result with
                          | Task.Kill -> raise Not_found
                          | Task.Continue ->
                              active_processes := List.filter_unordered (fun x -> x <> in_Unix_ch) !active_processes;
                              idle_processes := in_Unix_ch :: !idle_processes
                      end
            	) available_in_Unix_ch
            end
        done
      with Not_found -> ()
      end;

      List.iter (fun x -> ignore (Unix.close_process x)) processes_in_out_ch
end
