#!/bin/bash
#
# dependencies for postgres

esc() {
    echo "$1" | perl -pe "s@'@''@g"
}

normalize_name() {
    echo "$1" | sed 's@-@@g' |  tr '[:upper:]' '[:lower:]'
}

create_sql() { # uses: $id, $sourcedata, $processed, $processor
    local sourcedata_esc=$(esc "${sourcedata}")
    local processed_esc=$(esc "${processed}")

    sql="${sql}
        INSERT INTO ${database}.${table} (id, timestamp, sourcedata, processed, processor) 
        VALUES('$id', now(), '${sourcedata_esc}', '${processed_esc}', '${processor}') 
        ON CONFLICT (id) DO UPDATE 
        SET 
            timestamp=now(),
            sourcedata='${sourcedata_esc}',
            processed='${processed_esc}',
            processor='${processor}'; "
}

process_sql() {
    local res

    # why doesn't this approach process all sql??:
    #res=$(echo "${sql}" | ${DB_CLIENT} 2> /dev/null | head -n 1) 

    res=$(echo "${sql}" | ${DB_CLIENT} 2> /dev/null) 

    if [ ! "$(echo "${res}" | head -n 1)" == "INSERT 0 1" ] ; then 
        echo "Error, could not write or update records."
        exit 1
    fi
    sql=""
}


prepare_database() {
    local res
    
    res=$(echo "CREATE SCHEMA IF NOT EXISTS ${database};
        CREATE TABLE IF NOT EXISTS ${database}.${table} (
            id VARCHAR(80) PRIMARY KEY,
            timestamp TIMESTAMP WITHOUT TIME ZONE ,
            sourcedata TEXT,
            processed TEXT,
            processor VARCHAR(40)
        ); " | ${DB_CLIENT} 2> /dev/null | grep "CREATE TABLE")

    if [ ! -n "$res" ] ; then
        echo "An error occured creating table ${database}.${table} in postgres."
        exit 1
    fi

    echo "DB engine: ${DB_ENGINE}."
    echo "Storing in: ${database}.${table}."
}