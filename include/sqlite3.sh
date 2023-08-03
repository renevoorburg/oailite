#!/bin/bash

esc() {
    echo "$1" | perl -pe "s@'@''@g"
}

normalize_name() {
    echo "$1"
}

create_sql() { # uses: $id, $sourcedata, $processed, $processor
    $DB_CLIENT ${database}.db "
        replace into ${table} (id, timestamp, sourcedata, processed, processor) 
        values ('${id}', datetime(), '$(esc "${sourcedata}")', '$(esc "${processed}")', '${processor}');"
    return $?
}


process_sql() {
    sql=""
}

prepare_database() {
    local create_table_sql="create table $table (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT, processed TEXT, processor TEXT);"

    if ! hash sqlite3 2>/dev/null; then
        echo "Requires sqlite3. Not found. Exiting."
        exit 1
    fi

    if [ ! -f "${database}.db" ] ; then
        $DB_CLIENT ${database}.db "$create_table_sql"
        if [ $? -ne 0 ] ; then
            echo "An error occured when creating sqlite database ${database}.db, table $table."
            exit 1
        else 
            echo "Created database ${database}.db."
            echo "Created table $table."
        fi
    else 
        echo "Using database ${database}.db."
        if [ `$DB_CLIENT ${database}.db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$table';"` -eq 0 ] ; then
            $DB_CLIENT ${database}.db "$create_table_sql"
            echo "Created table $table."
        else 
            echo "Using table $table."
        fi
    fi  
}