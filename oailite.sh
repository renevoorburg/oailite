#!/bin/bash
set +H

## declare global vars:
curl='curl -fs'
wget='wget -q -t 3 -O -'
prog=$0
script_dir=$(dirname "$prog")
identifiers_xpath="//*[local-name()='header'][not(contains(@status, 'deleted'))]/*[local-name()='identifier']"
resumptiontoken_xpath="//*[local-name()='resumptionToken']/text()"
metadata_xpath="//*[local-name()='metadata']"

resumptiontoken=''
get=''

source "$script_dir/cfg/settings.sh"
if [ -f "$script_dir/cfg/settings_local.sh" ] ; then
    # in .gitignore:
    source "$script_dir/cfg/settings_local.sh"
fi

source "$script_dir/db/${DB_ENGINE}.sh"
if [ -f "$script_dir/db/${DB_ENGINE}_local.sh" ] ; then
    # in .gitignore:
    source "$script_dir/db/${DB_ENGINE}_local.sh"
fi


usage() {
    cat << EOF
usage: $prog [OPTIONS] -b [baseURL]

This is a simple OAI-PMH harvester that stores retrieved records in a sqlite database. 
The harvesting process can be paused by pressing 'p'. Restart harvest by supplying a resumptiontoken using '-r'.

Select either sqlite3 or postgres to be used by editing "$script_dir/include/settings.sh".

OPTIONS:
-h           Show this message
-v           Verbose, shows progress
-s  set      Specify a set to be harvested
-p  prefix   Choose which metadata format ('metadataPrefix') to harvest
-f  date     Define a 'from' date.
-u  date     Define an 'until' date
-r  token    Provide a resumptiontoken to continue a harvest
-d  database The sqlite database to use. Uses the set name for a database  when not supplied.
-t  table    The database table to use. Uses the prefix name as a table when not supplied.

EXAMPLE:
$prog -v -s ALBA -p dcx -f 2012-02-01T09:04:23Z -b http://services.kb.nl/mdo/oai

EOF
    exit
}


check_software_dependencies() {
    # check for required tools:
    if ! hash perl 2>/dev/null; then
        echo "Requires perl. Not found. Exiting."
        exit 1
    fi
    if hash curl 2>/dev/null; then
        get="$curl"
    elif hash wget  2>/dev/null; then
        get="$wget"
    else
        echo "Requires curl or wget. Not found. Exiting."
        exit 1
    fi
    if ! hash xmllint 2>/dev/null; then
        echo "Requires xmllint. Not found. Exiting."
        exit 1
    fi
}


read_commandline_parameters() {
    local option
    
    while getopts "hvd:t:f:u:b:s:p:r:e:" option ; do
        case $option in
            h)  usage
                ;;
            v)  verbose=true
                ;;
            d)  database=$(db::normalize_name "$OPTARG")
                ;;
            t)  table=$(db::normalize_name "$OPTARG")
                ;;
            f)  from_param="&from=$OPTARG"
                ;;
            u)  until_param="&until=$OPTARG"
                ;;
            s)  set="$OPTARG"
                set_param="&set=$OPTARG"
                ;;
            b)  oai_base="$OPTARG"
                ;;
            p)  prefix="$OPTARG"
                prefix_param="&metadataPrefix=$OPTARG"
                ;;
            r)  resumptiontoken="$OPTARG"
                ;;
            ?)  usage
                ;;
        esac
    done
}


check_parameter_validity() {
    if [ -z "$database" ] ; then
        if [ -z "$set" ] ; then
            echo "A database (-d) or set (-s) must be specified. "
            usage
        else
            database=$(db::normalize_name "$set")
        fi
    fi
    if [ -z "$table" ] ; then
        if [ -z "$prefix" ] ; then
            echo "A table (-t) of prefix (-p) must be specified."
            usage
        else
            table=$(db::normalize_name "$prefix")
        fi
    fi 
    if [ -z "$oai_base" ] ; then
        echo "A base url (-b) must be specified."
        usage
    fi
}


