#!/bin/bash

set -u

# include dependencies...
declare basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"

# declare main variables...
declare sharedir="$(abspath "$basedir/..")" sharename='/opt/share'
declare instance containerapp='ohif_app' containerdb='ohif_db'

function print_result {
    declare -i res="$1"
    declare inst="$2"
    if [ $res -ne 0 ]
    then
        echo 'Oops! Something went wrong...'
        echo "Please try running this script again or bringing the $inst Container up manually."
        exit 1
    else
        echo 'Done!'
    fi
}

function container_exists {
    declare containerid="$(docker ps -a -q -f "name=$1")"
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
    print_result "$?" "$instance"
else
    if ! container_running "$containerdb"
    then
        echo "Starting $instance Container..."
        docker start "$containerdb"
        print_result "$?" "$instance"
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
        print_result "$?" "$instance"
    else
        if ! container_running "$containerapp"
        then
            echo 'Starting APP Container...'
            docker start "$containerapp"
            print_result "$?" "$instance"
        else
            echo "$instance Container running!"
        fi
    fi
else
    echo 'Oops! DB Container should be running by now... Please try again.'
fi
