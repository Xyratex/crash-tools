#! /bin/bash


typeset -r me=$0
typeset -r base=c-cmd
typeset -r out=${base}.out
typeset -r new=${base}.new
typeset -r tmp=${base}.tmp

if test -z "$1"
then
    rm -f ${base}*
    phase=get-data-list
else
    phase=${1}
fi

exec 8>&1 1> ${base}.new 7> ${base}.xtrace
BASH_XTRACEFD=7
set -x

echo "! :> ${base}.out"

phase=${1:-get-data-list}

ready() {
    if test "X$1" = Xcleanup
    then
        test -s ${base}.prompt && echo "set silent off"
        echo "! rm -f ${base}*"
    else
        echo "! echo $phase complete.  Prepping $1"
        echo "! bash ${me} $1"
    fi

    exec 1>&8 8>&-

    printf '\n\nThe %s commands are configured\n' "$phase"
    cat ${new}
    mv -f ${new} ${base}
    echo "please type '< ${base}' to invoke them"
    echo "the next phase will be $1"
    exit 0
}

case "${phase}" in
( get-data-list )

    echo "sys | grep -E '^crash>' > ${base}.prompt"
    echo "set silent on"
    echo "p trace_data | sed -n 's/}.*//;s/,/ /g;s/.*{//p' > ${base}.traces"
    echo "! echo tcd_pages$'\n'tcd_daemon_pages > ${base}.struct"

    printf 'p &((struct trace_page*)0)->linkage | '
    echo   "sed -n 's/.*) *//p' > ${base}.link-off"
    ready head-entry-ct
    ;;

( head-entry-ct )
    # determine the number of entries in each array of trace blocks
    # do this by counting the number of "__pad" fields found.
    #
    outl=( $(< ${base}.traces) )
    for ix in ${!outl[*]}
    do
        [[ ${outl[$ix]} != 0x0 ]] || continue
        printf "p *(trace_data[$ix]) | "
        echo "sed -n '/__pad = /p' | wc -l > ${out}"
        break
    done
    ready list-heads
    ;;

( list-heads )
    ct=$(( $(< ${out}) - 1 ))
    outl=( $(< ${base}.traces) )
    field_list=$(< ${base}.struct)
    for ix in ${!outl[*]}
    do
        [[ ${outl[$ix]} != 0x0 ]] || continue
        cmd="p &(trace_data[$ix][0]"
        for iy in $(seq 0 $ct)
        do
            ncmd="${cmd}[$iy].tcd"
            for g in $field_list
            do
                echo "${ncmd}.${g}) | sed -n 's/.*)//p' >> ${base}.${g}"
            done
        done
    done
    rm -f ${out}
    f=
    for g in $field_list
    do f=${f}\ ${base}.${g}
    done
    echo "! wc -l ${f}"
    ready list-lists
    ;;

( list-lists )
    offset=$(< ${base}.link-off)
    for f in $(< ${base}.struct)
    do
        fmt="list -o ${offset} -s trace_page -H %s > ${base}.${f}-%s\n"

        for addr in $(< ${base}.${f})
        do
            printf "$fmt" $addr $addr
        done
    done
    ready trace-pages
    ;;

( trace-pages )
        fmt="! egrep '^[0-9a-fA-F]|next *=|used *=' > ${base}.${f}-%s\n"
        fmt="! test -s ${base}.${f}-%s || rm -f ${base}.${f}-%s\n"
    for f in $(< ${base}.struct)
    do
        for addr in $(< ${base}.${f})
        do
            test -f ${base}.${f}-${addr} || continue
            fmt="! used=\$(<$base.used) ;"
            fmt="${fmt} if test \${used:-0} -le 0 ; then rm -f $base.$f-$addr ; "
            fmt="${fmt}else echo %s \$used >> ${base}.usage ; fi\\n"

            for page in $(< ${base}.${f}-${addr})
            do
                : ${base}.${f}-${addr}
                page=0x$page
                page=$(( $page - offset ))
                page=$(printf 0x%X $page )
                printf 'p ((struct trace_page*)%s)->used | ' $page
                printf 'sed -n "s/\\$[0-9].*= *//p" > %s\n' ${base}.used
                printf "$fmt" $page
            done
        done
    done
    cat ${base}.log > /dev/tty
    echo "! ls -l trace-data.txt ; wc -l trace-data.txt"
    test -s ${base}.prompt && echo 'set silent off'
    ready dump-trace
    ;;

( dump-trace )
    exec 3< ${base}.usage
    echo '! rm -f trace-data.txt'
    while read -u3 addr used
    do
        test ${#used} -eq 0 && continue
        echo "p/x *(*(struct trace_page*)$addr).page > ${base}.tmp"
        printf '! sed '\''s/^\$[0-9]* *=/'"${addr} for $used =/'"
        echo   "< ${base}.tmp >> trace-data.txt"
    done
    ready cleanup
    ;;

( * )
    echo invalid parameter: $phase >&8
    ;;
esac
