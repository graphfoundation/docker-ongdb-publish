#!/bin/bash -eu

cmd="$1"

function running_as_root
{
    test "$(id -u)" = "0"
}

function secure_mode_enabled
{
    test "${SECURE_FILE_PERMISSIONS:=no}" = "yes"
}

function containsElement
{
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function is_readable
{
    # this code is fairly ugly but works no matter who this script is running as.
    # It would be nice if the writability tests could use this logic somehow.
    local _file=${1}
    perm=$(stat -c %a "${_file}")

    # everyone permission
    if [[ ${perm:2:1} -ge 4 ]]; then
        return 0
    fi
    # owner permissions
    if [[ ${perm:0:1} -ge 4 ]]; then
        if [[ "$(stat -c %U ${_file})" = "${userid}" ]] || [[ "$(stat -c %u ${_file})" = "${userid}" ]]; then
            return 0
        fi
    fi
    # group permissions
    if [[ ${perm:1:1} -ge 4 ]]; then
        if containsElement "$(stat -c %g ${_file})" "${groups[@]}" || containsElement "$(stat -c %G ${_file})" "${groups[@]}" ; then
            return 0
        fi
    fi
    return 1
}

function is_writable
{
    # It would be nice if this and the is_readable function could combine somehow
    local _file=${1}
    perm=$(stat -c %a "${_file}")

    # everyone permission
    if containsElement ${perm:2:1} 2 3 6 7; then
        return 0
    fi
    # owner permissions
    if containsElement ${perm:0:1} 2 3 6 7; then
        if [[ "$(stat -c %U ${_file})" = "${userid}" ]] || [[ "$(stat -c %u ${_file})" = "${userid}" ]]; then
            return 0
        fi
    fi
    # group permissions
    if containsElement ${perm:1:1} 2 3 6 7; then
        if containsElement "$(stat -c %g ${_file})" "${groups[@]}" || containsElement "$(stat -c %G ${_file})" "${groups[@]}" ; then
            return 0
        fi
    fi
    return 1
}


function print_permissions_advice_and_fail
{
    _directory=${1}
    echo >&2 "
Folder ${_directory} is not accessible for user: ${userid} or group ${groupid} or groups ${groups[@]}, this is commonly a file permissions issue on the mounted folder.

Hints to solve the issue:
1) Make sure the folder exists before mounting it. Docker will create the folder using root permissions before starting the ONgDB container. The root permissions disallow ONgDB from writing to the mounted folder.
2) Pass the folder owner's user ID and group ID to docker run, so that docker runs as that user.
If the folder is owned by the current user, this can be done by adding this flag to your docker run command:
  --user=\$(id -u):\$(id -g)
       "
    exit 1
}

function check_mounted_folder_readable
{
    local _directory=${1}
    if ! is_readable "${_directory}"; then
        print_permissions_advice_and_fail "${_directory}"
    fi
}

function check_mounted_folder_with_chown
{
# The /data and /log directory are a bit different because they are very likely to be mounted by the user but not
# necessarily writable.
# This depends on whether a user ID is passed to the container and which folders are mounted.
#
#   No user ID passed to container:
#   1) No folders are mounted.
#      The /data and /log folder are owned by ongdb by default, so should be writable already.
#   2) Both /log and /data are mounted.
#      This means on start up, /data and /logs are owned by an unknown user and we should chown them to ongdb for
#      backwards compatibility.
#
#   User ID passed to container:
#   1) Both /data and /logs are mounted
#      The /data and /logs folders are owned by an unknown user but we *should* have rw permission to them.
#      That should be verified and error (helpfully) if not.
#   2) User mounts /data or /logs *but not both*
#      The  unmounted folder is still owned by ongdb, which should already be writable. The mounted folder should
#      have rw permissions through user id. This should be verified.
#   3) No folders are mounted.
#      The /data and /log folder are owned by ongdb by default, and these are already writable by the user.
#      (This is a very unlikely use case).

    local mountFolder=${1}
    if running_as_root; then
        if ! is_writable "${mountFolder}" && ! secure_mode_enabled; then
            # warn that we're about to chown the folder and then chown it
            echo "Warning: Folder mounted to \"${mountFolder}\" is not writable from inside container. Changing folder owner to ${userid}."
            chown -R "${userid}":"${groupid}" "${mountFolder}"
        fi
    else
        if [[ ! -w "${mountFolder}" ]]  && [[ "$(stat -c %U ${mountFolder})" != "ongdb" ]]; then
            print_permissions_advice_and_fail "${mountFolder}"
        fi
    fi
}

