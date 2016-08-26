#!/bin/bash

function abspath {                                               
    local dir="$(dirname "$1")"
    if [ -d "$dir" ]
    then
        cd "$dir"
        printf "%s/%s\n" "$(pwd)" "$(basename "$1")"
        cd "$OLDPWD"
    else
        return 1
    fi
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
    ! command_found
}
