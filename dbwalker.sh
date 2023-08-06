#!/bin/bash

# dbwalker.sh : a companion script to oailite.sh
# part of https://github.com/renevoorburg/oailite

set +H

readonly SELF=$0
readonly SELF_DIR=$(dirname "${SELF}")

source "${SELF_DIR}/cfg/settings.sh"
if [ -f "${SELF_DIR}/cfg/settings_local.sh" ] ; then
    source "${SELF_DIR}/cfg/settings_local.sh"
fi
source "${SELF_DIR}/db/${DB_ENGINE}.sh"

readonly DB_ENGINE DB_CLIENT


show_usage() {
    cat << EOF
usage: $SELF [OPTIONS] -s [SOURCE_DB] -t [SOURCE_TABLE]

A helper script processing data stored by oailite.sh, in either a sqlite3 or postgres database. 
All (or selected) data can be simple returned, process by an external filter, and / or stored in a database.

From https://github.com/renevoorburg/oailite 

OPTIONS:
-h                    Show this message
-s SOURCE_DB          Source database or schema.  
-t SOURCE_TABLE       Source table.
-p filter             Filter for proecessing data field in a pipe.
-d destination_db     Destination database of schema. Replaces stdout.
-e destination_table  Destination table.
-f from               Return only payload with given 'from' datetime.
-u until              Return only payload with given 'until' datetime.

Choose to use either sqlite3 or postgres in "${SELF_DIR}/cfg/settings.sh".
             
EXAMPLES:

Return data from GGC-THES.db, table mdoall:
$SELF -s GGC-THES -t mdoall

Return selected data and process it with ./nta2schema.sh:
$SELF -s GGC-THES -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x"

Store processed data in OUT.db, table 'rdf':
$SELF -s GGC-THES -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x" -d OUT -e rdf

EOF
    exit
}


initiate_parameters() {
    local option
    local from
    while getopts "hd:t:f:u:p:s:d:e:" option ; do
        case ${option} in
            h)  show_usage ;;
            s)  SOURCE_DB=$(db::normalize_name "${OPTARG}") ;;
            t)  SOURCE_TABLE=$(db::normalize_name "${OPTARG}") ;;
            f)  from="${OPTARG}" ;;
            u)  until="${OPTARG}" ;;
            p)  PROCESSOR="${SELF_DIR}/${OPTARG}" ;;
            d)  DEST_DB=$(db::normalize_name "${OPTARG}") ;;
            e)  DEST_TABLE=$(db::normalize_name "${OPTARG}") ;;
        esac
    done

    if [ -z "${SOURCE_DB}" ] ; then
        echo "A source database(-s) must be specified. "
        show_usage
    fi
    if [ -z "${SOURCE_TABLE}" ] ; then
        echo "A table (-t) in the source database must be specified."
        show_usage
    fi  
    if [ -z "${PROCESSOR}" ] ; then
        PROCESSOR="cat" 
    fi

    RESTRICT_SQL=''
    if [ ! -z "${from}" ] ; then
        RESTRICT_SQL="${RESTRICT_SQL} AND timestamp >= '${from}'"
    fi 
    if [ ! -z "${until}" ] ; then 
        RESTRICT_SQL="${RESTRICT_SQL} AND timestamp <= '${until}'"
    fi

    WRITER="cat" 
    if [ ! -z "${DEST_DB}" ] ; then
        WRITER="db::create_sql ${DEST_DB} ${DEST_TABLE}"
        db::prepare_database "${DEST_DB}" "${DEST_TABLE}"
    fi

    sql=""
    offset=0
    counter=0

    readonly ROWCOUNT=10000
    readonly NUMRECS=$(db::get_number_of_records "${SOURCE_DB}" "${SOURCE_TABLE}")
    readonly SOURCE_DB SOURCE_TABLE RESTRICT_SQL PROCESSOR DEST_DB DEST_TABLE WRITER
}


process_record() {
    local record_id="$1"
    if [ "${WRITER}" == "cat" ] ; then
        db::get_record_data "${SOURCE_DB}" "${SOURCE_TABLE}" "${record_id}" | ${PROCESSOR}
    else
        sql="${sql} $(db::get_record_data ${SOURCE_DB} ${SOURCE_TABLE} ${record_id} | ${PROCESSOR} | db::create_sql ${DEST_DB} ${DEST_TABLE} ${record_id})"
    fi
}

main() {
    until [ ${counter} -ge ${NUMRECS} ] ; do
        while read id ; do
            process_record "$id"
        ((counter++))
        done <<< "$(db::get_some_ids "${SOURCE_DB}" "${SOURCE_TABLE}")"
        db::process_sql
        offset=$((offset+ROWCOUNT))
    done

}

initiate_parameters "$@"
main

