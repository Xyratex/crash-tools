#! /bin/bash

typeset -r me=$0
typeset -r base=c-cmd
typeset -r out=${base}.out
typeset -r new=${base}.new
typeset -r tmp=${base}.tmp

exec 1> ${new}
echo "! :> ${out}"

phase=${1:-onproc}

ready() {
    echo "! bash ${me} $1"

    printf '\n\nThe %s commands are configured\n' "$2" >&2
    cat ${new} >&2
}

case "${phase}" in
( onproc )
    cat <<- _EOF_
	ps > $tmp
	! sed -n "/^>/{;s/  *RU .*//;s/.* //;p;}" $tmp > ${out}
	! echo \$(wc -l < ${out}) processes are onproc
	_EOF_
    ready stack "onproc"
    ;;

( stack )
    fmt="set %s >/dev/null\n! printf '%s  ' >> ${out}"$'\n'
    fmt=${fmt}$'task | sed -n "/^ *stack  *= /{;'
    fmt=${fmt}"s/.*= *//;s/,.*//;p;}\" >> ${out}"$'\n'
    for f in $(<${out})
    do
        printf "$fmt" $f $f
    done
    echo '! echo $(wc -l < ${out}) stack addresses acquired'

    ready bt "stack acquisition"
    ;;

( bt )
    fmt=$'set %s >/dev/null\nbt -S %s\n!echo\n'
    exec 3< ${out}
    while read -u3 t s _
    do
        test ${#s} -le 1 && continue
        printf "$fmt" $t $s
    done

    ready cleanup "bt"
    ;;

( cleanup )
    exec 1>&2
    echo cleaning up:  ${base}*
    rm -f ${base}*
    ;;

( * )
    exec 1>&2
    echo invalid parameter: $phase
    rm -f ${base}*
    ;;
esac

exec 1>&2
test -f ${new} && {
    mv -f ${new} ${base}
    echo "please type '< ${base}'"
}