set_harvest_parameters() {
    if [ -z "$resumptiontoken" ] ; then
        resumptiontoken='dummy'
        url="$oai_base?verb=ListIdentifiers$from_param$until_param$prefix_param$set_param"
    else
        url="$oai_base?verb=ListIdentifiers&resumptionToken=$resumptiontoken"
    fi   
       
    resume_params=" -b $oai_base -d $database -t $table"
    if [ "$verbose" = "true" ] ; then
        resume_params="$resume_params -v"
    fi
    if [ ! -z "$prefix" ] ; then
        resume_params="$resume_params -p $prefix"
    fi
}

exit_on_keypress() {
    local listen="$1"
    local msg="$2"
    local alert="$3"
        
    echo -en "$msg"
    read -t 2 -n 1 key && [[ $key = "$listen" ]] && echo -e "\n$alert" && exit 1
    printf '\b%.0s' {1..100}
    printf ' %.0s' {1..100}
    printf '\b%.0s' {1..100}
}


retry() {
    local cmd="$@"
    local ret=0
    local n=1
    local max=3
    local delay=4
    local tstart=`date "+%s"`

    while true; do
        $cmd && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                sleep $delay;
                if [ "$DEBUG" == "true" ] ; then
                    log "Warning: '$cmd' failed, retrying."
                fi
            else
                log "Error: '$cmd' failed after retry $max."
                ret=1
                break
            fi
        }
    done

    if [ "$DEBUG" == "true" ] ; then
        local tend=`date "+%s"`
        local tspend=$(($tend-$tstart))
        if  [ "$tspend" -ge "$LOGSLOW" ] ; then
            log "Warning: '$cmd' slow ($tspend s)."
        fi
    fi   
    return $ret
}


show_progress() {
    local out="$1"
    if [ "$verbose" == "true" ] ; then
        echo -en "$out"
    fi
}


log() {
    local msg="$@"
    local date=`date "+%Y-%m-%d %H:%M:%S"`
    echo "$date $msg" >&2
}


rawurlencode() {
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


harvest_identifiers() {
    local url="$1"
    local identifiers_xml
    local identifiers_selected
    
    identifiers_xml="`$get "$url"`"
    if [ $? -ne 0 ] ; then return 1 ; fi    
    identifiers_selected="`echo "$identifiers_xml" | xmllint --xpath "$identifiers_xpath" - 2>/dev/null`"

    identifiers="`echo "$identifiers_selected" | perl -pe 's@</identifier[^\S\n]*>@\n@g' | perl -pe 's@<identifier[^\S\n]*>@@'`" 
    resumptiontoken="`echo "$identifiers_xml" | xmllint --xpath "$resumptiontoken_xpath" - 2>/dev/null`"
    url="$oai_base?verb=ListIdentifiers&resumptionToken=$resumptiontoken"
}


harvest_record() {
    local id="$1"
    local encoded_id=$(rawurlencode "$id")
    local sourcedata="$($get "$oai_base?verb=GetRecord$prefix_param&identifier=$encoded_id" | xmllint --xpath "$metadata_xpath" - 2>/dev/null)"

    sql="${sql} $(echo "$sourcedata" | db::create_sql $database $table $id)"
        
    show_progress "."
}


main_loop() {
    local id
    local sql=''

    while [ -n "$resumptiontoken" ] ; do

        # allow keypress 'p' to pause harvesting:
        if [ -n "$identifiers" ] ; then
            exit_on_keypress "p" "[ Press p to pauze harvest ]" "\nHarvest paused.\nContinue harvest with $prog -r '$resumptiontoken'$resume_params"
        fi

        # harvest: 
        retry harvest_identifiers "$url"
        if [ $? -ne 0 ] ; then exit 1 ; fi
        
        for id in `echo "$identifiers" ` ; do
            retry harvest_record "$id"
        done

        db::process_sql

        show_progress "\n$resumptiontoken\n"
    done

    show_progress "done\n"
}


check_software_dependencies
read_commandline_parameters "$@"
check_parameter_validity
db::prepare_database $database $table
set_harvest_parameters

main_loop
