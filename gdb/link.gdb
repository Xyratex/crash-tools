# Provides: link2struct
# Provides: list_links

define link2struct
  set $struct_off = (unsigned long)\
    &(((struct $arg1 *)0)->$arg2)
  p (struct $arg1 *)((char *)$arg0 - $struct_off)
end

document link2struct
  usage:  link2struct <addr> <struct-name> <link-field>

  Given the address of a link field of a structure, print
  the structure's address.  "<struct-name>" is the
  structure name (without the word "struct")
end
# end: link2struct

define list_links
  set $struct_off = (unsigned long)\
    &(((struct $arg1 *)0)->$arg2)
  set $start = (struct list_head *)$arg0
  set $curr  = $start->next

  while $curr != $start
    set $ptr = (struct $arg1 *)((char *)$curr - $struct_off)
    if $argc > 3
      p $ptr->$arg3
    else
      p $ptr
    end

    set $curr = $curr->next
  end
end

document list_links
  usage:  list_links <addr> <struct-name> <link-field> [ <show-field> ]

  starting from "<addr>", show every "struct <struct-name>" structure
  in the list linked by "<link-field>".  If "<show-field>" is provided,
  that field is printed, otherwise the structure address is printed.
end
# end: list_links
