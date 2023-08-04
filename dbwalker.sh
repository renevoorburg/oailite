#!/bin/bash

# dbwalker.sh
# part of https://github.com/renevoorburg/oailite

set +H

prog=$0
script_dir=$(dirname "$prog")

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

read_commandline_parameters() {
    prog=$0
    script_dir=$(dirname "$prog")
    while getopts "hd:t:f:u:p:s:d:e:" option ; do
        case $option in
            h)  usage
                ;;
            s)  source_db=$(db::normalize_name "$OPTARG")
                ;;
            t)  source_table=$(db::normalize_name "$OPTARG")
                ;;
            f)  from="$OPTARG"
                ;;
            u)  until="$OPTARG"
                ;;
            p)  processor="$script_dir/$OPTARG"
                ;;
            d)  dest_db=$(db::normalize_name "$OPTARG")
                ;;
            e)  dest_table=$(db::normalize_name "$OPTARG")
                ;;
            ?)  usage
                ;;
        esac
    done
    shift "$(($OPTIND -1))"
}

usage() {
    cat << EOF

usage: $prog [OPTIONS] -s [source db] -t [source table]

This is a helper script for processing data stored in an sqlite source_db, as retrieved by oailite.sh. 
It returns the selected captured payload for further processing.

OPTIONS:
-h              Show this message
-s source_db    Source database or schema.  
-t source_table Source table.
-p  filter      Use 'filter' to process returned payload in a pipe.
-d  dest_db     Destination database of schema. Replaces stdout.
-e  dest_table  Destination table.
-f  datetime    Return only payload with given 'from' datetime.
-u  datetime    Return only payload with given 'until' datetime.

             
EXAMPLES:

Return all payload from GGC-THES.db, table mdoall:
$prog -s GGC-THES -t mdoall

Return selected payload and process it with ./nta2schema.sh:
$prog -s GGC-THES -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x"

Return selected payload, process it with ./nta2schema.sh and store it in OUT.db:
$prog -s GGC-THES -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x" -d outd -e rdf

EOF
    exit
}

set_valid_initial_parameters() {
    if [ -z "$source_db" ] ; then
        echo "A source source_db (-s) must be specified. "
        usage
    fi
    # if [ ! -f "${source_db}.db" ] ; then
    #     echo "Database $source_db not found."
    #     exit
    # fi
    if [ -z "$source_table" ] ; then
        echo "A table (-t) in the source source_db must be specified."
        usage
    fi 
    # if [ `$DB_CLIENT ${source_db}.db "SELECT count(*) from sqlite_master WHERE type='table' AND name='$table';"` -eq 0 ] ; then
    #     echo "Table $table does not exist."
    #     exit 1
    # fi    
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


    writer="cat" 
    if [ ! -z "$dest_db" ] ; then
        writer="db::create_sql $dest_db $dest_table"
        db::prepare_database $dest_db $dest_table
    fi

    rowcount=10000
    offset=0
    counter=0
    numrecs=$(db::get_number_of_records $source_db $source_table)
}

# db::create_record() {
#     sourcedata=`cat <&0`
#     if [ ! -z "$piped_data" ] ; then
#         $DB_CLIENT $dest_db "pragma busy_timeout=20000; 
#             REPLACE INTO $dest_table (id, timestamp, sourcedata) 
#             VALUES ('$record_id', datetime(), '$(echo "$piped_data" | perl -pe "s@'@''@g")') ;" > /dev/null
#     fi
# }


process_record() {
    record_id=$1
    if [ "$writer" == "cat" ] ; then
        db::get_record_data $source_db $source_table | $processor
    else
        sql="${sql} $(db::get_record_data $source_db $source_table | $processor | db::create_sql $dest_db $dest_table $record_id)"
    fi
}

read_commandline_parameters "$@"
set_valid_initial_parameters

sql=""
until [ $counter -ge $numrecs ] ; do
    while read id ; do
        process_record $id
       ((counter++))
    done <<< "$(db::get_some_ids $source_db $source_table)"
    db::process_sql
    offset=$((offset+rowcount))
done
