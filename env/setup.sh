#!/bin/bash

set -u

declare -i status=0
declare resp basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"
declare tjn_dir tjn_url="https://github.com/tj/n"
declare meteor_sh meteor_url="https://install.meteor.com/"
declare git_user_name="" git_user_email=""
declare ohif_dir="/home/ohif" ohif_url="https://github.com/OHIF/Viewers"

# yum packages
yum install -y tree vim curl git make
if [ $? -ne 0 ]
then
    let "status|=1"
    print_error "Error executing package manager..."
fi

# Node.js
if command_not_found "node"
then
    tjn_dir="$(get_tmpd)"
    if [ $? -eq 0 ]
    then
        cd "$tjn_dir"
        git clone "$tjn_url" .
        if [ $? -eq 0 ]
        then
            PREFIX="/usr/local" make install
            if command_not_found "n" then
            then
                let "status|=2"
                print_error "Cannot install tj/n..."
            else
                n lts
                if [ $? -ne 0 ]
                then
                    let "status|=2"
                    print_error "Cannot install node through tj/n..."
                fi
            fi
        else
            let "status|=2"
            print_error "The tj/n git repo could not be cloned..."
        fi
        quiet_rm "$tjn_dir"
    else
        let "status|=2"
        print_error "Cannot create directory for tj/n git repo..."
    fi
fi

# Meteor
if command_not_found "meteor"
then
    echo 'Setting up Meteor...'
    meteor_sh="$(get_tmpf)"
    if [ -f "$meteor_sh" ]
    then
        curl -s -L "$meteor_url" > "$meteor_sh"
        if [ $? -eq 0 -a -s "$meteor_sh" ]
        then
            sh < "$meteor_sh"
            if [ $? -ne 0 ]
            then
                let "status|=4"
                print_error "Failure executing Meteor install script..."
            fi
        else
            let "status|=4"
            print_error "Could not reach meteor install script..."
        if 
        quiet_rm "$meteor_sh"
    fi
else
    echo 'Meteor already installed...'
fi

# Do we have Git?
if command_found "git"
then
    # Should we setup Git?
    read -p "Setup Git now? [y/N] " resp
    if [ "$resp" = "y" -o "$resp" = "Y" ]
    then
        echo ' - Setting up Git...'
        echo ' - Please provide the following info about the commit author...'
        read -p '   > Name: ' git_user_name
        read -p '   > Email: ' git_user_email
        git config --global core.editor vim
        git config --global color.ui true
        git config --global user.name "$git_user_name"
        git config --global user.email "$git_user_email"
    fi
    # clone repos...
fi

exit $status
