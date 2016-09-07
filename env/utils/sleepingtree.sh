#!/bin/bash

declare -i count

if [ $# -ge 1 ]; then
    count=$1
    shift 1
    echo "$$ dispatching ${count}..."
    while [ $count -gt 0 ]; do
        let count--
        "$0" "$@" &
    done
else
    sleep 120 &
    echo "$$ + $! ( ZzZz )..."
fi

# just wait...
wait
