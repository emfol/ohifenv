#!/bin/bash

set -u

declare basedir sharedir sharedirname='/opt/share' containerapp='ohif_app' containerdb='ohif_db'
declare basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"
sharedir="$(abspath "$0")"

if docker port "$containerdb" > /dev/null 2>&1
then
    docker run -dit --name "$containerapp" --link "$containerdb" -v "$sharedir":"$sharedirname" -p 3000:3000 centos:7 /bin/bash
else
    print_error "Database container not found... Please create one before creating the app container."
fi
