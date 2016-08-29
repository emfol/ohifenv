#!/bin/bash

set -u

declare -i result=0
declare base_dir='/home/ohif/viewers'
declare db_host='ohif_db'
declare proxy_tmpd="$base_dir/.proc/proxy" app_tmpd="$base_dir/.proc/app"
declare proxy_pidf="$proxy_tmpd/pid" app_pidf="$app_tmpd/pid"
declare proxy_logf="$proxy_tmpd/log" app_logf="$app_tmpd/log"
declare proxy_jsf="$proxy_tmpd/proxy.js" proxy_jss="$base_dir/etc/nodeCORSProxy.js"
declare app_tool app_project app_dir app_conf app_bin app_pid app_log

# utils

function quiet_rm {
    rm -rf "$@" > /dev/null 2>&1
}

function is_proc_running {
    local pidf="$1"
    local -i pidn=0
    if [ -f "$pidf" -a -s "$pidf" ]
    then
        pidn=$(cat "$pidf")
        test $pidn -gt 0 && kill -0 $pidn > /dev/null 2>&1
    else
        return 1
    fi
}

function stop_proc {
    local pidf="$1"
    local -i pidn=0
    if [ -f "$pidf" -a -s "$pidf" ]
    then
        pidn=$(cat "$pidf")
        test $pidn -gt 0 && kill -SIGINT $pidn > /dev/null 2>&1
        if [ $? -eq 0 ]
        then
            echo "Process killed... $pidn"
        fi
        quiet_rm "$pidf"
    fi
}

function proxy_run {
    local -i pidn=0
    # check if proxy already running...
    if is_proc_running "$proxy_pidf"
    then
        echo "Proxy already running..."
        return
    fi
    # start fresh
    quiet_rm "$proxy_pidf"
    # adapt proxy script
    if [ ! -f "$proxy_jsf" -o ! -s "$proxy_jsf" ]
    then
        sed -e 's/localhost:8042/ohif_db:8042/g' < "$proxy_jss" > "$proxy_jsf"
        if [ ! -f "$proxy_jsf" -o ! -s "$proxy_jsf" ]
        then
            printf 'Error applying changes to proxy JS file...\n - %s\n - %s\n' "$proxy_jss" "$proxy_jsf"
            exit 1
        fi
    fi
    # execute script
    cd "$(dirname "$proxy_jsf")"
    npm install http-proxy < /dev/null >> "$proxy_logf" 2>&1
    cd "$app_dir"
    node "$proxy_jsf" < /dev/null >> "$proxy_logf" 2>&1 &
    pidn="$!"
    echo "$pidn" > "$proxy_pidf"
    # wait a few second to see if the service is really running
    sleep 2
    if ! is_proc_running "$proxy_pidf"
    then
        echo 'Proxy server stayed up for less than 2 seconds... Aborting.'
        exit 1
    fi
    echo "Proxy started with PID $pidn!"
}

function print_usage {
    printf "Usage:\n\t%s <OV|LT> <project>\n\n" "$0"
}

function clean_up {
    echo 'Clean up routine invoked.'
    echo 'Stopping proxy...'
    stop_proc "$proxy_pidf"
    echo 'Done!'
}

# check parameters

if [ $# -lt 2 ]
then
    print_usage
    exit 1
fi

app_tool=$(echo "$1" | tr '[A-Z]' '[a-z]')
app_project="$2"

# determine tool

if [ "$app_tool" = 'ov' ]
then
    app_tool='OHIFViewer'
elif [ "$app_tool" = 'lt' ]
then
    app_tool='LesionTracker'
else
    echo "Invalid option: $app_tool"
    print_usage
    exit 1
fi

app_dir="$base_dir/$app_tool"

# check if app directory exists

if [ -d "$app_dir" ]
then
    cd "$app_dir"
else
    echo "Application directory not found ($app_dir)"
    exit 1
fi

# check binary and config files

app_bin="bin/${app_project}.sh"
app_conf="../config/${app_project}.json"

if [ ! -f "$app_conf" ]
then
    echo "Configuration file not found ($app_conf)"
    exit 1
fi

if [ ! -f "$app_bin" ]
then
    echo "Bootstrap script not found ($app_bin)"
    exit 1
fi

# directory setup

mkdir -p "$proxy_tmpd" "$app_tmpd"

# set signal handlers

trap 'clean_up' SIGINT

# start services

echo 'Starting services...'
proxy_run
echo 'Done!'
wait
result="$?"

clean_up

exit $result
