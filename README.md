# oailite.sh
This is a simple, shell script based, OAI-PMH harvester that stores retrieved records in an sqlite database. It is based on [renevoorburg/oai2linerec](https://github.com/renevoorburg/oai2linerec)

The database of `oailite.sh` can be reused for incremental harvesting, which is a main benefit above [renevoorburg/oai2linerec](https://github.com/renevoorburg/oai2linerec) . Also, since the OAI-PMH identifiers are used as the primary keys for the database, it  won't store duplicate records, as some OAI-PMH implementations tend to deliver.
	
	usage: oailite.sh [OPTIONS] -b [baseURL]
	
	This is a simple OAI-PMH harvester that stores retrieved records in a sqlite database. 
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
	
	EXAMPLE:
	./oailite.sh -v -s ALBA -p dcx -f 2012-02-01T09:04:23Z -b http://services.kb.nl/mdo/oai

# dbwalker.sh

This is a helper script for viewing and processing data retrieved by `oailite.sh`.

	usage: ./dbwalker.sh [OPTIONS] -s [source db] -t [source table]
	
	This is a helper script for processing data stored in an sqlite database, as retrieved by oailite.sh. 
	It returns the selected captured payload for further processing.
	
	OPTIONS:
	-h           Show this message
	-f  datetime Return only payload with given 'from' datetime.
	-u  datetime Return only payload with given 'until' datetime.
	-p  filter   Use 'filter' to process returned payload in a pipe.
	-d  database Do not print to stdout but store results in 'database'. 
	             This will call helper script 'dbstore.sh'.
	             Note that the same table as in the source database is used.
	             
	EXAMPLES:
	
	Return all payload from GGC-THES.db, table mdoall:
	./dbwalker.sh -s GGC-THES.db -t mdoall
	
	Return selected payload and process it with ./nta2schema.sh:
	./dbwalker.sh -s GGC-THES.db -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x"
	
	Return selected payload, process it with ./nta2schema.sh and store it in OUT.db:
	./dbwalker.sh -s GGC-THES.db -t mdoall -f "2023-05-15 17:56:03" -p "nta2schema.sh -x" -d OUT.db

