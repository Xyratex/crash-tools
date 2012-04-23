#! /bin/bash

if test ${#1} -eq 0
then
    test -f init.crash && exit 0
    phase=modlist
else
    phase=${1}
fi

declare -r phase
declare -r prog=$(basename $0 .sh)
declare -r progdir=$(cd $(dirname $0) > /dev/null ; pwd)
declare -r program=${progdir}/$(basename $0)

die() {
    echo "$prog error:  $*"
    exit 1
} >&2

prep() {
    base=c-cmd
    out=${base}.out
    new=${base}.new
    tmp=${base}.tmp
    exec 8>&1 1> ${base}.new
    echo "! :> ${base}.out"
}

wrap() {
    if test "X$1" = Xcleanup
    then echo "! rm -f ${base}*"
    else echo "! bash ${program} $1"
    fi

    exec 1>&8 8>&-

    printf '\n\nThe %s commands are configured\n' "$2"
    cat ${base}.new
    mv -f ${new} ${base}
    echo "please type '< ${base}' to invoke them"
    exit 0
}

case "${phase}" in
( modlist )
    prep
    rm -f ${out} ${base}.vers
    cat <<- _EOF_
	sys | sed '/^crash>/d'";s/'//g" > ${base}.sys
	mod | awk '/not loaded/{print \$2}' > ${out}
	! echo \$(wc -l < ${out}) modules need loading
	_EOF_
    wrap find_mods 'modules-to-load'
    ;;

( find_mods )
    prep
    exec < $base.sys

    # Convert the text before the ':' to a variable name and assign to it
    # the first token following the colon.  Except for values that are
    # quoted.  Then we set the variable to the entire contents.
    #
    while IFS=: read nm val
    do
        nm=$(echo $nm | sed 's/ /_/g')
        set -- $val
        [[ "$1" =~ \".* ]] && set -- "$*"
        eval $nm="$1"
    done

    # using those data, create a script to run crash that has all those
    # name in it.  "run-crash" is easier than the 100-odd byte long command
    #
    home_crashd=$HOME/.crash.d
    {
        echo '#!' $(which bash)
        echo cd $PWD
        echo kernel=$DEBUG_KERNEL
        echo dump=$DUMPFILE
        echo map=$SYSTEM_MAP
        echo crash=$(which crash)
        echo export CRASH_EXTENSIONS=${home_crashd}
        printf 'ini=\ntest -f init.crash && ini="-i init.crash"\n'
        echo 'exec $crash $ini $kernel $map $dump'
    } > run-crash
    chmod +x run-crash

    # Now create the "init.crash" command.  We look for the .ko module files
    # for all the modules that have been modprobe-d but are "not loaded"
    # (selected above in the "modlist" phase).
    #
    ct=0
    findlist=$(
        exec 2> /dev/null
        ls $(find * -type f -name '*.ko') )

    for f in $(<${out})
    do
        if test ${#findlist} -le 1
        then g=
        else g=$(find $findlist -name ${f}.ko)
        fi

        test ${#g} -le 1 && {
            test -d "/lib/modules/${RELEASE}" || continue
            g=$(find "/lib/modules/${RELEASE}" -type f name ${f}.ko)
            test ${#g} -le 1 && continue
        }
        printf 'mod -s %8s %s\n' $f "$g"
        (( ct += 1 ))
    done > init.crash

    # hunt for extensions in (fairly) well-known locations.
    # for a given extension, give priority to $HOME first,
    # then /usr/local, and finally /usr/lib*.
    #
    for f in $(
        find ${home_crashd} /usr/local/lib*/crash/extensions \
            /usr/lib*/crash/extensions \
            -type f -name '*.so')
    do
        nm=$(basename $f .so | sed 's/[^a-zA-Z0-9]/_/g')
        eval nmv=\${${nm}_extension_loaded}
        test ${#nmv} -eq 0 && {
            echo extend $f
            eval ${nm}_extension_loaded=true
        }
    done >> init.crash

    # add the contents of init.crash to the $base file, too.
    #
    cat init.crash

    echo "attempting loads on $ct modules" >&2
    wrap cleanup 'load module'
    ;;

( uninstall )
    # Remove this script from the crash startup
    #
    iftest='! if test -f run-crash'
    grep "^${iftest}" ~/.crashrc > /dev/null 2>&1 && \
        sed -i "/^${iftest}/d" ~/.crashrc
    ;;

( install )
    # Install this script as part of the crash startup
    #
    iftest='! if test -f run-crash'
    grep "^${iftest}" ~/.crashrc > /dev/null 2>&1 || \
        echo "${iftest}; then : ; else bash ${HOME}/bin/${prog}; fi" >> ~/.crashrc
    ;;

( * )
    die invalid parameter: $phase >&2
    ;;
esac
