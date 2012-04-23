#! /bin/bash

set -e
rcdir=$HOME/.crash.d

case "$1" in

--all )
    exit 0
    ;;

--install )
    test -d ${rcdir} || mkdir ${rcdir}
    for f in *.sial
    do
        test -f ${rcdir}/$f -a ${rcdir}/$f -nt $f || \
            cp -f $f ${rcdir}/$f
    done
    exit 0
    ;;

--uninstall )
    test -d ${rcdir} || exit 0
    for f in *.sial
    do
        rm -f ${rcdir}/$f
    done
    exit 0
    ;;

--show )
    test -d ${rcdir} || {
        echo install directory missing: ${rcdir}
        exit 0
    }
    for f in *.sial
    do
        test -f ${rcdir}/$f || {
            echo not installed: $f
            continue
        }
        test ${rcdir}/$f -nt $f || {
            echo out of date: $f
            continue
        }
        echo installed: $f
    done
    exit 0
    ;;

( * )
    echo invalid option: $1 >&2
    exit 1
esac
