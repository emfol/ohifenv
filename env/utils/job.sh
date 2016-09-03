#!/bin/bash

set -u

#############
# FUNCTIONS #

function print_usage {
    printf 'Usage:\n\t%s <start|stop|restart> <job> [ arg1 arg2 ... ]\n\n' "$0"
}

function command_path {
    local basedir fullpath
    [ $# -lt 1 ] && return 1
    fullpath=$(type -P "$1")
    [ $? -ne 0 -o -z "$fullpath" ] && return 2
    if [ "${fullpath:0:1}" != '/' ]; then
        basedir=$(dirname "$fullpath")
        if [ "$basedir" != '.' ]; then
            cd "$basedir"
            basedir=$(pwd)
            cd "$OLDPWD"
        else
            basedir=$(pwd)
        fi
        echo "$basedir/$(basename "$fullpath")"
    else
        echo "$fullpath"
    fi
    return 0
}

function is_executable {
    local fullpath
    [ $# -lt 1 ] && return 1
    fullpath=$(type -P "$1")
    [ $? -eq 0 -a -n "$fullpath" ]
}

function is_daemon_mode {
    [ ! -t 0 -a ! -t 1 -a ! -t 2 -a \
        -n "$parentpid" -a -n "$lockfile" -a -n "$jobpath" -a \
        -s "$lockfile" -a "$parentpid" = "$PPID" ]
}

function sanity_check {

    local data ppid pid

    # check if supplied job is executable
    is_executable "$jobpath" || return 1

    # check the contents of lock file
    data=$(cut -s -d : -f 1,2 < "$lockfile")
    ppid=${data%:*}
    pid=${data#*:}
    [ "$ppid" != "$parentpid" -o "$pid" != '0' ] && return 2

    # save daemon process id
    echo "$parentpid:$$" > "$lockfile"

    # make sure the parent process is alive
    kill -n 0 "$parentpid" || return 3

}

function clean_up {
    rm -rf "$lockfile"
}

function logger {
    [ $# -gt 0 ] && printf ' -- %s\n' "$*"
}

# ... SIGNAL HANDLERS

function trap_detach_signal {
    logger 'Done!'
    exit 0
}

function trap_interrupt_signal {
    logger 'interrupt signal intercepted!'
    logger 'sending termination signal (SIGTERM) to child process'
    kill -s SIGTERM $childpid
    logger "R: $?"
    logger 'waiting for child process status code'
    wait $childpid
    logger "R: $?"
    clean_up
    logger 'exit by interrupt... bye!'
    exit 0
}

#############
# VARIABLES #

declare rundir="$HOME/.jobsh"
declare cmd='' jobpath=${xjobpath:-''}
declare filekey='' logfile='' lockfile=${xlockfile:-''}
declare childpid='' parentpid=${xparentpid:-''}
declare selfpath=$(command_path "$0")
declare -i ival

########
# MAIN #

if is_daemon_mode; then

    logger "[ daemon init ] $(date -u)"

    # perform sanity check
    sanity_check
    ival=$?
    if [ $ival -ne 0 ]; then
        logger "aborting... bad result for sanity check ($ival)"
        exit 1
    fi

    logger 'sanity check passed'

    # ignore SIGHUP
    trap '' SIGHUP

    # detach from parent process
    logger 'sending detach signal (SIGUSR1) to parent process'
    kill -s SIGUSR1 "$parentpid"
    logger "R: $?"

    # dispatching job asynchronously
    "$jobpath" "$@" &
    childpid=$!
    logger "job dispatched: #$childpid \"$jobpath\" ($*)"

    # set iterruption trap
    trap 'trap_interrupt_signal' SIGTERM

    logger 'waiting for child process completion'
    wait $childpid
    logger "child proccess exited with code: $?"

    clean_up
    logger 'clean exit... bye!'

else

    # make sure jobs directory exists
    if ! mkdir -p "$rundir" > /dev/null 2>&1; then
        logger 'jobs directory could not be created'
        exit 1
    fi

    # check arguments
    if [ $# -lt 2 ]; then
        print_usage
        exit 1
    fi

    # define main parameters
    cmd=$1
    jobpath=$2

    # shift parameters
    shift 2

    # check if specified job exists
    jobpath=$(command_path "$jobpath")
    if [ $? -ne 0 -o -z "$jobpath" ]; then
        logger 'The specified job could not be found...'
        exit 1
    fi

    # set job related variables
    filekey=${jobpath#/}
    filekey=${filekey//\//.}
    if [ ${#filekey} -gt 128 ]; then
        filekey=${filekey:$(( ${#filekey} - 128 ))}
        filekey=${jobpath#.}
    fi
    lockfile="$rundir/$filekey.lock"
    logfile="$rundir/$filekey.log"

    # evaluate command
    if [ "$cmd" = 'start' ]; then

        # START

        if [ -f "$lockfile" ]; then
            logger 'The specified job seems to be already running...'
            exit 1
        fi
        # create lock
        touch "$lockfile"

        # # check for any hooks
        # if is_executable "hook_$jobpath"; then
        #     "hook_$jobpath" "${@:3}"
        # fi

        # export necessary variables and initialize lock file
        export xjobpath="$jobpath" xlockfile="$lockfile" xparentpid="$$"
        echo "$xparentpid:0" > "$xlockfile"

        # set detach signal handler (SIGUSR1)
        trap 'trap_detach_signal' SIGUSR1

        # dispatch child process and wait for detach signal (SIGUSR1)
        "$selfpath" "$@" < /dev/null >> "$logfile" 2>&1 &
        childpid=$!
        wait $childpid

        # ... execution should not reach this point
        clean_up
        logger 'Oops! The specified job died prematurely...'
        exit 1

        # ~ ~ ~

    elif [ "$cmd" = 'stop' ]; then
        # STOP
        logger 'Stop not implemented...'
        # ~ ~ ~
    elif [ "$cmd" = 'restart' ]; then
        # RESTART
        logger 'Restart not implemented...'
        # ~ ~ ~
    else
        # NONE
        print_usage
        exit 1
        # ~ ~ ~
    fi

fi

exit 0
