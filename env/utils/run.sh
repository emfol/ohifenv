#!/bin/bash

set -u

# ignore SIGHUP
trap '' SIGHUP

# vars -- base
declare db_host='ohif_db'
declare base_dir='/home/ohif'
declare src_dir="$base_dir/src"
declare tmp_dir="$base_dir/.proc"
declare orig_dir=$(pwd)
# vars -- proc
declare daemon_logf="$tmp_dir/daemon_log"
declare daemon_pidf="$tmp_dir/daemon_pid"
declare proxy_logf="$tmp_dir/proxy_log"
declare proxy_pidf="$tmp_dir/proxy_pid"
declare app_logf="$tmp_dir/app_log"
declare app_pidf="$tmp_dir/app_pid"
declare -i daemon_pid proxy_pid app_pid
# vars -- misc
declare proxy_js_target="$tmp_dir/proxy.js" proxy_js_src="$src_dir/etc/nodeCORSProxy.js"
declare app_tool app_project app_dir app_conf app_bin

# functions

function quiet_rm {
    rm -rf "$@" &> /dev/null
}

function is_proc_running {
    local -i pid=$1
    (( $pid > 0 )) && kill -0 $pid &> /dev/null
}

function stop_proc {
    local -i pid=$1
    if (( $pid > 0 ))
    then
        if kill -SIGINT $pid &> /dev/null
        then
            echo "Process #$pid killed!"
        else
            echo "Attempt to kill process #$pid failed..."
        fi
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
    if [ ! -f "$proxy_js_target" -o ! -s "$proxy_js_target" ]
    then
        sed -e 's/localhost:8042/ohif_db:8042/g' < "$proxy_js_src" > "$proxy_js_target"
        if [ ! -f "$proxy_js_target" -o ! -s "$proxy_js_target" ]
        then
            printf 'Error applying changes to proxy JS file...\n - %s\n - %s\n' "$proxy_js_src" "$proxy_js_target"
            exit 1
        fi
    fi
    # execute script
    cd "$(dirname "$proxy_js_target")"
    npm install http-proxy < /dev/null >> "$proxy_logf" 2>&1
    cd "$app_dir"
    node "$proxy_js_target" < /dev/null >> "$proxy_logf" 2>&1 &
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

# check parameter count

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

app_dir="$src_dir/$app_tool"

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

# make sure temporary directory exists...
if ! mkdir -p "$tmp_dir" &> /dev/null
then
    echo "Cannot create process directory ($tmp_dir)"
    exit 1
fi

# fork!
if [ -f "$daemon_pidf" ]
then
    daemon_pid=$(cat "$daemon_pidf")
    if [ $$ -ne $daemon_pid ]
    then
        echo "This job is already running ($daemon_pid)"
        exit 1
    fi
else
    "$0" < /dev/null >> "$daemon_logf" 2>&1 &
    echo "$!" > "$daemon_pidf"
    echo 'Starting servers in background...'
    exit 0
fi


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
