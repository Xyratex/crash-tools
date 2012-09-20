
define obd_dev
  set $i = 0
  while obd_devs[$i] != 0
    printf "%p - %s\n", obd_devs[$i], obd_devs[$i]->obd_name
    set $i = $i + 1
  end
end

# $1 task ptr
define lock_pages
  set task = (struct task_struct)$1
  printf "%u - %s\n", task->pid, task->comm
end
