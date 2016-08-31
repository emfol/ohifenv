#!/bin/bash

function abspath {
    local file path=$1
    if [ "${path:0:1}" = '/' ]
    then
        echo "$path"
    elif [ -d "$path" ]
    then
        cd "$path"
        echo "$PWD"
        cd "$OLDPWD"
    else
        file=$(basename "$path")
        path=$(dirname "$path")
        if [ -d "$path" ]
        then
            cd "$path"
            echo "$PWD/$file"
            cd "$OLDPWD"
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
