#! /bin/bash

# This script should be idempotent -- i.e. run as often as you like
# and additional invocations will make no changes.
#
# It looks for documented gdb commands and adds them into ~/.gdbinit
# from the "define cmd" line through the "# end: cmd" line.
# It should not perturb any other text in that file.

readonly prog=$(basename $0)
cd $(dirname $0)

die() {
    echo "$prog error:  $*"
    exit 1
} >&2

initfile=$HOME/.gdbinit

list=$(sed -n $'s/^document[ \t][ \t]*//p' *.gdb)
sedoutcmd=$(
    for f in $list
    do
        echo $'/^define[ \t]*'"$f\$/,/^# *end: *$f\$/d"
    done )
sedincmd=$(echo "$sedoutcmd" | sed 's@/d$@/p@')

case "X$1" in
X | Xinstall | X--install )
    test -s ${initfile} || {
        sed -n "$sedincmd" *.gdb > ${initfile}
        exit 0
    }

    {
        sed "$sedoutcmd" ${initfile}
        sed -n "$sedincmd" *.gdb
    } > ${initfile}-$$
    ;;

Xuninstall | X--uninstall )
    test -s ${initfile} || exit 0
    sed "$sedoutcmd" ${initfile} > ${initfile}-$$
    ;;

* )
    die "unrecognizable argument:  $1"
    ;;
esac

if cmp -s ${initfile}-$$ ${initfile}
then rm -f ${initfile}-$$
else mv -f ${initfile}-$$ ${initfile}
     echo updated ${initfile}
fi
