
define __print_ptlrpc_request
  p $arg0
  p *(struct ptlrpc_request *)$arg0
end

define obd_rpc
  set $obd = ((struct obd_device *)$arg0)
  set $imp = $obd->u.cli.cl_import
  printf "client import %p\n", $imp

  set $send = &(((struct obd_import *)$imp)->imp_sending_list)
  printf "sending list %p\n", $send
  list_links $send ptlrpc_request rq_list __print_ptlrpc_request

  set $send = &(((struct obd_import *)$imp)->imp_delayed_list)
  printf "delay list %p\n", $send
  list_links $send ptlrpc_request rq_list __print_ptlrpc_request

  set $replay = &(((struct obd_import *)$imp)->imp_replay_list)
  printf "replay_list %p\n", $replay
  list_links $send ptlrpc_request rq_replay_list __print_ptlrpc_request
end

document obd_rpc
end
