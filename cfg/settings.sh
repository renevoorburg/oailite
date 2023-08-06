#!/bin/bash
#
# configuration settings
# part of https://github.com/renevoorburg/oailite 

# NOTE: will be overridden by optional settings_local.sh

IDENTIFIERS_XPATH="//*[local-name()='header'][not(contains(@status, 'deleted'))]/*[local-name()='identifier']"
RESUMPTIONTOKEN_XPATH="//*[local-name()='resumptionToken']/text()"
METADATA_XPATH="//*[local-name()='metadata']"

CURL='curl -fs'
WGET='wget -q -t 3 -O -'

DB_ENGINE="sqlite3" 
DB_CLIENT="sqlite3 -batch"

# readonly DB_ENGINE="postgres" 
# readonly DB_CLIENT="docker run -e PGPASSWORD=mysecretpassword --interactive --rm --link some-postgres:postgres postgres psql -h postgres -U postgres"
# ^^^^^^^^^ - this docker container was created with
# docker run --name some-postgres -v /Users/rene/data/pgdata:/var/lib/postgresql/data -p 5432:5432 -e POSTGRES_PASSWORD=mysecretpassword -d postgres 
