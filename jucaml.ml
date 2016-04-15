module J  = Yojson.Basic
module JU = Yojson.Basic.Util

module WireIO = struct
    type t = {
        key : Cstruct.t;
        uuid: string
    }

    let create key = { 
        key  = Cstruct.of_string key; 
        uuid = Core.Uuid.(to_string @@ create ()) 
    }
    
    type wire_msg = {
        header : string;
        parent_header : string;
        metadata : string;
        content : string;
        extra : string list
    }
    
    let msg_to_list msg =
        [ msg.header; msg.parent_header; msg.metadata; msg.content] @ msg.extra

    let sign t msg =
        msg |> msg_to_list
            |> List.map Cstruct.of_string 
            |> Cstruct.concat
            |> Nocrypto.Hash.mac `SHA256 ~key:(t.key)  
            |> Hex.of_cstruct
            |> function `Hex x -> x  

    let mk_message t ?(metadata="{}") ?(extra=[]) htype parent_header content =
        let header = J.to_string @@ J.( `Assoc [
                ("date"     , `String Core.Time.( to_filename_string ( now () ) Zone.local ) );
                ("msg_id"   , `String Core.Uuid.( to_string @@ create () ) );
                ("username" , `String "kernel");
                ("session"  , `String t.uuid  );
                ("msg_type" , `String htype   );
                ("version"  , `String "0.1"   ) ]) 
            in 
        { header; parent_header; content; metadata; extra }

    let read_msg t socket =
        let message = ZMQ.Socket.recv_all socket in
        let rec scan zmqids = function
            | "<IDS|MSG>"::signature::h::p::m::c::e -> 
                let msg = { header = h; parent_header = p; metadata = m; content = c; extra = e } in 
                zmqids , signature, msg
            | zmqid::tl -> scan (zmqid::zmqids) tl
            | _ -> failwith "Malformed wire message." 
            in
        let zmqids, signature, msg = scan [] message in
        if String.compare (sign t msg) signature != 0 then
            failwith "Received a message with wrong signature."
        else zmqids, msg

    let send_msg t socket ?(zmqids=[]) msg =
        let lmsg = "<IDS|MSG>" :: sign t msg :: msg_to_list msg in
        ZMQ.Socket.send_all socket ( zmqids @ lmsg )
end

let counter = ref 0;;

let handler wireio iopub mtype  = 
    let content msg key = 
        msg.WireIO.content |> J.from_string |> JU.member key |> JU.to_string
        in
    let reply_kernel_info msg = 
        J.to_string @@ J.from_file "./kernel_info.json" 
        in
    let reply_comm msg = J.to_string @@ J.(`Assoc [
            ( "comm_id",     `String ( content msg "comm_id"     ) );
            ( "target_name", `String ( content msg "target_name" ) );
            ( "data",        `Assoc [] ) ])  
        in
    let reply_execute msg =
        counter := !counter + 1;
        let code = content msg "code" in
        let lexbuf = Lexing.from_string code in
        let phrases = !Toploop.parse_use_file lexbuf in
        phrases |> List.map (fun phrase -> 
            try 
                Toploop.execute_phrase true Format.str_formatter phrase |> ignore ;
                let reply = Format.flush_str_formatter () in
                let content = J.to_string @@ J.(`Assoc [ 
                    ("name", `String "stdout"); ("text", `String reply )]) in
                let rmsg = WireIO.mk_message wireio "stream" msg.WireIO.header content in
                WireIO.send_msg wireio iopub rmsg
            with _ -> ()
        ) |> ignore; 
        J.to_string @@ J.( `Assoc [ 
            ( "status", `String "ok" ); 
            ( "execution_count", `Int  !counter  ) ]) 
        in
    match mtype with
        | "kernel_info_request" -> "kernel_info_reply" , reply_kernel_info 
        | "comm_open"           -> "comm_close"        , reply_comm        
        | "execute_request"     -> "execute_result"    , reply_execute     

let handle wireio iopub socket =
    let zmqids, msg = WireIO.read_msg wireio socket in
    let mtype = msg.WireIO.header |> J.from_string |> JU.member "msg_type" |> JU.to_string in
    let rtype, handler = handler wireio iopub mtype in
    let content = handler msg in 
    let rmsg = WireIO.mk_message wireio rtype msg.WireIO.header content in
    WireIO.send_msg wireio socket ~zmqids:zmqids rmsg

let () =
    Toploop.initialize_toplevel_env ();

    (* Processing Jupyter-kernel settings file *)
    let filename = Sys.argv.(1) in
    let settings_str k = J.from_file filename |> JU.member k |> JU.to_string in
    let settings_int k = J.from_file filename |> JU.member k |> JU.to_int    in

    (* Setting up WireIO module *)
    let wireio = settings_str "key" |> WireIO.create in

    (* Firing up ZMQ sockets *)
    let context = ZMQ.Context.create () in
    let hb      = ZMQ.Socket.create context ZMQ.Socket.rep     
    and shell   = ZMQ.Socket.create context ZMQ.Socket.router    
    and control = ZMQ.Socket.create context ZMQ.Socket.router  
    and stdin   = ZMQ.Socket.create context ZMQ.Socket.router  
    and iopub   = ZMQ.Socket.create context ZMQ.Socket.pub   in
    let addr = Printf.sprintf "%s://%s:%d" (settings_str "transport") (settings_str "ip") in
    settings_int "hb_port"     |> addr |> ZMQ.Socket.bind hb     ;
    settings_int "shell_port"  |> addr |> ZMQ.Socket.bind shell  ;
    settings_int "control_port"|> addr |> ZMQ.Socket.bind control;
    settings_int "stdin_port"  |> addr |> ZMQ.Socket.bind stdin  ;
    settings_int "iopub_port"  |> addr |> ZMQ.Socket.bind iopub  ;

    (* Creating poller *)
    let poller = ZMQ.Poll.( mask_of 
        [|(hb,In); (shell,In); (control,In); (stdin,In) |] ) in 

    (* Entering polling loop *)
    let handle = handle wireio iopub in
    while true do
        let evts = ZMQ.Poll.poll poller in
        [ hb; shell; control; stdin ] 
        |> List.iteri ( fun i socket -> match i, evts.(i) with
            | _ , None   -> ()
            | 1 , Some _ -> handle shell 
            | n , Some _ -> () 
        )
    done
