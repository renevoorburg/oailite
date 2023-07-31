#!/bin/bash

# dbwalker.sh
# part of https://github.com/renevoorburg/oailite

set +H

read_commandline_parameters()
{
    prog=$0
    script_dir=$(dirname "$prog")
    while getopts "hd:t:f:u:p:s:" option ; do
        case $option in
            h)  usage
                ;;
            s)  source_db="$OPTARG"
                ;;
            t)  table="$OPTARG"
                dest_table="$table"
                ;;
            f)  from="$OPTARG"
                ;;
            u)  until="$OPTARG"
                ;;
            p)  processor="$script_dir/$OPTARG"
                ;;
            d)  dest_db="$OPTARG"
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

usage: $prog [OPTIONS] -s [source db] -t [source table]

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
$prog -s GGC-THES.db -t mdoall

Return selected payload and process it with ./nta2schema.sh:
$prog -s GGC-THES.db -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x"

Return selected payload, process it with ./nta2schema.sh and store it in OUT.db:
$prog -s GGC-THES.db -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x" -d OUT.db

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
    if [ -z "$source_db" ] ; then
        echo "A source database (-s) must be specified. "
        usage
    fi
    if [ ! -f "$source_db" ] ; then
        echo "Database $source_db not found."
        exit
    fi
    if [ -z "$table" ] ; then
        echo "A table (-t) in the source database must be specified."
        usage
    fi 
    if [ `sqlite3 -batch $source_db "SELECT count(*) from sqlite_master WHERE type='table' AND name='$table';"` -eq 0 ] ; then
        echo "Table $table does not exist."
        exit 1
    fi    
    if [ -z "$processor" ] ; then
        processor="cat" 
    fi

    restrict_sql=''
    if [ ! -z "$from" ] ; then
        restrict_sql="$restrict_sql AND timestamp >= '$from'"
    fi 
    if [ ! -z "$until" ] ; then 
        restrict_sql="$restrict_sql AND timestamp <= '$until'"
    fi

    rowcount=10000
    offset=0
    counter=0
    numrecs=`sqlite3 -batch $source_db "SELECT count(id) from $table WHERE 1 $restrict_sql"`
}

prepare_destination_database()
{
    writer="cat" 
    if [ ! -z "$dest_db" ] ; then
        if [ ! -f "$dest_db" ] ; then
            writer="create_record"
            sqlite3 -batch $dest_db "create table $dest_table (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"
            if [ $? -ne 0 ] ; then
                echo "An error occured when creating destination database $dest_db, table $dest_table."
                exit 1
            else
                if [ `sqlite3 -batch $dest_db "SELECT count(*) from sqlite_master WHERE type='table' AND name='$dest_table';"` -eq 0 ] ; then
                    sqlite3 -batch $dest_db "create table $dest_table (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"
                fi
            fi
        elif  [ "$dest_db" = "$source_db" ] ; then
            writer="update_record"
            # make sure we have columns for the processed data:
            sqlite3 -batch $dest_db "alter table $dest_table add column processed TEXT;" 2> /dev/null
            sqlite3 -batch $dest_db "alter table $dest_table add column processor TEXT;" 2> /dev/null
        else
            writer="create_record"
        fi
    fi
}

create_record()
{
    piped_data=`cat <&0`
    if [ ! -z "$piped_data" ] ; then
        sqlite3 -batch $dest_db "pragma busy_timeout=20000; 
            REPLACE INTO $dest_table (id, timestamp, sourcedata) 
            VALUES ('$record_id', datetime(), '$(echo "$piped_data" | perl -pe "s@'@''@g")') ;" > /dev/null
    fi
}

update_record() 
{
    piped_data=`cat <&0`
    if [ ! -z "$piped_data" ] ; then
        sqlite3 -batch $dest_db "pragma busy_timeout=20000; 
            UPDATE $dest_table 
            SET timestamp = datetime(), 
                processed = '$(echo "$piped_data" | perl -pe "s@'@''@g")', 
                processor = '${processor}' 
            WHERE id = '$record_id' ;" > /dev/null
    fi
}

process_record()
{
    record_id=$1
    echo "`sqlite3 -batch $source_db "SELECT sourcedata from $table WHERE id='$record_id'"`" | $processor | "$writer"
}

read_commandline_parameters "$@"
check_software_dependencies
set_valid_initial_parameters
prepare_destination_database

until [ $counter -ge $numrecs ] ; do
    while read id ; do
        process_record $id
       ((counter++))
    done <<< "$(sqlite3 -batch $source_db "SELECT id from $table WHERE 1 $restrict_sql ORDER BY timestamp LIMIT $offset, $rowcount")"
    offset=$((offset+rowcount))
done
