#!/bin/bash

set -u

declare -a rkills=()

function rkill {
    local result child parent
    [ $# -gt 0 ] || return 1
    result=0
    parent=$1
    [ ${#rkills[@]} -gt 0 ] && rkills=( "${rkills[@]}" "$parent" ) || rkills=( "$parent" )
    kill -stop "$parent" || let 'result|=2'
    # ps --no-headers -o pid --ppid "$parent"
    # pgrep -P "$parent"
    for child in $(pgrep -P "$parent"); do
        rkill "$child"
        let "result|=$?"
    done
    kill -term "$parent" || let 'result|=4'
    kill -cont "$parent" || let 'result|=8'
    return $result
}

if [ $# -ge 1 ]; then
    rkill "$1"
    echo "Result: $?"
    echo "pids: ${rkills[*]}"
fi
