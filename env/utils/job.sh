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
    [ -z "$1" ] && return 2
    fullpath=$(type -P "$1")
    [ $? -ne 0 -o -z "$fullpath" ] && return 3
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

function is_valid_executable {
    local fullpath
    [ $# -lt 1 ] && return 1
    [ -z "$1" ] && return 2
    fullpath=$(type -P "$1")
    [ $? -ne 0 -o "$fullpath" != "$1" ] && return 3
    [ "${fullpath:0:1}" != '/' ] && return 4
    return 0
}

function is_daemon_mode {
    [ ! -t 0 -a ! -t 1 -a ! -t 2 -a \
        -n "$clientpid" -a -n "$lockfile" -a -n "$jobpath" -a \
        -s "$lockfile" -a "$clientpid" = "$PPID" ]
}

function sanity_check {

    local data ppid pid

    # check if supplied job is executable
    is_valid_executable "$jobpath" || return 1

    # check the contents of lock file
    data=$(cut -s -d : -f 1,2 < "$lockfile")
    ppid=${data%:*}
    pid=${data#*:}
    [ "$ppid" != "$clientpid" -o "$pid" != '0' ] && return 2

    # save daemon process id
    echo "$clientpid:$$" > "$lockfile"

    # make sure the parent process is alive
    kill -n 0 "$clientpid" || return 3

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
    logger 'sending termination signal (SIGTERM) to job process'
    kill -s SIGTERM $jobpid
    logger "R: $?"
    logger 'waiting for job status code'
    wait $jobpid
    logger "R: $?"
    clean_up
    logger 'exit by interrupt... bye!'
    exit 0
}

#############
# VARIABLES #

declare -i result=0
declare rundir="$HOME/.jobsh"
declare cmdname='' jobpath=${xjobshjobpath:-''}
declare filekey='' logfile='' lockfile=${xjobshlockfile:-''}
declare jobpid='' monitorpid='' clientpid=${xjobshclientpid:-''}
declare selfpath=$(command_path "$0")

########
# MAIN #

# check self reference

if ! is_valid_executable "$selfpath"; then
    logger "Self reference could not be resolved..."
    exit 1
fi

if is_daemon_mode; then

    # INSIDE MONITOR

    logger "[ monitor init ] $(date -u)"

    # perform sanity check
    sanity_check
    result=$?
    if [ $result -ne 0 ]; then
        logger "aborting... bad result for sanity check ($result)"
        exit 1
    fi

    logger 'sanity check passed'

    # ignore SIGHUP
    trap '' SIGHUP

    # detach from parent process
    logger 'sending detach signal (SIGUSR1) to client process'
    kill -s SIGUSR1 "$clientpid"
    logger "R: $?"

    # dispatching job asynchronously
    "$jobpath" "$@" &
    jobpid=$!
    logger "job dispatched: #$jobpid \"$jobpath\" ($*)"

    # set iterruption trap
    trap 'trap_interrupt_signal' SIGTERM

    logger 'waiting for job completion'
    wait $jobpid
    logger "job exited with code: $?"

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
    cmdname=$1
    jobpath=$2

    # shift parameters
    shift 2

    # check if specified job exists
    jobpath=$(command_path "$jobpath")
    if [ $? -ne 0 -o -z "$jobpath" ]; then
        logger 'The specified job could not be found...'
        exit 1
    fi

    if ! is_valid_executable "$jobpath"; then
        logger 'The absolute path for specified job could not be reliably determined...'
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
    if [ "$cmdname" = 'start' ]; then

        # START

        if [ -f "$lockfile" ]; then
            logger 'The specified job seems to be already running...'
            exit 1
        fi
        # create lock
        touch "$lockfile"

        # # check for any hooks
        # if is_valid_executable "hook_$jobpath"; then
        #     "hook_$jobpath" "${@:3}"
        # fi

        # export necessary variables and initialize lock file
        export xjobshjobpath="$jobpath" xjobshlockfile="$lockfile" xjobshclientpid="$$"
        echo "$xjobshclientpid:0" > "$xjobshlockfile"

        # set detach signal handler (SIGUSR1)
        trap 'trap_detach_signal' SIGUSR1

        # dispatch monitor process and wait for detach signal (SIGUSR1)
        "$selfpath" "$@" < /dev/null >> "$logfile" 2>&1 &
        monitorpid=$!
        wait $monitorpid

        # ... execution should not reach this point
        clean_up
        logger 'Oops! The specified job died prematurely...'
        exit 1

        # ~ ~ ~

    elif [ "$cmdname" = 'stop' ]; then
        # STOP
        logger 'Stop not implemented...'
        # ~ ~ ~
    elif [ "$cmdname" = 'restart' ]; then
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
