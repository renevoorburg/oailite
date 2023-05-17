#!/bin/bash
set +H

## declare global vars:
CURL='curl -fs'
WGET='wget -q -t 3 -O -'
PROG=$0
IDENTIFIERS_XP="//*[local-name()='header'][not(contains(@status, 'deleted'))]/*[local-name()='identifier']"
RESUMPTION_XP="//*[local-name()='resumptionToken']/text()"
METADATA_XP="//*[local-name()='metadata']"

RESUMPTIONTOKEN=''

GET=''


usage()
{
    cat << EOF
usage: $PROG [OPTIONS] -b [baseURL]

This is a simple OAI-PMH harvester that stores retrieved records in a sqlite database. 
The harvesting process can be paused by pressing 'p'. Restart harvest by supplying a resumptiontoken using '-r'.

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
$PROG -v -s ALBA -p dcx -f 2012-02-01T09:04:23Z -b http://services.kb.nl/mdo/oai

EOF
    exit
}


check_software_dependencies()
{
    # check for required tools:
    if ! hash perl 2>/dev/null; then
        echo "Requires perl. Not found. Exiting."
        exit 1
    fi
    if hash curl 2>/dev/null; then
        GET="$CURL"
    elif hash wget  2>/dev/null; then
        GET="$WGET"
    else
        echo "Requires curl or wget. Not found. Exiting."
        exit 1
    fi
    if ! hash xmllint 2>/dev/null; then
        echo "Requires xmllint. Not found. Exiting."
        exit 1
    fi
    if ! hash sqlite3 2>/dev/null; then
        echo "Requires sqlite3. Not found. Exiting."
        exit 1
    fi
}


read_commandline_parameters()
{
    local option
    
    while getopts "hvd:t:f:u:b:s:p:r:" option ; do
        case $option in
            h)  usage
                ;;
            v)  VERBOSE=true
                ;;
            d)  DB="$OPTARG"
                ;;
            t)  TABLE="$OPTARG"
                ;;
            f)  FROMPARAM="&from=$OPTARG"
                ;;
            u)  UNTILPARAM="&until=$OPTARG"
                ;;
            s)  SET="$OPTARG"
                SETPARAM="&set=$OPTARG"
                ;;
            b)  BASE="$OPTARG"
                ;;
            p)  PREFIX="$OPTARG"
                PREFIXPARAM="&metadataPrefix=$OPTARG"
                ;;
            r)  RESUMPTIONTOKEN="$OPTARG"
                ;;
            ?)  usage
                ;;
        esac
    done
}


check_parameter_validity()
{
    if [ -z "$DB" ] ; then
        if [ -z "$SET" ] ; then
            echo "A database (-d) or set (-s) must be specified. "
            usage
        else
            DB="$SET.db"
        fi
    fi
    if [ -z "$TABLE" ] ; then
        if [ -z "$PREFIX" ] ; then
            echo "A table (-t) of prefix (-p) must be specified."
            usage
        else
            TABLE="$PREFIX"
        fi
    fi 
    if [ -z "$BASE" ] ; then
        echo "A base url (-b) must be specified."
        usage
    fi
}


set_parameters()
{
    if [ -z "$RESUMPTIONTOKEN" ] ; then
        RESUMPTIONTOKEN='dummy'
        URL="$BASE?verb=ListIdentifiers$FROMPARAM$UNTILPARAM$PREFIXPARAM$SETPARAM"
    else
        URL="$BASE?verb=ListIdentifiers&resumptionToken=$RESUMPTIONTOKEN"
    fi   
       
    RESUMEPARAMS=" -b $BASE -d $DB -t $TABLE"
    if [ "$VERBOSE" = "true" ] ; then
        RESUMEPARAMS="$RESUMEPARAMS -v"
    fi
    if [ ! -z "$PREFIX" ] ; then
        RESUMEPARAMS="$RESUMEPARAMS -p $PREFIX"
    fi
}


