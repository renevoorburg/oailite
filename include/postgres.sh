#!/bin/bash
#
# dependencies for postgres

DB_CLIENT="docker run -e PGPASSWORD=mysecretpassword --interactive --rm --link some-postgres:postgres postgres psql -h postgres -U postgres"
# this docker container was created with
# docker run --name some-postgres -v /Users/rene/data/pgdata:/var/lib/postgresql/data -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword -d postgres 


esc() {
    echo "$1" | perl -pe "s@'@''@g"
}

normalize_name() {
    echo "$1" | sed 's@-@@g' |  tr '[:upper:]' '[:lower:]'
}

create_sql() { # uses: $id, $sourcedata, $processed, $processor
    sql="${sql}
        INSERT INTO ${database}.${table} (id, timestamp, sourcedata, processed, processor)
        VALUES('$id', now(), '$(esc "${sourcedata}")', '$(esc "${processed}")', '${processor}') 
        ON CONFLICT (id) 
        DO 
        UPDATE SET 
            timestamp=now(), 
            sourcedata='$(esc "${sourcedata}")',
            processed='$(esc "${processed}")',
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