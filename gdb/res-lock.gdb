# -*- Mode: gdb-script -*-

define show_nspool
  if ($arg0->ns_pool.pl_granted.counter > 0)
    printf "ns %p %lu locks in pool %s\n", $arg0, \
      $arg0->ns_pool.pl_granted.counter, $arg0->ns_pool.pl_name
    set $find_ct = $find_ct + 1
  end
end
document show_nspool
  usage: show_nspool <pool-address>

  Print the lock granted count for all non-empty pools
end
# end: show_nspool

define show_nslocks
  if ($arg0->ns_pool.pl_granted.counter > 0)
    set $grant_ct = $arg0->ns_pool.pl_granted.counter
    printf "\nns %p %lu resources\n\tpool %s\n", $arg0, \
      $arg0->ns_resources, \
      $arg0->ns_pool.pl_name
    walk_hash_array $ns->ns_hash
    set $find_ct = $find_ct + 1
  end
end
document show_nslocks
  usage: show_nslocks <ns-struct-addr>
  Print the locks granted count for all non-zero pools
end

# show_nslocks Support values:

set $OFF_ldlm_lock_l_res_link = (unsigned long)\
    &(((struct ldlm_lock*)0)->l_res_link)
set $OFF_ldlm_resource_lr_hash = (unsigned long)\
    &(((struct ldlm_resource *)0)->lr_hash)
set $OFF_ldlm_namespace_ns_list_chain = (unsigned long)\
    &(((struct ldlm_namespace*)0)->ns_list_chain)

# show_nslocks Support commands:

define walk_locks
  set $lock_list_ptr = $arg0->next
  set $lock_walk_ct  = 0
  while ($lock_list_ptr != $arg0)
    set $lock_walk_ct += 1
    if ($lock_walk_ct <= 100)
      set $lock_ptr = (struct ldlm_lock *)((char *)$lock_list_ptr \
                  - $OFF_ldlm_lock_l_res_link)
      printf "ldlm_lock %p -- l_refc %d, readers %d, writers %d\n", \
        $lock_ptr, $lock_ptr->lrefc.counter \
        $lock_ptr->l_readers, $lock_ptr->l_writers
      p $lock_ptr->l_policy_data
    end
    set $lock_list_ptr = $lock_list_ptr->next
    set $lock_count = $lock_count + 1
  end
  if ($lock_walk_ct > 100)
    printf " [... %u elided]\n", ($lock_walk_ct - 100)
  end
end

define walk_res_hash
  set $head = $arg0->next
  set $hash_ent_ct = 0

  while ($head != $arg0)
    set $hash_ent_ct = $hash_ent_ct + 1
    set $res = (struct ldlm_resource *)((char *)$head \
             - $OFF_ldlm_resource_lr_hash)
    printf "hash index %d ent %d -> (struct ldlm_resource *)%p\n", \
      $ix, $hash_ent_ct, $res
    set $lock_count = 0
    set $list_head = &($res->lr_granted)
    if ($list_head != $list_head->next)
      set $walk_locks_name = 1
      printf "walk locks 1 -> granted\n"
      walk_locks $list_head
    end

    set $list_head = &($res->lr_waiting)
    if ($list_head != $list_head->next)
      set $walk_locks_name = 2
      printf "walk locks 2 -> waiting\n"
      walk_locks $list_head
    end

    set $list_head = &($res->lr_converting)
    if ($list_head != $list_head->next)
      set $walk_locks_name = 3
      printf "walk locks 3 -> converting\n"
      walk_locks $list_head
    end

    if ($lock_count > 0)
      printf "%3d locks\n", $lock_count
    else
      printf "has no locks\n"
    end

    set $head = $head->next
    set $grant_ct = $grant_ct - 1
  end
end

define walk_hash_array
  set $ix = 0
  while ($ix < 4096)
    set $hash_entry_p = $arg0+$ix
    set $hash_next_p  = $hash_entry_p->next
    if ($hash_entry_p != $hash_next_p)
      walk_res_hash $hash_entry_p $ix
    end
    set $ix = $ix + 1
  end
end

# end: show_nslocks

define ns_list
  set $scan=$list->next
  set $find_ct = 0
  while $scan != $list
    set $ns=((unsigned long)$scan - $OFF_ldlm_namespace_ns_list_chain)
    set $ns=(struct ldlm_namespace*)$ns
    $arg0 $ns
    set $scan = $scan->next
  end
  printf "Found %d namespaces\n", $find_ct

end
document ns_list
  usage: ns_list <namespace-list-walking-command>

  Traipse through a list of "struct ldlm_namespace" structures
  and perform some command on each one found.
  "$list" must be set and pointing to a name space list.

  Two supported commands:  show_nslocks show_nspool
end
# end: ns_list

define namespaces
  printf "Looking for CLI name spaces:\n"
  set $list = &ldlm_cli_namespace_list
  ns_list $arg0

  printf "Looking for SRV name spaces:\n"
  set $list = &ldlm_srv_namespace_list
  ns_list $arg0
end
document namespaces
  usage: namespaces <namespace-list-walking-command>

  Traipse through all of the namespace
  lists and perform some command on each one found.

  Two supported commands:  show_nslocks show_nspool
end
# end: namespaces
