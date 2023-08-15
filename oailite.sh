#!/bin/bash
#
# oailite.sh : a simple OAI-PMH harvester using sqlite3 or postgres
# part of https://github.com/renevoorburg/oailite 

set +H

readonly SELF=$0
readonly SELF_DIR=$(dirname "${SELF}")

source "${SELF_DIR}/lib/util.sh"
source "${SELF_DIR}/cfg/settings.sh"
if [ -f "${SELF_DIR}/cfg/settings_local.sh" ] ; then
    source "${SELF_DIR}/cfg/settings_local.sh"
fi
source "${SELF_DIR}/db/${DB_ENGINE}.sh"

readonly IDENTIFIERS_XPATH RESUMPTIONTOKEN_XPATH METADATA_XPATH CURL WGET
readonly DB_ENGINE DB_CLIENT


show_usage() {
    cat << EOF
usage: ${SELF} [OPTIONS] -b [baseURL]

A simple OAI-PMH harvester that stores retrieved records in a sqlite database or in a postgres schema. 
The harvesting process can be paused by pressing 'p'. Restart harvest by supplying a resumptiontoken using '-r'.

From https://github.com/renevoorburg/oailite 

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

EXAMPLE:
${SELF} -v -s ALBA -p dcx -f 2012-02-01T09:04:23Z -b http://services.kb.nl/mdo/oai

EOF
    exit
}


check_software_dependencies() {
    if ! hash perl 2>/dev/null; then
        util::err "Requires perl. Not found. Exiting."
        exit 1
    fi
    if hash curl 2>/dev/null; then
        GET_CMD="${CURL}"
    elif hash wget  2>/dev/null; then
        GET_CMD="${WGET}"
    else
        util::err "Requires curl or wget. Not found. Exiting."
        exit 1
    fi
    if ! hash xmllint 2>/dev/null; then
        util::err "Requires xmllint. Not found. Exiting."
        exit 1
    fi
    readonly GET_CMD
}


initiate_parameters() {
    local option
    while getopts "hvd:t:f:u:b:s:p:r:e:" option ; do
        case ${option} in
            h)  show_usage ;;
            v)  VERBOSE=true ;;
            d)  DATABASE=$(db::normalize_name "${OPTARG}") ;;
            t)  TABLE=$(db::normalize_name "${OPTARG}") ;;
            f)  FROM_PARAM="&from=${OPTARG}" ;;
            u)  UNTIL_PARAM="&until=${OPTARG}" ;;
            s)  OAI_SET="${OPTARG}"
                SET_PARAM="&set=${OPTARG}" ;;
            b)  OAI_BASE_URL="${OPTARG}" ;;
            p)  OAI_PREFIX="${OPTARG}"
                PREFIX_PARAM="&metadataPrefix=${OPTARG}" ;;
            r)  resumptiontoken="${OPTARG}" ;;
            ?)  show_usage ;;
        esac
    done

    if [ -z "${DATABASE}" ] ; then
        if [ -z "${OAI_SET}" ] ; then
            util::err "A database (-d) or OAI-PMH set(-s) must be specified. "
            show_usage
        else
            DATABASE=$(db::normalize_name "${OAI_SET}")
        fi
    fi
    if [ -z "${TABLE}" ] ; then
        if [ -z "${OAI_PREFIX}" ] ; then
            util::err "A table (-t) or OAI-PMH prefix (-p) must be specified."
            show_usage
        else
            TABLE=$(db::normalize_name "${OAI_PREFIX}")
        fi
    fi 
    if [ -z "${OAI_BASE_URL}" ] ; then
        util::err "A base url (-b) must be specified."
        show_usage
    fi

    if [ -z "${resumptiontoken}" ] ; then
        resumptiontoken='dummy'
        identifiers_url="${OAI_BASE_URL}?verb=ListIdentifiers${FROM_PARAM}${UNTIL_PARAM}${PREFIX_PARAM}${SET_PARAM}"
    else
        identifiers_url="${OAI_BASE_URL}?verb=ListIdentifiers&resumptionToken=${resumptiontoken}"
    fi   

    resume_params=" -b ${OAI_BASE_URL} -d ${DATABASE} -t ${TABLE}"
    if [ "${VERBOSE}" == "true" ] ; then
        resume_params="${resume_params} -v"
    fi
    if [ ! -z "${OAI_PREFIX}" ] ; then
        resume_params="${resume_params} -p ${OAI_PREFIX}"
    fi

    readonly DATABASE VERBOSE FROM_PARAM UNTIL_PARAM OAI_SET SET_PARAM OAI_BASE_URL OAI_PREFIX PREFIX_PARAM
}


show_progress() {
    if [ "${VERBOSE}" == "true" ] ; then
        echo -en "$1"
    fi
}


harvest_identifiers() {
    local url="$1"

    local identifiers_xml
    local identifiers_selected
    
    identifiers_xml="`${GET_CMD} "${url}"`"
    if [ $? -ne 0 ] ; then return 1 ; fi    
    identifiers_selected="`echo "${identifiers_xml}" \
        | xmllint --xpath "${IDENTIFIERS_XPATH}" - 2>/dev/null`"

    identifiers="`echo "${identifiers_selected}" \
        | perl -pe 's@</identifier[^\S\n]*>@\n@g' \
        | perl -pe 's@<identifier[^\S\n]*>@@'`" 
    resumptiontoken="`echo "${identifiers_xml}" \
        | xmllint --xpath "${RESUMPTIONTOKEN_XPATH}" - 2>/dev/null`"
    identifiers_url="${OAI_BASE_URL}?verb=ListIdentifiers&resumptionToken=${resumptiontoken}"
}


harvest_record() {
    local id="$1"

    local encoded_id=$(util::rawurlencode "${id}")
    local sourcedata="$(${GET_CMD} "${OAI_BASE_URL}?verb=GetRecord${PREFIX_PARAM}&identifier=${encoded_id}" \
        | xmllint --xpath "$METADATA_XPATH" - 2>/dev/null)"

    sql="${sql} $(echo "${sourcedata}" | db::create_sql ${DATABASE} ${TABLE} ${id})"
    show_progress "."
}


main() {
    local id
    local sql=''

    while [ -n "${resumptiontoken}" ] ; do

        # allow keypress 'p' to pause harvesting:
        if [ -n "${identifiers}" ] ; then
            util::exit_on_keypress "p" "[ Press p to pauze harvest ]" "\nHarvest paused.\nContinue harvest with ${SELF} -r '${resumptiontoken}'${resume_params}"
        fi

        # harvest: 
        harvest_identifiers "${identifiers_url}"
        if [ $? -ne 0 ] ; then exit 1 ; fi
        
        for id in `echo "${identifiers}" ` ; do
            harvest_record "${id}"
        done

        db::process_sql

        show_progress "\n${resumptiontoken}\n"
    done

    show_progress "done\n"
}


check_software_dependencies
initiate_parameters "$@"
db::prepare_database "${DATABASE}" "${TABLE}"
main
