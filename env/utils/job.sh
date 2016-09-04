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
    local filepath
    [ $# -lt 1 ] && return 1
    [ -z "$1" ] && return 2
    filepath=$1
    [ "${filepath:0:1}" != '/' ] && return 3
    [ -x "$filepath" ] || return 4
    return 0
}

function is_monitor_mode {
    # not in monitor mode if any standard fd is a terminal
    [ -t 0 -o -t 1 -o -t 2 ] && return 1
    # not in monitor mode if any of these variables is empty
    [ -z "$jobpath" -o -z "$lockfile" -o -z "$clientpid" ] && return 2
    # not in monitor mode if client PID is not PPID
    [ "$clientpid" != "$PPID" ] && return 3
    # not in monitor mode if lockfile is not a file or is empty
    [ ! -s "$lockfile" ] && return 4
    return 0
}

function sanity_check {

    local data cpid mpid

    # check if job path is a valid executable
    is_valid_executable "$jobpath" || return 1

    # check if lockfile path is valid
    is_valid_lockfile "$jobpath" "$lockfile" || return 2

    # check the contents of lock file
    read data < "$lockfile"
    [ -z "$data" ] && return 3
    cpid=${data%:*}
    mpid=${data#*:}
    [ "$cpid" != "$clientpid" -o "$mpid" != '0' ] && return 4

    # save monitor process id
    monitorpid=$$
    echo "$clientpid:$monitorpid" > "$lockfile"

    # make sure the client process is alive
    kill -n 0 "$clientpid" || return 5

    return 0

}

function getjobkey {
    local -i maxlen=80
    local keyname
    [ $# -lt 1 ] && return 1
    [ -z "$1" ] && return 2
    keyname=$1
    keyname=${keyname// /_}
    keyname=${keyname#/}
    keyname=${keyname//\//.}
    if [ ${#keyname} -gt $maxlen ]; then
        keyname=${keyname:$(( ${#keyname} - $maxlen ))}
        keyname=${keyname#.}
    fi
    echo "$keyname"
    return 0
}

function getwritablefile {
    local filepath
    [ $# -lt 1 ] && return 1
    [ -z "$1" ] && return 2
    filepath="$rundir/$1"
    touch "$filepath" > /dev/null 2>&1 || return 3
    [ -w "$filepath" ] || return 4
    echo "$filepath"
    return 0
}

function getlockfilename {
    local keyname
    [ $# -lt 1 ] && return 1
    [ -z "$1" ] && return 2
    keyname=$(getjobkey "$1")
    [ $? -ne 0 -o -z "$keyname" ] && return 3
    echo "${keyname}.lock"
    return 0
}

function getlogfile {
    local extname keyname filepath
    [ $# -lt 2 ] && return 1
    [ "$1" != '-m' -a "$1" != '-j' ] && return 2
    [ -z "$2" ] && return 3
    keyname=$(getjobkey "$2")
    [ $? -ne 0 -o -z "$keyname" ] && return 4
    if [ "$1" = '-j' ]; then
        extname='job'
    else
        extname='mon'
    fi
    filepath=$(getwritablefile "${keyname}.${extname}.log")
    [ $? -ne 0 -o -z "$filepath" ] && return 5
    echo "$filepath"
    return 0
}

function is_valid_lockfile {
    local jpath lpath rpath
    [ $# -lt 2 ] && return 1
    [ -z "$1" -o -z "$2" ] && return 2
    jpath=$1
    lpath=$(basename "$2")
    rpath=$(getlockfilename "$jpath")
    [ $? -ne 0 -o -z "$rpath" ] && return 3
    [ "$rpath" != "$lpath" ] && return 4
    return 0
}

function getmonitorpid {
    local pid
    # lockfile exists?
    [ -s "$lockfile" ] || return 1
    # check the contents of lock file
    read pid < "$lockfile"
    [ -n "$pid" ] || return 2
    # remove client pid
    pid=${pid#*:}
    [ -n "$pid" ] || return 3
    # echo found pid
    echo "$pid"
    return 0
}

function is_process_alive {
    [ $# -gt 0 ] || return 1
    [ -n "$1" ] || return 2
    kill -n 0 "$1" > /dev/null 2>&1 || return 3
    return 0
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

function trap_termination_signal {
    logger 'SIGTERM intercepted!'
    logger 'sending termination signal (SIGTERM) to job process'
    kill -s SIGTERM "$jobpid"
    logger "R: $?"
    sigret=2
}

#############
# VARIABLES #

declare retval=0 sigret=0
declare rundir="$HOME/.jobsh"
declare emptyfile="$rundir/.empty"
declare cmdname='' jobpath=${xjobshjobpath:-''}
declare logfile='' lockfile=${xjobshlockfile:-''}
declare jobpid='' monitorpid='' clientpid=${xjobshclientpid:-''}
declare selfpath=$(command_path "$0")

########
# MAIN #

# check self reference

if is_monitor_mode; then

    # INSIDE MONITOR

    logger "[ MONITOR INIT ] $(date -u)"

    # perform sanity check
    declare result
    sanity_check
    result=$?
    if [ $result -ne 0 ]; then
        logger "aborting... bad result for sanity check ($result)"
        exit 1
    fi
    unset -v result

    logger "sanity check passed! monitor PID is #$monitorpid"

    # create log file for job
    logger 'creating output file for job'
    logfile=$(getlogfile -j "$jobpath")
    if [ $? -ne 0 -o -z "$logfile" ]; then
        logger 'aborting... output file could not be created'
        exit 1
    fi
    logger "done! job output is going to $logfile"

    # ignore SIGHUP (SIGINT is ignored by default for asynchronous tasks)
    trap '' SIGHUP

    # detach from parent process
    logger 'sending detach signal (SIGUSR1) to client process'
    kill -s SIGUSR1 "$clientpid"
    logger "R: $?"

    # log job dispatch
    logger "dispatching job \"$jobpath\""
    declare item
    for item in "$@"; do
        logger "-- arg: $item"
    done
    unset -v item

    # dispatching job asynchronously
    "$jobpath" "$@" > "$logfile" 2>&1 &
    jobpid=$!
    logger "done! job PID is #$jobpid"

    # set iterruption trap
    logger 'setting termination trap'
    trap 'trap_termination_signal' SIGTERM
    logger "R: $?"

    # prepare to wait
    sigret=0
    retval=0

    # enter wait state
    logger 'waiting for job completion'
    wait $jobpid
    retval=$?

    # check if returning from trap
    if [ $sigret -gt 0 ]; then
        logger "trap executed ( w: $retval, s: $sigret )"
        logger 'waiting for interrupted job status code'
        wait $jobpid
        logger "R: $?"
    else
        logger "job exited with code: $retval"
    fi

    # clean up and leave
    clean_up
    logger 'clean exit... bye!'

else

    # make sure self path has been correctly resolved
    if ! is_valid_executable "$selfpath"; then
        logger 'Self reference could not be resolved...'
        exit 1
    fi

    # make sure jobs directory exists
    if ! mkdir -p "$rundir" > /dev/null 2>&1; then
        logger 'Jobs directory could not be created...'
        exit 1
    fi

    # make sure empty file exists
    if [ ! -f "$emptyfile" ]; then
        touch "$emptyfile" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            logger 'Empty file could not be created...'
            exit 1
        fi
        chmod 444 "$emptyfile"
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

    # check if specified job is valid
    if ! is_valid_executable "$jobpath"; then
        logger 'The absolute path for the specified job could not be reliably determined...'
        exit 1
    fi

    # get lockfile based on job path
    lockfile=$(getlockfilename "$jobpath")
    if [ $? -ne 0 -o -z "$lockfile" ]; then
        logger 'Error determining lock file path...'
        exit 1
    fi
    lockfile="$rundir/$lockfile"

    # evaluate command
    if [ "$cmdname" = 'start' ]; then

        # START

        if [ -f "$lockfile" ]; then
            logger 'The specified job seems to be already running...'
            exit 1
        fi

        # create lock
        touch "$lockfile" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            logger 'A lock file for the specified job could not be created...'
            exit 1
        fi

        # create log file based on job path
        logfile=$(getlogfile -m "$jobpath")
        if [ $? -ne 0 -o -z "$logfile" ]; then
            logger 'Error creating monitor log file...'
            exit 1
        fi
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
        # ... make sure no standard fd is a terminal
        "$selfpath" "$@" < "$emptyfile" >> "$logfile" 2>&1 &
        monitorpid=$!
        wait $monitorpid

        # ... execution should not reach this point
        clean_up
        logger 'Oops! The specified job died prematurely...'
        exit 1

        # ~ ~ ~

    elif [ "$cmdname" = 'stop' ]; then

        # STOP
        monitorpid=$(getmonitorpid)
        if [ $? -ne 0 -o -z "$monitorpid" ]; then
            logger 'The specified job does not seem to be running...'
            exit 1
        fi

        # send SIGTERM to monitor
        logger "Sending stop request to process #${monitorpid}..."
        kill -s SIGTERM "$monitorpid" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            logger 'Oops! Stop request failed...'
            exit 1
        fi
        logger 'Done!'

        logger 'Waiting for process completion...'
        while true; do
            is_process_alive "$monitorpid" || break
            sleep 2
        done
        logger 'Done!'

        # @TODO send SIGKILL if process takes too long to complete

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
