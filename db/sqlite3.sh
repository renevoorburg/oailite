#!/bin/bash
#
# package db::
# dependencies for sqlite3
# part of https://github.com/renevoorburg/oailite 

# 'local' functions (as if):

esc() {
    echo "$1" | perl -pe "s@'@''@g"
}


# 'exported' functions (as if): 

db::normalize_name() {
    echo "$1"
}


db::create_sql() { 
    local database="$1"
    local table="$2"
    local id="$3"

    local sourcedata="$(esc "$(cat <&0)")"

    echo "${sourcedata}" > $$.tmp
    if [ ! -z "${sourcedata}" ] ; then
        ${DB_CLIENT} ${database}.db "
            replace into ${table} (id, timestamp, sourcedata) 
            values ('${id}', datetime(), readfile('$$.tmp'));"
    fi

    rm $$.tmp

}


db::process_sql() {
    sql=""
}


db::get_some_ids() {
    local database="$1"
    local table="$2"

    ${DB_CLIENT} ${database}.db "SELECT id from ${table} WHERE 1 ${RESTRICT_SQL} ORDER BY timestamp LIMIT ${offset}, ${ROWCOUNT}"
}


db::get_record_data() {
    local database="$1"
    local table="$2"
    local record_id="$3"

    ${DB_CLIENT} ${database}.db "SELECT sourcedata from ${table} WHERE id='${record_id}'"
}


db::get_number_of_records() {
    local database="$1"
    local table="$2"

    ${DB_CLIENT} ${database}.db "SELECT count(id) from ${table} WHERE 1 ${RESTRICT_SQL}"
}


db::prepare_database() {
    local database="$1"
    local table="$2"

    local create_table_sql="create table ${table} (id TEXT PRIMARY KEY, timestamp TEXT, sourcedata TEXT);"

    if ! hash sqlite3 2>/dev/null; then
        util::err "Requires sqlite3. Not found. Exiting."
        exit 1
    fi

    if [ ! -f "${database}.db" ] ; then
        ${DB_CLIENT} ${database}.db "${create_table_sql}"
        if [ $? -ne 0 ] ; then
            util::err "An error occured when creating sqlite database ${database}.db, table ${table}."
            exit 1
        fi
    else 
        echo "Using database ${database}.db."
        if [ $(${DB_CLIENT} ${database}.db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='${table}';") -eq 0 ] ; then
            ${DB_CLIENT} ${database}.db "${create_table_sql}"
        fi
    fi  
    echo "DB engine: ${DB_ENGINE}."
    echo "Storing in: ${database}.db, table ${table}."
}
