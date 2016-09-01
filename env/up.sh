#!/bin/bash

set -u

# include dependencies...
declare basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"

# declare main variables...
declare share_h=$(abspath "$basedir/..") share_g='/home/ohif'
declare instance dkcnt_app='ohif_app' dkcnt_db='ohif_db'
declare -a docker_args

# utility functions...
function check_result {
    local -i res="$1"
    local inst="$2"
    if [ $res -ne 0 ]
    then
        echo 'Oops! Something went wrong...'
        echo "Please try running this script again or bring the $inst Container up manually."
        exit 1
    else
        echo 'Done!'
    fi
}

function docker_container_exists {
    local dkcntid=$(docker ps -q -a -f "name=$1")
    test -n "$dkcntid"
}

function docker_container_running {
    local dkcntid=$(docker ps -q -f "name=$1")
    test -n "$dkcntid"
}

function docker_format_args {
    local -a list
    local -i i j
    local prev curr
    if docker run --help | grep -q -E -e '--(name|link)='
    then
        (( i = 0, j = 0 ))
        for curr in "${docker_args[@]}"
        do
            (( ++i % 2 == 0 )) && list[j++]="$prev=$curr" || prev=$curr
        done
        [ ${#list[@]} -gt 0 ] && docker_args=( "${list[@]}" )
    fi
}

# check if docker is installed...
if command_not_found 'docker'
then
    echo 'It seems Docker is not installed... :('
    exit 1
fi

instance='DB'
if ! docker_container_exists "$dkcnt_db"
then
    echo "Creating $instance Container..."
    docker_args=( '--name' "$dkcnt_db" )
    docker_format_args
    docker run -d -i -t -p 4242:4242 -p 8042:8042 "${docker_args[@]}" jodogne/orthanc-plugins:latest
    check_result "$?" "$instance"
else
    if ! docker_container_running "$dkcnt_db"
    then
        echo "Starting $instance Container..."
        docker start "$dkcnt_db"
        check_result "$?" "$instance"
    else
        echo "$instance Container running!"
    fi
fi

instance='APP'
if docker_container_running "$dkcnt_db"
then
    if ! docker_container_exists "$dkcnt_app"
    then
        echo "Creating $instance Container..."
        docker_args=( '--name' "$dkcnt_app" '--link' "$dkcnt_db:$dkcnt_db" )
        docker_format_args
        docker run -d -i -t -v "$share_h":"$share_g" -p 3000:3000 "${docker_args[@]}" centos:7 /bin/bash
        check_result "$?" "$instance"
    else
        if ! docker_container_running "$dkcnt_app"
        then
            echo 'Starting APP Container...'
            docker start "$dkcnt_app"
            check_result "$?" "$instance"
        else
            echo "$instance Container running!"
        fi
    fi
else
    echo 'Oops! DB Container should be running by now... Please try again.'
    exit 2
fi

exit 0
