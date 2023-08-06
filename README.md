# oailite.sh
A hell script based, OAI-PMH harvester that stores retrieved records in an sqlite or postgres database. It is based on [renevoorburg/oai2linerec](https://github.com/renevoorburg/oai2linerec)

The database of `oailite.sh` can be reused for incremental harvesting, which is a main benefit above [renevoorburg/oai2linerec](https://github.com/renevoorburg/oai2linerec). Further, since the OAI-PMH identifiers are used as the primary keys for the database, it  won't store duplicate records, as some OAI-PMH implementations tend to deliver.
	

	usage: oailite.sh  [OPTIONS] -b [baseURL]
	
	The harvesting process can be paused by pressing 'p'. Restart harvest by supplying a resumptiontoken using '-r'.
	
	OPTIONS:
	-h           Show this message
	-v           Verbose, shows progress
	-s  set      Specify an OAI-PMH set to be harvested
	-p  prefix   Choose which metadata format ('metadataPrefix') to harvest
	-f  from     Define a 'from' date  for the OAI-PMH harvest..
	-u  until    Define an 'until' date for the OAI-PMH harvest.
	-r  token    A resumptiontoken to continue a paused harvest
	-d  database The sqlite datbase / postgres schema to use. Defaults to the OAI-PMH set.
	-t  table    Table for the output. Defaults to the OAI-PMH prefix.
	
	Choose to use either sqlite3 or postgres in "${SELF_DIR}/cfg/settings.sh".

## example

	oailite.sh  -v -s ALBA -p dcx -f 2012-02-01 -b http://services.kb.nl/mdo/oai
  
# dbwalker.sh

A helper script processing data stored by `oailite.sh`, in either a sqlite3 or postgres database. 
All (or selected) data can be simple returned, process by an external filter, and / or stored in a database.

	usage: $SELF [OPTIONS] -s [SOURCE_DB] -t [SOURCE_TABLE]
	
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
             
## examples

Return data from `GGC-THES.db`, table `mdoall`:

	dbwalker.sh -s GGC-THES -t mdoall

Return selected data and process it with filter `./nta2schema.sh` (from [https://github.com/renevoorburg/thes2rdf]() ):

	dbwalker.sh -s GGC-THES -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x"

Store processed data in `OUT.db`, table `rdf`:

	dbwalker.sh -s GGC-THES -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x" -d OUT -e rdf

