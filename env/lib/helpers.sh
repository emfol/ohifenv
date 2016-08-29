#!/bin/bash

function abspath {
    local olddir=$(pwd) dir="$1"
    if [ -d "$dir" ]
    then
        cd "$dir"
        echo "$(pwd)"
        cd "$olddir"
    else
        dir=$(dirname "$dir")
        if [ -d "$dir" ]
        then
            cd "$dir"
            echo "$(pwd)/$(basename "$1")"
            cd "$olddir"
        else
            return 1
        fi
    fi
    return 0
}

function print_error {
    printf 'Error! %s\n' "$*" 1>&2;
}

function get_tmpf {
    mktemp -q
}

function get_tmpd {
    mktemp -q -d
}

function quiet_rm {
    rm -rf "$@" > /dev/null 2>&1
}

function command_found {
    command -v "$1" > /dev/null 2>&1
}

function command_not_found {
    ! command_found "$1"
}
