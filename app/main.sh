#!/bin/bash

set -u

declare basedir='/home/ohif'
declare argfile='/tmp/args-ohif.app.main.txt'
declare appdir='' appbin=''

if [ ! -s "$argfile" -o ! -r "$argfile" ]; then
    echo 'Arguments file not found or not accessible...'
    exit 1
fi

exec 3< "$argfile"
if [ $? -ne 0 ]; then
    echo 'Cannot open arguments file...'
    exit 2
fi

read -u 3 appdir
if [ $? -ne 0 -o -z "$appdir" -o ! -d "$appdir" ]; then
    echo 'Invalid argument for application directory...'
    exit 3
fi

cd "$appdir"

read -u 3 appbin
if [ $? -ne 0 -o -z "$appbin" -o ! -x "$appbin" ]; then
    echo 'Invalid argument for application binary...'
    exit 4
fi

# execute binary...
"$appbin" "$@"

