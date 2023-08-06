#!/bin/bash
#
# package util:: 
# various tools
# part of https://github.com/renevoorburg/oailite 


util::err() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") $@" >&2
}


util::rawurlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

util::exit_on_keypress() {
    local listen="$1"
    local msg="$2"
    local alert="$3"
        
    echo -en "$msg"
    read -t 2 -n 1 key && [[ $key = "$listen" ]] && echo -e "\n$alert" && exit 1
    printf '\b%.0s' {1..100}
    printf ' %.0s' {1..100}
    printf '\b%.0s' {1..100}
}