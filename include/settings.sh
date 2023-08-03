#!/bin/bash

# NOTE: will be overridden by optional settings_local.sh

DB_ENGINE="sqlite3" 
DB_CLIENT="sqlite3 -batch"

#DB_ENGINE="postgres" 
#DB_CLIENT="docker run -e PGPASSWORD=mysecretpassword --interactive --rm --link some-postgres:postgres postgres psql -h postgres -U postgres"

