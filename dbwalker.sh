#!/bin/bash

# dbwalker.sh
# part of https://github.com/renevoorburg/oailite
# 2023-05-21

set +H

export DEST_DB
export DEST_TABLE
export RECORD_ID

read_commandline_parameters()
{
    PROG=$0
    SCRIPT_DIR=$(dirname "$PROG")
    while getopts "hd:t:f:u:p:s:" option ; do
        case $option in
            h)  usage
                ;;
            s)  SOURCE_DB="$OPTARG"
                ;;
            t)  TABLE="$OPTARG"
                DEST_TABLE="$TABLE"
                ;;
            f)  FROM="$OPTARG"
                ;;
            u)  UNTIL="$OPTARG"
                ;;
            p)  FILTER="$OPTARG"
                ;;
            d)  DEST_DB=`pwd`"/$OPTARG"
                ;;
            ?)  usage
                ;;
        esac
    done
    shift "$(($OPTIND -1))"
}

usage()
{
    cat << EOF

usage: $PROG [OPTIONS] -s [source db] -t [source table]

This is a helper script for processing data stored in an sqlite database, as retrieved by oailite.sh. 
It returns the selected captured payload for further processing.

OPTIONS:
-h           Show this message
-f  datetime Return only payload with given 'from' datetime.
-u  datetime Return only payload with given 'until' datetime.
-p  filter   Use 'filter' to process returned payload in a pipe.
-d  database Do not print to stdout but store results in 'database'. 
             This will call helper script 'dbstore.sh'.
             Note that the same table as in the source database is used.
             
EXAMPLES:

Return all payload from GGC-THES.db, table mdoall:
$PROG -s GGC-THES.db -t mdoall

Return selected payload and process it with ./nta2schema.sh:
$PROG -s GGC-THES.db -t mdoall -f "2023-05-15 17:56:03" -p ./nta2schema.sh

Return selected payload, process it with ./nta2schema.sh and store it in OUT.db:
$PROG -s GGC-THES.db -t mdoall -f "2023-05-15 17:56:03" -p ./nta2schema.sh -d OUT.db

EOF
    exit
}

check_software_dependencies()
{
    if ! hash sqlite3 2>/dev/null; then
        echo "Requires sqlite3. Not found. Exiting."
        exit 1
    fi
}

set_valid_initial_parameters()
{
    if [ -z "$SOURCE_DB" ] ; then
        echo "A source database (-s) must be specified. "
        usage
    fi
    if [ ! -f "$SOURCE_DB" ] ; then
        echo "Database $SOURCE_DB not found."
        exit
    fi
    if [ -z "$TABLE" ] ; then
        echo "A table (-t) in the source database must be specified."
        usage
    fi 
    if [ `sqlite3 -batch $SOURCE_DB "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$TABLE';"` -eq 0 ] ; then
        echo "Table $TABLE does not exist."
        exit 1
    fi
    if [ -z "$DEST_DB" ] ; then
        PROCESSOR="cat" 
    else
        PROCESSOR="$SCRIPT_DIR/dbstore.sh"
    fi
    if [ -z "$FILTER" ] ; then
        FILTER="cat" 
    fi

    RESTRICT_SQL=''
    if [  ! -z "$FROM" ] ; then
        RESTRICT_SQL="$RESTRICT_SQL AND timestamp >= '$FROM'"
    fi 
    if [ ! -z "$UNTIL" ] ; then 
        RESTRICT_SQL="$RESTRICT_SQL AND timestamp <= '$UNTIL'"
    fi

    ROWCOUNT=10000
    OFFSET=0
    COUNTER=0
    NUMRECS=`sqlite3 -batch $SOURCE_DB "SELECT count(id) FROM $TABLE WHERE 1 $RESTRICT_SQL"`
}

prepare_destination_database()
{
    if [ ! -z "$DEST_DB" ] ; then
        if [ ! -f "$DEST_DB" ] ; then
            sqlite3 -batch $DEST_DB "create table $DEST_TABLE (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"
            if [ $? -ne 0 ] ; then
                echo "An error occured when creating destination database $DEST_DB, table $DEST_TABLE."
                exit 1
            else
                if [ `sqlite3 -batch $DEST_DB "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$DEST_TABLE';"` -eq 0 ] ; then
                    sqlite3 -batch $DEST_DB "create table $DEST_TABLE (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"
                fi
            fi
        fi
    fi
}

process_record()
{
    RECORD_ID=$1
    echo "`sqlite3 -batch $SOURCE_DB "SELECT sourcedata FROM $TABLE WHERE id='$RECORD_ID'"`" | "$FILTER" | "$PROCESSOR"
}

read_commandline_parameters "$@"
check_software_dependencies
set_valid_initial_parameters
prepare_destination_database

until [ $COUNTER -ge $NUMRECS ] ; do
    while read id ; do
        process_record $id
       ((COUNTER++))
    done <<< "$(sqlite3 -batch $SOURCE_DB "SELECT id FROM $TABLE WHERE 1 $RESTRICT_SQL ORDER BY timestamp LIMIT $OFFSET, $ROWCOUNT")"
    OFFSET=$((OFFSET+ROWCOUNT))
done
