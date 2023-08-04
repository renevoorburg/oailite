#!/bin/bash

# NOTE: will be overridden by optional settings_local.sh

DB_ENGINE="sqlite3" 
DB_CLIENT="sqlite3 -batch"

# DB_ENGINE="postgres" 
# DB_CLIENT="docker run -e PGPASSWORD=mysecretpassword --interactive --rm --link some-postgres:postgres postgres psql -h postgres -U postgres"
# ^^^^^^^^^ - this docker container was created with
# docker run --name some-postgres -v /Users/rene/data/pgdata:/var/lib/postgresql/data -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword -d postgres 

