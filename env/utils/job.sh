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
    [ $? -ne 0 ] && return 1
    if [ "${fullpath:0:1}" = '/' ]; then
        echo "$fullpath"
    else
        basedir=$(dirname "$fullpath")
        if [ "$basedir" = '.' ]; then
            basedir=$(pwd)
        else
            cd "$basedir"
            basedir=$(pwd)
            cd "$OLDPWD"
        fi
        echo "$basedir/$(basename "$fullpath")"
    fi
    return 0
}

function is_executable {
    [ $# -gt 0 ] && type -P "$1" > /dev/null 2>&1
}

function is_daemon_mode {
    [ -n "$parentpid" -a -n "$lockfile" -a -n "$job" -a \
        -s "$lockfile" -a "$parentpid" = "$PPID" ]
}

function sanity_check {
    local data ppid pid
    # check if supplied job is executable
    is_executable "$job" || return 1
    # check content of lock file
    data=$(cut -s -d : -f 1,2 < "$lockfile")
    ppid=${data%:*}
    pid=${data#*:}
    [ "$ppid" != "$parentpid" -o "$pid" != '0' ] && return 2
    # save daemon process id
    echo "$parentpid:$$" > "$lockfile"
    # make sure the parent process is alive
    kill -n 0 "$parentpid" > /dev/null 2>&1 || return 3
}

function release_parent {
    echo 'Done!'
    exit 0
}

function clean_up {
    rm -rf "$lockfile"
}

function logger {
    [ $# -gt 0 ] && printf ' -- %s\n' "$*"
}

function interrupt_child {
    logger 'iterrupt signal intercepted!'
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

declare rundir="$HOME/.jobs"
declare cmd='' job=${xjobpath:-''}
declare filekey='' logfile='' lockfile=${xlockfile:-''}
declare childpid='' parentpid=${xparentpid:-''}
declare selfpath=$(command_path "$0")
declare -i ival

########
# MAIN #

if is_daemon_mode; then


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

    # release parent process
    logger 'sending release signal (SIGUSR1) to parent process'
    kill -s SIGUSR1 "$parentpid"
    logger "R: $?"

    # dispatching job asynchronously
    "$job" "$@" &
    childpid=$!
    logger "job dispatched: #$childpid \"$job\" ($*)"

    # setting iterruption trap
    trap 'interrupt_child' SIGINT SIGTERM

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
    job=$2

    # shift parameters
    shift 2

    # check if specified job exists
    job=$(command_path "$job")
    if [ $? -ne 0 ]; then
        logger 'The specified job could not be found...'
        exit 1
    fi

    # set job related variables
    filekey=${job#/}
    filekey=${filekey//\//.}
    if [ ${#filekey} -gt 128 ]; then
        filekey=${filekey:$(( ${#filekey} - 128 ))}
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
        # if is_executable "hook_$job"; then
        #     "hook_$job" "${@:3}"
        # fi

        # export necessary variables and initialize lock file
        export xjobpath=$job xlockfile=$lockfile xparentpid=$$
        echo "$xparentpid:0" > "$xlockfile"

        # set SIGUSR1 handler
        trap 'release_parent' SIGUSR1

        # dispatch child process (daemon) and wait for SIGUSR1 signal
        "$selfpath" "$@" < /dev/null > "$logfile" 2>&1 &
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
