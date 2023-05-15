# oailite
This is a simple, shell script based, OAI-PMH harvester that stores retrieved records in a sqlite database.
It is based on https://github.com/renevoorburg/oai2linerec

The database of oailite can be reused for incremental harvesting, which is a main benefit above https://github.com/renevoorburg/oai2linerec . Also, since the OAI-PMH identifiers are used as the primary keys for the database, it  won't store duplicate records, as some OAI-PMH implementations tend to deliver.

The harvesting process can be paused by pressing 'p'. Restart harvest by supplying a resumptiontoken using '-r'.
