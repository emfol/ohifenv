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
    [ -n "$parentpid" -a -n "$lockfile" -a -n "$job" \
        -a -s "$lockfile" -a "$parentpid" = "$PPID" ]
}

function sanity_check {
    local data ppid pid
    # check if supplied job is executable
    is_executable "$job" || return 1
    # check content of lock file
    data=$(cut -s -d : -f 1,2 < "$lockfile")
    ppid=${data%:*}
    pid=${data#*:}
    [ "$ppid" != "$parentpid" -o "$pid" != '0' ] && return 1
    # save daemon process id
    echo "$parentpid:$$" > "$lockfile"
    # make sure the parent process is alive
    kill -n 0 "$parentpid" > /dev/null 2>&1
}

function release_parent {
    echo 'Done!'
    exit 0
}

function interrupt_child {
    echo 'Sending termination signal (SIGTERM) to child process...'
    kill -SIGTERM $pid_child
    echo "R: $?"
    echo 'Waiting for child process status code...'
    wait $pid_child
    echo "R: $?"
    echo 'Removing lock...'
    rm -rf "$file_pid"
    echo "R: $?"
    echo 'Bye!'
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
        echo "Bad result for sanity check ($ival)..."
        exit 1
    fi

    # ignore SIGHUP
    trap '' SIGHUP

    # release parent process
    kill -s SIGUSR1 "$parentpid" > /dev/null 2>&1

    # dispatch job
    "$job" "$@" &
    childpid=$!

    # trap 'interrupt_child' SIGINT SIGTERM
    wait $childpid

else

    # make sure jobs directory exists
    if ! mkdir -p "$rundir" > /dev/null 2>&1; then
        echo 'Jobs directory could not be created...'
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
        echo 'The specified job could not be found...'
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
            echo 'This job seems to be already running...'
            exit 1
        fi
        # create lock
        touch "$lockfile"
        # # check for any hooks
        # if is_executable "hook_$job"; then
        #     "hook_$job" "${@:3}"
        # fi
        # prepare to dispatch job
        trap 'release_parent' SIGUSR1
        export xjobpath=$job xlockfile=$lockfile xparentpid=$$
        echo "$xparentpid:0" > "$xlockfile"
        # dispatch child process (daemon)
        "$selfpath" "$@" < /dev/null > "$logfile" 2>&1 &
        # wait for SIGUSR1 from child
        childpid=$!
        wait $childpid
        # ... execution should not reach this point
        rm -rf "$lockfile" > /dev/null 2>&1
        echo 'Oops! Premature job death...'
        exit 1
        # ~ ~ ~
    elif [ "$cmd" = 'stop' ]; then
        # STOP
        echo 'Stop not implemented...'
        # ~ ~ ~
    elif [ "$cmd" = 'restart' ]; then
        # RESTART
        echo 'Restart not implemented...'
        # ~ ~ ~
    else
        # NONE
        print_usage
        exit 1
        # ~ ~ ~
    fi

fi

exit 0
