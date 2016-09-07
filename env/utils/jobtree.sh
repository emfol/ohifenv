#!/bin/bash

set -u

declare -a list=()

function children {
    local indent child parent
    [ $# -ge 1 ] && parent=$1 || return 1
    [ $# -ge 2 ] && indent=$2 || indent=''
    [ ${#list[@]} -gt 0 ] && list=( "${list[@]}" "$parent" ) || list=( "$parent" )
    echo "${indent}${parent}"
    for child in $(pgrep -P "$parent"); do
        children "$child" "|-- ${indent}"
    done
    return 0
}

if [ $# -ge 1 ]; then
   if children "$1"; then
       echo "List: ${list[*]} ( #${#list[@]} )"
   else
       echo 'Oops! Something went wrong...'
   fi
else
   echo "Usage: $0 <pid>"
fi
