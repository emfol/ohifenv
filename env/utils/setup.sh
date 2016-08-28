#!/bin/bash

set -u

# include dependencies...
declare basedir=$(dirname "$0")
source "$basedir/../lib/helpers.sh"
basedir="$(abspath "$basedir")"

# main vars
declare -i count status=0
declare item resp='' origdir="$(pwd)"
# tj/n/node.js vars
declare tjn_dir tjn_url="https://github.com/tj/n"
# meteor vars
declare meteor_sh meteor_url="https://install.meteor.com/"
# git/ohif vars
declare git_user_name git_user_email
declare ohif_dir="/home/ohif/viewers" ohif_url="https://github.com/OHIF/Viewers"
# yum var
declare -a yum_pkgs_missing yum_pkgs_list=(tree vim curl git make)
# logs
declare logfile="/tmp/$(basename "$0").log"

# display some info...
printf "Provisioning container with [ %s/%s ]\n" "$basedir" "$(basename "$0")"
echo   " ... for more info, please refer to [ $logfile ]"

# reset log file
date > "$logfile"

# install YUM packages
count=0
for item in "${yum_pkgs_list[@]}"
do
   if command_not_found "$item"
   then
       let count+=1
       yum_pkgs_missing[$count]="$item"
   fi
done
if [ ${#yum_pkgs_missing[@]} -gt 0 ]
then
    echo "The following YUM packages will be installed: ${yum_pkgs_missing[*]}"
    echo ' ... Executing YUM'
    yum install -y "${yum_pkgs_missing[@]}" >> "$logfile" 2>&1
    if [ $? -ne 0 ]
    then
        print_error 'YUM failed and provisioning cannot proceed... Please try again later.'
        exit 1
    else
        echo 'Done!'
    fi
else
    echo 'All needed YUM packages installed!'
fi

# Node.js and Node.js Version Menager
if command_not_found 'node'
then
    echo 'Installing Node.js and Node.js Version Manager (tj/n)'
    tjn_dir="$(get_tmpd)"
    if [ -d "$tjn_dir" ]
    then
        echo ' ... Cloning tj/n'
        cd "$tjn_dir"
        git clone "$tjn_url" . >> "$logfile" 2>&1
        if [ $? -eq 0 ]
        then
            echo ' ... Done!'
            echo ' ... Installing tj/n'
            PREFIX='/usr/local' make install >> "$logfile" 2>&1
            if test $? -eq 0 && command_found "n"
            then
                echo ' ... Done!'
                echo ' ... Installing Node.js LTS'
                n lts >> "$logfile" 2>&1
                if [ $? -eq 0 ]
                then
                    echo ' ... Done!'
                else
                    let 'status|=2'
                    print_error 'Cannot install Node.js through tj/n...'
                fi
            else
                let 'status|=2'
                print_error 'Cannot install tj/n...'
            fi
        else
            let 'status|=2'
            print_error 'The tj/n git repo could not be cloned...'
        fi
        echo ' ... Clean up!'
        cd "$origdir"
        quiet_rm "$tjn_dir"
        echo 'Complete.'
    else
        let 'status|=2'
        print_error 'Cannot create directory for cloning tj/n git repo...'
    fi
else
    echo 'Node.js and Node.js Version Manager already installed!'
fi

# Meteor
if command_not_found 'meteor'
then
    echo 'Installing Meteor'
    meteor_sh="$(get_tmpf)"
    if [ -f "$meteor_sh" ]
    then
        echo ' ... Downloading installation script'
        curl -s -L "$meteor_url" > "$meteor_sh" 2>> "$logfile"
        if [ $? -eq 0 -a -s "$meteor_sh" ]
        then
            echo ' ... Done!'
            echo ' ... Executing installation script'
            sh < "$meteor_sh" >> "$logfile" 2>&1
            if [ $? -eq 0 ]
            then
                echo ' ... Done!'
            else
                let 'status|=4'
                print_error 'Failure executing Meteor install script...'
            fi
        else
            let 'status|=4'
            print_error 'Installation script could not be downloaded...'
        fi
        echo ' ... Clean up!'
        quiet_rm "$meteor_sh"
        echo 'Complete.'
    else
        let 'status|=4'
        print_error 'Cannot create temporary file for Metoer install script...'
    fi
else
    echo 'Meteor already installed!'
fi

# Do we have Git?
if command_found 'git'
then
    # if tty, setup Git?
    test -t 0 && read -p 'Setup Git now? [y/N] ' resp
    if [ "$resp" = 'y' -o "$resp" = 'Y' ]
    then
        echo 'Setting up Git'
        echo ' ... Please provide the following info about the committer:'
        read -p ' ... Name : ' git_user_name
        read -p ' ... Email: ' git_user_email
        git config --global core.editor 'vim'
        git config --global color.ui 'true'
        git config --global user.name "$git_user_name"
        git config --global user.email "$git_user_email"
        echo 'Done!'
    fi
    # clone repos...
    mkdir -p "$ohif_dir" && cd "$ohif_dir"
    count="$(ls -A . | wc -l)"
    if [ $count -lt 2 ]
    then
        echo 'Cloning OHIF Viewers repository'
        # remove pottentialy broken Git clone
        quiet_rm '.git'
        git clone "$ohif_url" . >> "$logfile" 2>&1
        if [ $? -eq 0 ]
        then
            echo 'Done!'
        else
            print_error 'Error cloning OHIF Viewers repo...'
            let 'status|=8'
        fi
    fi
    cd "$origdir"
fi

exit $status
