#!/bin/bash

set -u

declare basedir containerid containerapp='ohif_app' containerdb='ohif_db'
declare basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"

containerid="$(docker ps -aq -f "name=$containerdb")"
if [ -z "$containerid" ]
then
    docker run -dit --name "$containerdb" -p 4242:4242 -p 8042:8042 jodogne/orthanc
else
    echo "Container already created... $containerid"
fi