function load_plugin_from_github
{
  # Load a plugin at runtime. The provided github repository must have a versions.json on the master branch with the
  # correct format.
  local _plugin_name="${1}" #e.g. apoc, graph-algorithms, graph-ql

  local _plugins_dir="${ONGDB_HOME}/plugins"
  if [ -d /plugins ]; then
    local _plugins_dir="/plugins"
  fi
  local _versions_json_url="$(jq --raw-output "with_entries( select(.key==\"${_plugin_name}\") ) | to_entries[] | .value.versions" /ongdb-plugins.json )"
  # Using the same name for the plugin irrespective of version ensures we don't end up with different versions of the same plugin
  local _destination="${_plugins_dir}/${_plugin_name}.jar"
  local _ongdb_version="$(ongdb --version | cut -d' ' -f2)"

  # Now we call out to github to get the versions.json for this plugin and we parse that to find the url for the correct plugin jar for our ongdb version
  echo "Fetching versions.json for Plugin '${_plugin_name}' from ${_versions_json_url}"
  local _versions_json="$(wget -q --timeout 300 --tries 30 -O - "${_versions_json_url}")"
  local _plugin_jar_url="$(echo "${_versions_json}" | jq --raw-output ".[] | select(.ongdb==\"${_ongdb_version}\") | .jar")"
  if [[ -z "${_plugin_jar_url}" ]]; then
    echo >&2 "Error: No jar URL found for version '${_ongdb_version}' in versions.json from '${_versions_json_url}'"
    echo >&2 "${_versions_json}"
    exit 1
  fi
  echo "Installing Plugin '${_plugin_name}' from ${_plugin_jar_url} to ${_destination} "
  wget -q --timeout 300 --tries 30 --output-document="${_destination}" "${_plugin_jar_url}"

  if ! is_readable "${_destination}"; then
    echo >&2 "Plugin at '${_destination}' is not readable"
    exit 1
  fi
}

function apply_plugin_default_configuration
{
  # Set the correct Load a plugin at runtime. The provided github repository must have a versions.json on the master branch with the
  # correct format.
  local _plugin_name="${1}" #e.g. apoc, graph-algorithms, graph-ql
  local _reference_conf="${2}" # used to determine if we can override properties
  local _ongdb_conf="${ONGDB_HOME}/conf/ongdb.conf"

  local _property _value
  echo "Applying default values for plugin ${_plugin_name} to ongdb.conf"
  for _entry in $(jq  --compact-output --raw-output "with_entries( select(.key==\"${_plugin_name}\") ) | to_entries[] | .value.properties | to_entries[]" /ongdb-plugins.json); do
    _property="$(jq --raw-output '.key' <<< "${_entry}")"
    _value="$(jq --raw-output '.value' <<< "${_entry}")"

    # the first grep strips out comments
    if grep -o "^[^#]*" "${_reference_conf}" | grep -q --fixed-strings "${_property}=" ; then
      # property is already set in the user provided config. In this case we don't override what has been set explicitly by the user.
      echo "Skipping ${_property} for plugin ${_plugin_name} because it is already set"
    else
      if grep -o "^[^#]*" "${_ongdb_conf}" | grep -q --fixed-strings "${_property}=" ; then
        sed --in-place "s/${_property}=/&${_value},/" "${_ongdb_conf}"
      else
        echo "${_property}=${_value}" >> "${_ongdb_conf}"
      fi
    fi
  done
}

function install_ongdb_plugins
{
  # We store a copy of the config before we modify it for the plugins to allow us to see if there are user-set values in the input config that we shouldn't override
  local _old_config="$(mktemp)"
  cp "${ONGDB_HOME}"/conf/ongdb.conf "${_old_config}"
  for plugin_name in $(echo "${ONGDB_PLUGINS}" | jq --raw-output '.[]'); do
    load_plugin_from_github "${plugin_name}"
    apply_plugin_default_configuration "${plugin_name}" "${_old_config}"
  done
  rm "${_old_config}"
}

# If we're running as root, then run as the ongdb user. Otherwise
# docker is running with --user and we simply use that user.  Note
# that su-exec, despite its name, does not replicate the functionality
# of exec, so we need to use both
if running_as_root; then
  userid="ongdb"
  groupid="ongdb"
  groups=($(id -G ongdb))
  exec_cmd="exec gosu ongdb:ongdb"
else
  userid="$(id -u)"
  groupid="$(id -g)"
  groups=($(id -G))
  exec_cmd="exec"
fi
readonly userid
readonly groupid
readonly groups
readonly exec_cmd


# Need to chown the home directory - but a user might have mounted a
# volume here (notably a conf volume). So take care not to chown
# volumes (stuff not owned by ongdb)
if running_as_root; then
    # Non-recursive chown for the base directory
    chown "${userid}":"${groupid}" "${ONGDB_HOME}"
    chmod 700 "${ONGDB_HOME}"
    find "${ONGDB_HOME}" -mindepth 1 -maxdepth 1 -user root -type d -exec chown -R ${userid}:${groupid} {} \;
    find "${ONGDB_HOME}" -mindepth 1 -maxdepth 1 -user root -type d -exec chmod -R 700 {} \;
fi

# Env variable naming convention:
# - prefix ONGDB_
# - double underscore char '__' instead of single underscore '_' char in the setting name
# - underscore char '_' instead of dot '.' char in the setting name
# Example:
# ONGDB_dbms_tx__log_rotation_retention__policy env variable to set
#       dbms.tx_log.rotation.retention_policy setting

# Backward compatibility - map old hardcoded env variables into new naming convention (if they aren't set already)
# Set some to default values if unset
: ${ONGDB_dbms_tx__log_rotation_retention__policy:=${ONGDB_dbms_txLog_rotation_retentionPolicy:-"100M size"}}
: ${ONGDB_wrapper_java_additional:=${ONGDB_UDC_SOURCE:-"-Dongdb.ext.udc.source=docker"}}
: ${ONGDB_dbms_unmanaged__extension__classes:=${ONGDB_dbms_unmanagedExtensionClasses:-}}
: ${ONGDB_dbms_allow__format__migration:=${ONGDB_dbms_allowFormatMigration:-}}
: ${ONGDB_dbms_connectors_default__advertised__address:=${ONGDB_dbms_connectors_defaultAdvertisedAddress:-}}
: ${ONGDB_ha_server__id:=${ONGDB_ha_serverId:-}}
: ${ONGDB_ha_initial__hosts:=${ONGDB_ha_initialHosts:-}}

if [ "${ONGDB_EDITION}" == "enterprise" ];
  then
   : ${ONGDB_causal__clustering_expected__core__cluster__size:=${ONGDB_causalClustering_expectedCoreClusterSize:-}}
   : ${ONGDB_causal__clustering_initial__discovery__members:=${ONGDB_causalClustering_initialDiscoveryMembers:-}}
   : ${ONGDB_causal__clustering_discovery__advertised__address:=${ONGDB_causalClustering_discoveryAdvertisedAddress:-"$(hostname):5000"}}
   : ${ONGDB_causal__clustering_transaction__advertised__address:=${ONGDB_causalClustering_transactionAdvertisedAddress:-"$(hostname):6000"}}
   : ${ONGDB_causal__clustering_raft__advertised__address:=${ONGDB_causalClustering_raftAdvertisedAddress:-"$(hostname):7000"}}
   # Custom settings for dockerized ongdb
   : ${ONGDB_ha_host_coordination:=$(hostname):5001}
   : ${ONGDB_ha_host_data:=$(hostname):6001}
   : ${ONGDB_causal__clustering_discovery__advertised__address:=$(hostname):5000}
   : ${ONGDB_causal__clustering_transaction__advertised__address:=$(hostname):6000}
   : ${ONGDB_causal__clustering_raft__advertised__address:=$(hostname):7000}
fi

# unset old hardcoded unsupported env variables
unset ONGDB_dbms_txLog_rotation_retentionPolicy ONGDB_UDC_SOURCE \
    ONGDB_dbms_unmanagedExtensionClasses ONGDB_dbms_allowFormatMigration \
    ONGDB_dbms_connectors_defaultAdvertisedAddress ONGDB_ha_serverId \
    ONGDB_ha_initialHosts ONGDB_causalClustering_expectedCoreClusterSize \
    ONGDB_causalClustering_initialDiscoveryMembers \
    ONGDB_causalClustering_discoveryListenAddress \
    ONGDB_causalClustering_discoveryAdvertisedAddress \
    ONGDB_causalClustering_transactionListenAddress \
    ONGDB_causalClustering_transactionAdvertisedAddress \
    ONGDB_causalClustering_raftListenAddress \
    ONGDB_causalClustering_raftAdvertisedAddress

if [ -d /conf ]; then
    if secure_mode_enabled; then
	    check_mounted_folder_readable "/conf"
    fi
    find /conf -type f -exec cp {} "${ONGDB_HOME}"/conf \;
fi

if [ -d /ssl ]; then
    if secure_mode_enabled; then
    	check_mounted_folder_readable "/ssl"
    fi
    : ${ONGDB_dbms_directories_certificates:="/ssl"}
fi

if [ -d /plugins ]; then
    if secure_mode_enabled; then
        if [[ ! -z "${ONGDB_PLUGINS:-}" ]]; then
            # We need write permissions
            check_mounted_folder_with_chown "/plugins"
        fi
        check_mounted_folder_readable "/plugins"
    fi
    : ${ONGDB_dbms_directories_plugins:="/plugins"}
fi

if [ -d /import ]; then
    if secure_mode_enabled; then
        check_mounted_folder_readable "/import"
    fi
    : ${ONGDB_dbms_directories_import:="/import"}
fi

if [ -d /metrics ]; then
    if secure_mode_enabled; then
        check_mounted_folder_readable "/metrics"
    fi
    : ${ONGDB_dbms_directories_metrics:="/metrics"}
fi

if [ -d /logs ]; then
    check_mounted_folder_with_chown "/logs"
    : ${ONGDB_dbms_directories_logs:="/logs"}
fi

if [ -d /data ]; then
    check_mounted_folder_with_chown "/data"
    if [ -d /data/databases ]; then
        check_mounted_folder_with_chown "/data/databases"
    fi
    if [ -d /data/dbms ]; then
        check_mounted_folder_with_chown "/data/dbms"
    fi
fi

if [ -d /data ]; then
    check_mounted_folder_with_chown "/data"
fi


# set the ongdb initial password only if you run the database server
if [ "${cmd}" == "ongdb" ]; then
    if [ "${ONGDB_AUTH:-}" == "none" ]; then
        ONGDB_dbms_security_auth__enabled=false
    elif [[ "${ONGDB_AUTH:-}" == ongdb/* ]]; then
        password="${ONGDB_AUTH#ongdb/}"
        if [ "${password}" == "ongdb" ]; then
            echo >&2 "Invalid value for password. It cannot be 'ongdb', which is the default."
            exit 1
        fi

        if running_as_root; then
            # running set-initial-password as root will create subfolders to /data as root, causing startup fail when ongdb can't read or write the /data/dbms folder
            # creating the folder first will avoid that
            mkdir -p /data/dbms
            chown "${userid}":"${groupid}" /data/dbms
        fi
        # Will exit with error if users already exist (and print a message explaining that)
        # we probably don't want the message though, since it throws an error message on restarting the container.
        ongdb-admin set-initial-password "${password}" 2>/dev/null || true
    elif [ -n "${ONGDB_AUTH:-}" ]; then
        echo >&2 "Invalid value for ONGDB_AUTH: '${ONGDB_AUTH}'"
        exit 1
    fi
fi

declare -A COMMUNITY
declare -A ENTERPRISE

COMMUNITY=(
     [dbms.tx_log.rotation.retention_policy]="100M size"
     [dbms.memory.pagecache.size]="512M"
     [dbms.connectors.default_listen_address]="0.0.0.0"
     [dbms.connector.https.listen_address]="0.0.0.0:7473"
     [dbms.connector.http.listen_address]="0.0.0.0:7474"
     [dbms.connector.bolt.listen_address]="0.0.0.0:7687"
     [dbms.udc.enabled]="false"
)

ENTERPRISE=(
)

for conf in ${!COMMUNITY[@]} ; do
    if ! grep -q "^$conf" "${ONGDB_HOME}"/conf/ongdb.conf
    then
        echo -e "\n"$conf=${COMMUNITY[$conf]} >> "${ONGDB_HOME}"/conf/ongdb.conf
    fi
done

for conf in ${!ENTERPRISE[@]} ; do
    if [ "${ONGDB_EDITION}" == "enterprise" ];
    then
       if ! grep -q "^$conf" "${ONGDB_HOME}"/conf/ongdb.conf
       then
        echo -e "\n"$conf=${ENTERPRISE[$conf]} >> "${ONGDB_HOME}"/conf/ongdb.conf
       fi
    fi
done

#The udc.source=tarball should be replaced by udc.source=docker in both dbms.jvm.additional and wrapper.java.additional
#Using sed to replace only this part will allow the custom configs to be added after, separated by a ,.
if grep -q "udc.source=tarball" "${ONGDB_HOME}"/conf/ongdb.conf; then
     sed -i -e 's/udc.source=tarball/udc.source=docker/g' "${ONGDB_HOME}"/conf/ongdb.conf
fi
#The udc.source should always be set to docker by default and we have to allow also custom configs to be added after that.
#In this case, this piece of code helps to add the default value and a , to support custom configs after.
if ! grep -q "dbms.jvm.additional=-Dunsupported.dbms.udc.source=docker" "${ONGDB_HOME}"/conf/ongdb.conf; then
  sed -i -e 's/dbms.jvm.additional=/dbms.jvm.additional=-Dunsupported.dbms.udc.source=docker,/g' "${ONGDB_HOME}"/conf/ongdb.conf
fi

# list env variables with prefix ONGDB_ and create settings from them
unset ONGDB_AUTH ONGDB_SHA256 ONGDB_TARBALL
for i in $( set | grep ^ONGDB_ | awk -F'=' '{print $1}' | sort -rn ); do
    setting=$(echo ${i} | sed 's|^ONGDB_||' | sed 's|_|.|g' | sed 's|\.\.|_|g')
    value=$(echo ${!i})
    # Don't allow settings with no value or settings that start with a number (ongdb converts settings to env variables and you cannot have an env variable that starts with a number)
    if [[ -n ${value} ]]; then
        if [[ ! "${setting}" =~ ^[0-9]+.*$ ]]; then
            if grep -q -F "${setting}=" "${ONGDB_HOME}"/conf/ongdb.conf; then
                # Remove any lines containing the setting already
                sed --in-place "/^${setting}=.*/d" "${ONGDB_HOME}"/conf/ongdb.conf
            fi
            # Then always append setting to file
            echo "${setting}=${value}" >> "${ONGDB_HOME}"/conf/ongdb.conf
        else
            echo >&2 "WARNING: ${setting} not written to conf file because settings that start with a number are not permitted"
        fi
    fi
done

if [[ ! -z "${ONGDB_PLUGINS:-}" ]]; then
  # ONGDB_PLUGINS should be a json array of plugins like '["graph-algorithms", "apoc", "streams", "graphql"]'
  install_ongdb_plugins
fi

[ -f "${EXTENSION_SCRIPT:-}" ] && . ${EXTENSION_SCRIPT}

if [ "${cmd}" == "dump-config" ]; then
    if ! is_writable "/conf"; then
        print_permissions_advice_and_fail "/conf"
    fi
    cp --recursive "${ONGDB_HOME}"/conf/* /conf
    echo "Config Dumped"
    exit 0
fi

# Use su-exec to drop privileges to ongdb user
# Note that su-exec, despite its name, does not replicate the
# functionality of exec, so we need to use both
if [ "${cmd}" == "ongdb" ]; then
  ${exec_cmd} ongdb console
else
  ${exec_cmd} "$@"
fi