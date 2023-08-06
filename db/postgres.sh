#!/bin/bash
#
# package db::
# dependencies for postgres
# part of https://github.com/renevoorburg/oailite 

# 'local' functions (as if):

esc() {
    echo "$1" | perl -pe "s@'@''@g"
}


# 'exported' functions (as if): 

db::normalize_name() {
    echo "$1" |  tr '[:upper:]' '[:lower:]' | sed 's@[^a-z0-9]@@g'
}


db::create_sql() { 
    local database="$1"
    local table="$2"
    local id="$3"

    local sourcedata="$(esc "$(cat <&0)")"
    if [ ! -z "$sourcedata" ] ; then
        echo "INSERT INTO ${database}.${table} (id, timestamp, sourcedata) 
            VALUES('$id', now(), '${sourcedata}') 
            ON CONFLICT (id) DO UPDATE 
            SET timestamp=now(), sourcedata='${sourcedata}';"
    fi
}


db::process_sql() {
    local res
    if [ ! -z "$sql" ] ; then
        # why doesn't this approach process all sql??:
        #res=$(echo "${sql}" | ${DB_CLIENT} 2> /dev/null | head -n 1) 

        res=$(echo "${sql}" | ${DB_CLIENT} 2> /dev/null) 

        if [ ! "$(echo "${res}" | head -n 1)" == "INSERT 0 1" ] ; then 
            util::err "Error, could not write or update records."
            exit 1
        fi
        sql=""
    fi
}


db::get_some_ids() {
    local database="$1"
    local table="$2"

    echo "\pset pager off
        SELECT id from ${database}.${table} WHERE true ${RESTRICT_SQL} ORDER BY timestamp OFFSET ${offset} LIMIT ${ROWCOUNT} ;" \
        | ${DB_CLIENT} -t -A -q 2> /dev/null
}


db::get_record_data() {
    local database="$1"
    local table="$2"
    local record_id="$3"

    echo "\pset pager off
        SELECT sourcedata from ${database}.${table} WHERE id='${record_id}' ;" \
        | ${DB_CLIENT} -t -A -q 2> /dev/null
}


db::get_number_of_records() {
    local database="$1"
    local table="$2"

    echo "\pset pager off
        SELECT count(id) from ${database}.${table} WHERE true ${RESTRICT_SQL} ;" \
        | ${DB_CLIENT} -t -A -q 2> /dev/null
}


db::prepare_database() {
    local database="$1"
    local table="$2"

    local res
    res=$(echo "CREATE SCHEMA IF NOT EXISTS ${database};
        CREATE TABLE IF NOT EXISTS ${database}.${table} (
            id VARCHAR(80) PRIMARY KEY,
            timestamp TIMESTAMP WITHOUT TIME ZONE ,
            sourcedata TEXT
        ); " | ${DB_CLIENT} 2> /dev/null | grep "CREATE TABLE")

    if [ ! -n "$res" ] ; then
        util::err "An error occured creating table ${database}.${table} in postgres."
        exit 1
    fi
    echo "DB engine: ${DB_ENGINE}."
    echo "Storing in: ${database}.${table}."
}
