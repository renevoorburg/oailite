# oailite
This is a simple, shell script based, OAI-PMH harvester that stores retrieved records in a sqlite database.
It is based on https://github.com/renevoorburg/oai2linerec

The database of oailite can be reused for incremental harvesting, which is a main benefit above https://github.com/renevoorburg/oai2linerec . Also, since the OAI-PMH identifiers are used as the primary keys for the database, it  won't store duplicate records, as some OAI-PMH implementations tend to deliver.

The harvesting process can be paused by pressing 'p'. Restart harvest by supplying a resumptiontoken using '-r'.

OPTIONS:
   -h           Show this message
   -v           Verbose, shows progress
   -s  set      Specify a set to be harvested
   -p  prefix   Choose which metadata format ('metadataPrefix') to harvest
   -f  date     Define a 'from' date.
   -u  date     Define an 'until' date
   -r  token    Provide a resumptiontoken to continue a harvest
   -d  database The sqlite database to use. Uses the set name for a database  when not supplied.
   -t  table    The database table to use. Uses the prefix name as a table when not supplied.
