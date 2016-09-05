#!/bin/bash

set -u

#############
# FUNCTIONS #

function print_usage {
    echo "Usage: $0 start  path/to/job [arg ...]"
    echo "       $0 stop   path/to/job"
    echo "       $0 status path/to/job [-m]"
    echo "       $0 list"
}

function command_path {
    local basedir abspath
    [ $# -gt 0 ] || return 1
    [ -n "$1" ] || return 2
    abspath=$(type -P "$1")
    [ $? -eq 0 -a -n "$abspath" ] || return 3
    if [ "${abspath:0:1}" != '/' ]; then
        basedir=$(dirname "$abspath")
        abspath=$(basename "$abspath")
        if [ "$basedir" = '.' ]; then
            basedir=$(pwd)
        else
            cd "$basedir" > /dev/null 2>&1 || return 4
            basedir=$(pwd)
            cd "$OLDPWD" > /dev/null 2>&1 || return 5
        fi
        abspath="$basedir/$abspath"
    fi
    echo "$abspath"
    return 0
}

function is_valid_executable {
    local filepath
    [ $# -gt 0 ] || return 1
    filepath=$1
    [ ${#filepath} -gt 1 ] || return 2
    [ "${filepath:0:1}" = '/' ] || return 3
    [ -f "$filepath" -a -x "$filepath" ] || return 4
    return 0
}

function is_monitor_mode {
    # not in monitor mode if any standard fd is a terminal
    [ -t 0 -o -t 1 -o -t 2 ] && return 1
    # not in monitor mode if any of these variables is empty
    [ -n "$jobpath" -a -n "$lockfile" -a -n "$clientpid" ] || return 2
    # not in monitor mode if client PID is not PPID
    [ "$clientpid" = "$PPID" ] || return 3
    # not in monitor mode if lock file is not a file or is empty
    [ -f "$lockfile" -a -s "$lockfile" ] || return 4
    # not in monitor mode if job path is not an executable file
    [ -f "$jobpath" -a -x "$jobpath" ] || return 5
    return 0
}

function sanity_check {

    local data cpid mpid

    # check if job path is a valid executable
    is_valid_executable "$jobpath" || return 1

    # check if lock file is readable and writable
    [ -f "$lockfile" -a -r "$lockfile" -a -w "$lockfile" ] || return 2

    # check the contents of lock file
    read data < "$lockfile"
    [ -n "$data" ] || return 3
    cpid=${data%:*}
    mpid=${data#*:}
    [ "$cpid" = "$clientpid" -a "$mpid" = '0' ] || return 4

    # store monitor PID
    monitorpid=$$
    echo "$clientpid:$monitorpid" > "$lockfile"

    # make sure the client (parent) process is alive
    kill -n 0 "$clientpid" || return 5

    return 0

}

function getjobkey {
    local -i maxlen=80
    local keyname
    [ $# -gt 0 ] || return 1
    [ -n "$1" ] || return 2
    keyname=$1
    keyname=${keyname#/}
    keyname=${keyname// /_}
    keyname=${keyname//\//.}
    if [ ${#keyname} -gt $maxlen ]; then
        keyname=${keyname:$(( ${#keyname} - $maxlen ))}
        keyname=${keyname#.}
    fi
    echo "$keyname"
    return 0
}

function getlockfilepath {
    local keyname
    [ $# -gt 0 ] || return 1
    [ -n "$1" ] || return 2
    keyname=$(getjobkey "$1")
    [ $? -eq 0 -a -n "$keyname" ] || return 3
    echo "$rundir/${keyname}.lock"
    return 0
}

function getlogfile {
    local keyname extname filepath optarg=''
    [ $# -ge 2 ] || return 1
    [ "$1" = '-m' -o "$1" = '-j' ] || return 2
    [ -n "$2" ] || return 3
    # check for optional argument
    if [ $# -gt 2 ]; then
        optarg=$3
    fi
    keyname=$(getjobkey "$2")
    [ $? -eq 0 -a -n "$keyname" ] || return 4
    if [ "$1" = '-j' ]; then
        extname='job'
    else
        extname='mon'
    fi
    filepath="$rundir/${keyname}.${extname}.log"
    if [ "$optarg" = '-ro' ]; then
        [ -f "$filepath" -a -r "$filepath" ] || return 5
    else
        touch "$filepath" > /dev/null 2>&1 || return 6
        [ -f "$filepath" -a -w "$filepath" ] || return 7
    fi
    echo "$filepath"
    return 0
}

function getmonitorpid {
    local pid filepath
    [ $# -gt 0 ] || return 1
    [ -n "$1" ] || return 2
    filepath=$1
    # file exists?
    [ -f "$filepath" -a -r "$filepath" ] || return 3
    # check file contents
    read pid < "$filepath"
    [ -n "$pid" ] || return 4
    # remove client pid
    pid=${pid#*:}
    [ -n "$pid" ] || return 5
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
    sigret=1
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

    # enter wait state
    logger 'waiting for job completion'
    wait $jobpid
    retval=$?

    # check if returning from trap
    if [ $sigret -eq 0 ]; then
        # no trap executed
        logger "job exited with code: $retval"
    else
        # trap executed
        logger "trap executed ( w: $retval, s: $sigret )"
        if [ $sigret -eq 2 ]; then
            # repeat wait call
            logger 'waiting for interrupted job status code'
            wait $jobpid
            logger "R: $?"
        else
            logger "not expecting such trap return code: $sigret"
        fi
    fi

    # clean up and leave
    clean_up
    logger 'clean exit... bye!'

else

    # make sure self path has been correctly resolved
    is_valid_executable "$selfpath"
    if [ $? -ne 0 ]; then
        logger 'Self reference could not be resolved...'
        exit 1
    fi

    # make sure jobs directory exists
    if [ ! -d "$rundir" ]; then
        mkdir -p "$rundir" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            logger 'Jobs directory could not be created...'
            exit 1
        fi
    fi

    # make sure empty file exists
    if [ ! -f "$emptyfile" ]; then
        touch "$emptyfile" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            logger 'Empty file could not be created...'
            exit 1
        fi
        chmod 444 "$emptyfile" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            logger 'Error changing mode of empty file...'
            exit 1
        fi
    fi

    # check arguments
    if [ $# -lt 1 ]; then
        print_usage
        exit 1
    fi

    # define command name
    cmdname=$1
    # ... and shift parameters
    shift 1

    # check if command requires a job argument
    if [[ "$cmdname" =~ ^(start|stop|status)$ ]]; then

        # check arguments
        if [ $# -lt 1 ]; then
            print_usage
            exit 1
        fi

        # define job
        jobpath=$1
        # ... and shift parameters
        shift 1

        # check if specified job exists
        jobpath=$(command_path "$jobpath")
        if [ $? -ne 0 -o -z "$jobpath" ]; then
            logger 'The specified job could not be found...'
            exit 1
        fi

        # check if specified job is valid
        is_valid_executable "$jobpath"
        if [ $? -ne 0 ]; then
            logger 'The absolute path for the specified job could not be reliably determined...'
            exit 1
        fi

        # get lockfile based on job path
        lockfile=$(getlockfilepath "$jobpath")
        if [ $? -ne 0 -o -z "$lockfile" ]; then
            logger 'Error determining lock file path...'
            exit 1
        fi

    fi

    # execute command
    if [ "$cmdname" = 'start' -a -n "$jobpath" -a -n "$lockfile" ]; then

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

        # # check for any hooks
        # if is_valid_executable "hook_$jobpath"; then
        #     "hook_$jobpath" "${@:3}"
        # fi

        # create log file for monitor based on job path
        logfile=$(getlogfile -m "$jobpath")
        if [ $? -ne 0 -o -z "$logfile" ]; then
            logger 'Error creating log file for monitor process...'
            exit 1
        fi

        # export necessary variables and initialize lock file
        export xjobshjobpath="$jobpath" xjobshlockfile="$lockfile" xjobshclientpid="$$"
        echo "$xjobshclientpid:0" > "$xjobshlockfile"

        # set detach signal handler (SIGUSR1)
        trap 'trap_detach_signal' SIGUSR1

        # dispatch monitor process and wait for detach signal (SIGUSR1)
        # ... make sure no standard fd is a terminal
        "$selfpath" "$@" < "$emptyfile" > "$logfile" 2>&1 &
        monitorpid=$!

        # prepare to wait
        sigret=0

        # enter wait state
        wait $monitorpid
        retval=$?

        logger "( #: $monitorpid, w: $retval, s: $sigret )"

        if [ $sigret -eq 0 ]; then
            # no trap executed
            logger "Oops! The job died prematurely with code #${retval}... :-("
            clean_up
        else
            # trap executed
            if [ $sigret -eq 1 ]; then
                logger 'Done!'
            else
                logger "Oops! Not quite what we were expecting... ( s: $sigret )"
            fi
        fi

        # ~ ~ ~
    elif [ "$cmdname" = 'stop' -a -n "$jobpath" -a -n "$lockfile" ]; then

        # STOP

        monitorpid=$(getmonitorpid "$lockfile")
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
    elif [ "$cmdname" = 'status' -a -n "$jobpath" -a -n "$lockfile" ]; then

        # STATUS

        declare result optarg='-j'

        monitorpid=$(getmonitorpid "$lockfile")
        result=$?
        [ $result -eq 0 -a -n "$monitorpid" ] && logger '[ RUNNING ]' || logger "[ NOT RUNNING ] #$result"

        if [ $# -gt 0 ] && [ "$1" = '-m' ]; then
            optarg='-m'
        fi

        logfile=$(getlogfile "$optarg" "$jobpath" -ro)
        result=$?
        if [ $result -eq 0 -a -n "$logfile" ]; then
            logger "[ $logfile ]"
            cat "$logfile"
        else
            logger "Nothing to print... #$result"
            exit 1
        fi

        unset -v result optarg

        # ~ ~ ~
    elif [ "$cmdname" = 'list' ]; then

        # LIST

        ls -p "$rundir" | grep -e '.\.lock$' | while read line; do
            echo "${line%.lock}"
        done;

        # ~ ~ ~
    else

        # NONE

        print_usage
        exit 1

        # ~ ~ ~
    fi

fi

exit 0
