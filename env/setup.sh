#!/bin/bash

set -u

declare -i count status=0
declare resp origdir="$(pwd)" basedir=$(dirname "$0")
source "$basedir/lib/helpers.sh"
basedir="$(abspath "$basedir")"
declare tjn_dir tjn_url="https://github.com/tj/n"
declare meteor_sh meteor_url="https://install.meteor.com/"
declare git_user_name git_user_email
declare ohif_dir="/home/ohif/viewers" ohif_url="https://github.com/OHIF/Viewers"
declare -a missing_packages packages=(tree vim curl git make)
declare pkg

# some info...
printf "Provisioning container with %s/%s...\n" "$basedir" "$(basename "$0")"

# install packages
count=0
for pkg in "${packages[@]}"
do
   if command_not_found "$pkg"
   then
       let count+=1
       missing_packages[$count]="$pkg"
   fi
done

if [ ${#missing_packages[@]} -ne 0 ]
then
    echo "Installing packages..."
    yum install -y "${missing_packages[@]}"
    if [ $? -ne 0 ]
    then
        print_error "Package manager failed to execute and provisioning cannot proceed..."
        exit 1
    else
        echo 'Done!'
        printf 'The following packages where installed: %s\n' "${missing_packages[*]}"
    fi
else
    echo 'No package to be installed...'
fi

# Node.js
if command_not_found "node"
then
    echo 'Installing Node.js...'
    tjn_dir="$(get_tmpd)"
    if [ $? -eq 0 ]
    then
        echo '... Cloning tj/n Node.js version manager...'
        cd "$tjn_dir"
        git clone "$tjn_url" .
        if [ $? -eq 0 ]
        then
            echo '... Done!'
            echo '... Installing tj/n...'
            PREFIX="/usr/local" make install
            if command_found "n"
            then
                echo '... Done!'
                n lts
                if [ $? -ne 0 ]
                then
                    let "status|=2"
                    print_error "Cannot install node through tj/n..."
                fi
            else
                let "status|=2"
                print_error "Cannot install tj/n..."
            fi
        else
            let "status|=2"
            print_error "The tj/n git repo could not be cloned..."
        fi
        echo '... Clean up!'
        cd "$origdir"
        quiet_rm "$tjn_dir"
    else
        let "status|=2"
        print_error "Cannot create directory for tj/n git repo..."
    fi
else
    echo 'Node.js already installed...'
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
            else
                echo 'Done!'
            fi
        else
            let "status|=4"
            print_error "Could not reach meteor install script..."
        fi
        echo '... Clean up!'
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
    mkdir -p "$ohif_dir" && cd "$ohif_dir"
    count="$(ls -A . | wc -l)"
    if [ $count -lt 2 ]
    then
        echo "Cloning OHIF Viewers directory..."
        # remove pottentialy broken Git clone
        quiet_rm ".git"
        git clone "$ohif_url" .
        if [ $? -ne 0 ]
        then
            print_error "Error cloning OHIF Viewers repo..."
            let "status|=8"
        else
            echo 'Done!'
        fi
    fi
    cd "$origdir"
fi

exit $status