prepare_database()
{
    if [ ! -f "$DB" ] ; then
        sqlite3 -batch $DB "create table $TABLE (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"
        if [ $? -ne 0 ] ; then
            echo "An error occured when creating sqlite database $DB, table $TABLE."
            exit 1
        else 
            echo "Created database $DB."
            echo "Created table $TABLE."
        fi
    else 
        echo "Using database $DB."
        if [ `sqlite3 -batch $DB "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$TABLE';"` -eq 0 ] ; then
            sqlite3 -batch $DB "create table $TABLE (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"
            echo "Created table $TABLE."
        else 
            echo "Using table $TABLE."
        fi
    fi  
}


exit_on_keypress()
{
    local listen="$1"
    local msg="$2"
    local alert="$3"
        
    echo -en "$msg"
    read -t 2 -n 1 key && [[ $key = "$listen" ]] && echo -e "\n$alert" && exit 1
    printf '\b%.0s' {1..100}
    printf ' %.0s' {1..100}
    printf '\b%.0s' {1..100}
}


retry() 
{
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


show_progress()
{
    local out="$1"
    if [ "$VERBOSE" == "true" ] ; then
        echo -en "$out"
    fi
}


log()
{
    local msg="$@"
    local date=`date "+%Y-%m-%d %H:%M:%S"`
    echo "$date $msg" >&2
}


rawurlencode() 
{
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


harvest_identifiers()
{
    local url="$1"
    local identifiers_xml
    local identifiers_selected
    
    identifiers_xml="`$GET "$url"`"
    if [ $? -ne 0 ] ; then return 1 ; fi    
    identifiers_selected="`echo "$identifiers_xml" | xmllint --xpath "$IDENTIFIERS_XP" - 2>/dev/null`"

    IDENTIFIERS="`echo "$identifiers_selected" | perl -pe 's@</identifier[^\S\n]*>@\n@g' | perl -pe 's@<identifier[^\S\n]*>@@'`" 
    RESUMPTIONTOKEN="`echo "$identifiers_xml" | xmllint --xpath "$RESUMPTION_XP" - 2>/dev/null`"
    URL="$BASE?verb=ListIdentifiers&resumptionToken=$RESUMPTIONTOKEN"
}


harvest_record()
{
    local id=$(rawurlencode "$1")
    local metadata
    local payload
    
    metadata="`$GET "$BASE?verb=GetRecord$PREFIXPARAM&identifier=$id" | xmllint --xpath "//*[local-name()='metadata']" - 2>/dev/null`"
    if [ $? -ne 0 ] ; then return 1 ; fi

    payload=`echo "$metadata" | perl -pe "s@'@''@g"` 
    sqlite3 -batch $DB  "replace into $TABLE (id, timestamp, sourcedata) values ('$1', datetime(), '$(echo "$metadata" | perl -pe "s@'@''@g")');"
    if [ $? -ne 0 ] ; then return 1 ; fi
        
    show_progress "."
}


main_loop()
{
    local id

     while [ -n "$RESUMPTIONTOKEN" ] ; do

        # allow keypress 'p' to pause harvesting:
        if [ -n "$IDENTIFIERS" ] ; then
            exit_on_keypress "p" "[ Press p to pauze harvest ]" "\nHarvest paused.\nContinue harvest with $PROG -r '$RESUMPTIONTOKEN'$RESUMEPARAMS"
        fi

        # harvest: 
        retry harvest_identifiers "$URL"
        if [ $? -ne 0 ] ; then exit 1 ; fi
        
        for id in `echo "$IDENTIFIERS" ` ; do
            retry harvest_record "$id"
        done
        show_progress "\n$RESUMPTIONTOKEN\n"
    done

    show_progress "done\n"
}


check_software_dependencies
read_commandline_parameters "$@"
check_parameter_validity
set_parameters
prepare_database

main_loop

exit
