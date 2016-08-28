#!/bin/bash

set -u

# include dependencies...
declare basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"

# declare main variables...
declare sharedir="$(abspath "$basedir/..")" sharename='/mnt/share'
declare instance containerapp='ohif_app' containerdb='ohif_db'

function check_result {
    declare -i res="$1"
    declare inst="$2"
    if [ $res -ne 0 ]
    then
        echo 'Oops! Something went wrong...'
        echo "Please try running this script again or bring the $inst Container up manually."
        exit 1
    else
        echo 'Done!'
    fi
}

function container_exists {
    declare containerid="$(docker ps -q -a -f "name=$1")"
    test -n "$containerid"
}

function container_running {
    declare containerid="$(docker ps -q -f "name=$1")"
    test -n "$containerid"
}

# check if docker is installed...
if command_not_found 'docker'
then
    echo 'It seems Docker is not installed... :('
    exit 1
fi

instance='DB'
if ! container_exists "$containerdb"
then
    echo "Creating $instance Container..."
    docker run -d -i -t --name "$containerdb" -p 4242:4242 -p 8042:8042 jodogne/orthanc-plugins
    check_result "$?" "$instance"
else
    if ! container_running "$containerdb"
    then
        echo "Starting $instance Container..."
        docker start "$containerdb"
        check_result "$?" "$instance"
    else
        echo "$instance Container running!"
    fi
fi

instance='APP'
if container_running "$containerdb"
then
    if ! container_exists "$containerapp"
    then
        echo "Creating $instance Container..."
        docker run -d -i -t --name "$containerapp" --link "$containerdb" -v "$sharedir":"$sharename" -p 3000:3000 centos:7 /bin/bash
        check_result "$?" "$instance"
    else
        if ! container_running "$containerapp"
        then
            echo 'Starting APP Container...'
            docker start "$containerapp"
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
