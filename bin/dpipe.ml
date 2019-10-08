let () = Printexc.record_backtrace true

module Buffer = Decompress.Buffer
module Bigarray = Bigarray_compat

external bs_read :
  Unix.file_descr -> Buffer.Bigstring.t -> int -> int -> int
  = "bigstring_read"
  [@@noalloc]

external bs_write :
  Unix.file_descr -> Buffer.Bigstring.t -> int -> int -> int
  = "bigstring_write"
  [@@noalloc]

(** Abstract [Unix.read] with ['a Buffer.t]. *)
let unix_read : type a. a Buffer.t -> Unix.file_descr -> a -> int -> int -> int
    = function
  | Buffer.Bytes -> Unix.read
  | Buffer.Bigstring -> bs_read

let unix_write : type a.
    a Buffer.t -> Unix.file_descr -> a -> int -> int -> int = function
  | Buffer.Bytes -> Unix.write
  | Buffer.Bigstring -> bs_write

let _chunk = 0xFFFF

let do_command input_size output_size mode level algo wbits =
  let src =
    Bigarray.Array1.create Bigarray.Char Bigarray.c_layout input_size
  in
  let dst =
    Bigarray.Array1.create Bigarray.Char Bigarray.c_layout output_size
  in
  let refill dst len =
    let count = unix_write Buffer.bigstring Unix.stdout dst 0 len in
    match count with
    | -1 -> raise (Failure "Error occure: unix write returned -1")
    | _ -> output_size
  in
  match mode with
  | `Compression -> (
      let flush src max =
        let count =
          match max with
          | Some max ->
              unix_read Buffer.bigstring Unix.stdin src 0 (min max input_size)
          | None -> unix_read Buffer.bigstring Unix.stdin src 0 input_size
        in
        match count with
        | -1 -> raise (Failure "Error occure: unix read returned -1")
        | _ -> count
      in
      match algo with
      | `Gzip -> (
          let t =
            Decompress.Gzip_deflate.default ~witness:Buffer.bigstring
              ~name:"README.md" ~extra:"lolilol" ~header_crc:true level
          in
          let r = Decompress.Gzip_deflate.to_result src dst flush refill t in
          match r with
          | Ok _ -> ()
          | Error exn ->
              Format.eprintf "%a\n%!" Decompress.Gzip_deflate.pp_error exn )
      | `Zlib -> (
          let t =
            Decompress.Zlib_deflate.default ~witness:Buffer.bigstring ~wbits
              level
          in
          let r = Decompress.Zlib_deflate.to_result src dst flush refill t in
          match r with
          | Ok _ -> ()
          | Error exn ->
              Format.eprintf "%a\n%!" Decompress.Zlib_deflate.pp_error exn ) )
  | `Decompression -> (
      let flush src =
        let count = unix_read Buffer.bigstring Unix.stdin src 0 input_size in
        match count with
        | -1 -> raise (Failure "Error occure: read write returned -1")
        | _ -> count
      in
      match algo with
      | `Gzip -> (
          let w =
            Decompress.Window.create ~crc:Decompress.Window.crc32
              ~witness:Buffer.bigstring
          in
          let t =
            Decompress.Gzip_inflate.default ~witness:Buffer.bigstring w
          in
          let r = Decompress.Gzip_inflate.to_result src dst flush refill t in
          match r with
          | Ok _ -> ()
          | Error exn ->
              Format.eprintf "%a\n%!" Decompress.Gzip_inflate.pp_error exn )
      | `Zlib -> (
          let w =
            Decompress.Window.create ~crc:Decompress.Window.adler32
              ~witness:Buffer.bigstring
          in
          let t =
            Decompress.Zlib_inflate.default ~witness:Buffer.bigstring w
          in
          let r = Decompress.Zlib_inflate.to_result src dst flush refill t in
          match r with
          | Ok _ -> ()
          | Error exn ->
              Format.eprintf "%a\n%!" Decompress.Zlib_inflate.pp_error exn ) )

open Cmdliner

let nat a b =
  let parse s =
    try
      let v = int_of_string s in
      let p = Printf.sprintf in
      match (v, a, b) with
      | v, Some a, Some b when a <= v && v <= b -> `Ok v
      | v, Some a, None when a <= v -> `Ok v
      | v, None, Some b when v <= b -> `Ok v
      | v, None, None -> `Ok v
      | _, Some a, Some b -> failwith (p "%s must be >= %d and <= %d" s a b)
      | _, Some a, None -> failwith (p "%s must be >= %d" s a)
      | _, None, Some b -> failwith (p "%s must be <= %d" s b)
    with Failure e -> `Error e
  in
  (parse, Format.pp_print_int)

let mode =
  let parse = function
    | "deflate" -> `Ok `Compression
    | "inflate" -> `Ok `Decompression
    | _ -> `Error "Invalid mode"
  in
  ( parse
  , fun fmt -> function
      | `Compression -> Format.pp_print_string fmt "compression"
      | `Decompression -> Format.pp_print_string fmt "decompression" )

let algo =
  let parse = function
    | "zlib" -> `Ok `Zlib
    | "gzip" -> `Ok `Gzip
    | _ -> `Error "Invalid algorithm"
  in
  ( parse
  , fun fmt -> function
      | `Zlib -> Format.pp_print_string fmt "zlib"
      | `Gzip -> Format.pp_print_string fmt "gzip" )

let mode =
  let doc = "Compression or decompression" in
  Arg.(value & opt mode `Compression & info ["mode"] ~doc)

let algo =
  let doc = "Zlib or Gzip" in
  Arg.(value & opt algo `Zlib & info ["algo"] ~doc)

let wbits =
  let doc = "Size of window (window bits between 8 and 15) (Zlib only)" in
  Arg.(value & opt (nat (Some 8) (Some 15)) 15 & info ["wbits"] ~doc)

let level =
  let doc = "Level of compression" in
  Arg.(value & opt (nat (Some 0) (Some 9)) 4 & info ["level"] ~doc)

let input_size =
  let doc = "Size of the input buffer" in
  Arg.(value & opt (nat (Some 2) None) 0xFFFF & info ["i"] ~doc)

let output_size =
  let doc = "Size of the output buffer" in
  Arg.(value & opt (nat (Some 2) None) 0xFFFF & info ["o"] ~doc)

let command =
  let doc = "Deflate and inflate any document." in
  let man =
    [ `S "Description"
    ; `P
        "$(tname) takes a standard input and write in standard output the \
         compressed/uncompressed data." ]
  in
  ( Term.(
      pure do_command $ input_size $ output_size $ mode $ level $ algo $ wbits)
  , Term.info "dpipe" ~doc ~man )

let () = match Term.eval command with `Error _ -> exit 1 | _ -> exit 0
