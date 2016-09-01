#!/bin/bash

set -u

# include dependencies...
declare basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"

# declare main variables...
declare share_h=$(abspath "$basedir/..") share_g='/home/ohif'
declare instance dkr_args dkcnt_app='ohif_app' dkcnt_db='ohif_db'

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
    declare containerid=$(docker ps -q -a -f "name=$1")
    test -n "$containerid"
}

function docker_container_running {
    declare containerid=$(docker ps -q -f "name=$1")
    test -n "$containerid"
}

function docker_format_args {
    if docker run --help | grep -q -E -e '--(name|link)='
    then
        echo "$1"
    else
        echo "$1" | tr '=' ' '
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
    dkr_args=$(docker_format_args "--name=$dkcnt_db")
    docker run -d -i -t -p 4242:4242 -p 8042:8042 $dkr_args jodogne/orthanc-plugins:latest
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
        dkr_args=$(docker_format_args "--name=$dkcnt_app --link=$dkcnt_db:$dkcnt_db")
        docker run -d -i -t -v "$share_h":"$share_g" -p 3000:3000 $dkr_args centos:7 /bin/bash
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
