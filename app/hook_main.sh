#!/bin/bash

set -u

declare basedir='/home/ohif'
declare projectnames='LesionTracker|OHIFViewer'
declare dbhost='ohif_db:8042'
declare argfile='/tmp/args-ohif.app.main.txt'
declare -a binaries=() projects=()
declare project='' projectdir='' config='' binary=''

# make sure we are working on a brand new hook file...
rm -rf "$argfile" > /dev/null 2>&1

# this hook requires a terminal...
if [ ! -t 0 -o ! -t 1 ]; then
    echo 'This hook requires a terminal...'
    exit 1
fi

PS3='Which one would you like to run? '

cd "$basedir"

for project in $(ls -p src | grep -E -e "^($projectnames)/$"); do
    project=${project%/}
    [ ${#projects[@]} -gt 0 ] && projects=( "${projects[@]}" "$project" ) || projects=( "$project" )
done

if [ ${#projects[@]} -lt 1 ]; then
    echo 'No projects found...'
    exit 2
fi

echo 'The following projects were found:'
select project in "${projects[@]}"; do
    if [ -n "$project" ]; then
        echo " -- Selected: $project"
        break
    fi
done

if [ -z "$project" ]; then
    echo 'Aborting! No project selected...'
    exit 3
fi

projectdir="src/$project"
cd "$projectdir"
projectdir=$(pwd)

for binary in $(ls bin | grep -E -e "\.sh$"); do
    binary=${binary%.sh}
    [ ${#binaries[@]} -gt 0 ] && binaries=( "${binaries[@]}" "$binary" ) || binaries=( "$binary" )
done

if [ ${#binaries[@]} -lt 1 ]; then
    echo 'No binaries found...'
    exit 4
fi

echo 'The following binaries were found:'
select binary in "${binaries[@]}"; do
    if [ -n "$binary" ]; then
        echo " -- Selected: $binary"
        break
    fi
done

config="../config/${binary}.json"
binary="bin/${binary}.sh"

if grep -q -E -e '\blocalhost:8042\b' "$config"; then
    echo 'Updating DB HOST configuration on config file...'
    sed -e "s/\([^[:alnum:]]\)localhost:8042\([^[:alnum:]]\)/\1$dbhost\2/g" -i.bak "$config"
    echo 'Done!'
fi

echo 'Creating arguments file...'

exec 3>&1 > "$argfile" || exit 5

echo "$projectdir"
echo "$binary"
echo "$config"

exec 1>&- 1>&3- || exit 6

echo 'Done!'

exit 0
