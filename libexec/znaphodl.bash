function __znaphodl__load_target_dataset_record_cleanup {
  [[ "${fifoname:-}" ]] && rm "${fifoname}"
  [[ "${fifodir:-}" ]] && rmdir "${fifodir}"
}

export -f __znaphodl__load_target_dataset_record_cleanup

function __znaphodl__lockfile_cleanup {
  if [[ "${debug}" -ne 0 ]]; then
    echo >&2 "[DEBUG] Checking lockfile: ${lockfile}"
  fi

  if [[ -e "${lockfile:-}" ]]; then
    if [[ "${debug}" -ne 0 ]]; then
      echo >&2 "[DEBUG] Found lockfile"
    fi

    sudo rm -f "${lockfile}"

    if [[ "${debug}" -ne 0 ]]; then
      echo >&2 "[DEBUG] Lockfile deleted"
    fi
  fi
}

export -f __znaphodl__lockfile_cleanup

function __znaphodl__load_latest_common_snapshot {
  local target_snapshots

  target_snapshots="$(
    if [[ "${target_hostname}" ]]; then
      set -- sudo ssh -- "${target_hostname}"
    else
      set --
    fi
    exec "$@" zfs list -d 1 -H -o name \
      -s creation -t snapshot "${target_dataset}"
  )"

  latest_common_snapshot="$(
    comm -12 \
      <(
        zfs list -d 1 -H -o name \
          -s creation -t snapshot "${source_dataset}"
      ) \
      <(
        awk -F @ -v "ds=${source_dataset}" \
          '{ print ds"@"$2 }' <<< "${target_snapshots}"
      ) \
      | tail -1
  )"
}

export -f __znaphodl__load_latest_common_snapshot

function __znaphodl__load_target_dataset_space_available {
  target_dataset_space_available="$(
    if [[ "${target_hostname}" ]]; then
      set -- sudo ssh -- "${target_hostname}"
    else
      set --
    fi
    exec "$@" zfs get -H -o value available "${target_dataset}"
  )"
}

export -f __znaphodl__load_target_dataset_space_available

function __znaphodl__load_target_dataset_record {
  local pid exitstatus fifodir fifoname

  trap __znaphodl__load_target_dataset_record_cleanup \
    EXIT INT HUP TERM
  fifodir="$(mktemp -d)"
  fifoname="${fifodir}/znaphodl.$RANDOM.fifo"
  mkfifo -m0600 "${fifoname}" || return 1

  (__znaphodl__target_dataset_record) > "${fifoname}" &
  pid="$!"
  IFS=$'\t' read -d $'\n' target_dataset target_hostname \
    < "${fifoname}" \
    || true

  wait "${pid}" || exitstatus="$?"

  __znaphodl__load_target_dataset_record_cleanup
  trap - EXIT INT HUP TERM
  return "${exitstatus:-0}"
}

export -f __znaphodl__load_target_dataset_record

function __znaphodl__target_dataset_record {
  (
    set -o pipefail
    znapzendzetup export "${source_dataset}" 2>/dev/null \
      | awk -F [=:] -v 'OFS=\t' -v 'ORS=' \
        -v "key=${target_dataset_key}" \
        '$1 == "dst_"key {
          found = 1
          if ($3) print $3, $2; else print $2
        }
        END { if (!found) exit 1 }'
  )

  return "$?"
}

export -f __znaphodl__target_dataset_record

function __znaphodl__load_tagged_source_snapshot {
  tagged_source_snapshot="$(
    zfs list -H -t snapshot -o name "${source_dataset}" \
      | xxargs -r -n 1 -P 16 zfs holds -r -H \
      | awk -F '\t' -v "tag=${source_hold_tag}" \
        '$2 == tag && found {
          print "Duplicate tag: "tag > "/dev/stderr"; exit 1
        }
        $2 == tag { found = 1; print $1 }'
  )"
}

export -f __znaphodl__load_tagged_source_snapshot

function __znaphodl__move_tag_to_latest_common_snapshot {
  echo >&2 "Holding latest snapshot: ${latest_common_snapshot}"
  sudo zfs hold "${source_hold_tag}" "${latest_common_snapshot}"

  echo >&2 "Releasing tagged snapshot: ${tagged_source_snapshot}"
  sudo zfs release "${source_hold_tag}" "${tagged_source_snapshot}"

  echo >&2 "Tag ${source_hold_tag} has been moved successfully"
}

export -f __znaphodl__move_tag_to_latest_common_snapshot

function __znaphodl {
  local LOCKFILE_BASEDIR='/var/run/znapzupport'
  local LOCKFILE_TTL_SECONDS=1800
  local PROPERTY_NAMESPACE='cat.claudi'

  local OPTIND=1
  local option

  local debug=0
  local latest_common_snapshot
  local last_query_timestamp_property_name
  local lockfile
  local log_available_space=0
  local source_dataset
  local source_hold_tag
  local space_available_property_name
  local tag_snapshot=1
  local tagged_source_snapshot
  local target_dataset
  local target_dataset_key
  local target_hostname
  local target_dataset_space_available

  set -eu

  while getopts ':dln' option; do
    case "${option}" in
    d)
      debug=1
      ;;
    l)
      log_available_space=1
      ;;
    n)
      tag_snapshot=0
      ;;
    '?')
      echo >&2 "Usage:" \
        "$(basename -- "$0") [-d] [-l] [-n]" \
        "source_dataset target_dataset_key"
      return 1
      ;;
    esac
  done

  shift "$(($OPTIND-1))"

  source_dataset="${1?}"
  target_dataset_key="${2?}"

  sudo -v

  __znaphodl__load_target_dataset_record

  sudo mkdir -p "${LOCKFILE_BASEDIR}"
  lockfile="${LOCKFILE_BASEDIR}/$(
    md5 <<< "${target_dataset_key}").lock"
  echo >&2 "Waiting for previous runs to complete"
  sudo lockfile -l "${LOCKFILE_TTL_SECONDS}" "${lockfile}"
  if [[ "${debug}" -ne 0 ]]; then
    echo >&2 "[DEBUG] Lockfile created: ${lockfile}"
  fi
  trap __znaphodl__lockfile_cleanup EXIT INT HUP TERM

  if [[ "${target_hostname}" ]]; then
    set -- sudo ssh -- "${target_hostname}"
  else
    set --
  fi
  "$@" zfs list "${target_dataset}" >/dev/null

  if [[ "${tag_snapshot}" -eq 0 ]]; then
    echo >&2 "[INFO] Skipping snapshot tag update"
  else
    source_hold_tag="remote/${target_dataset}"

    echo >&2 "Auditing snapshot tag: ${source_hold_tag}"

    __znaphodl__load_tagged_source_snapshot

    if [[ ! "${tagged_source_snapshot}" ]]; then
      echo >&2 "[ERROR] Tag ${source_hold_tag} not found" \
        "on ${source_dataset}"
      echo >&2 '[INFO] Run `zfs hold '"${source_hold_tag}"'`' \
        'on a common snapshot manually'
      return 1
    fi

    echo >&2 "Previously tagged snapshot:" \
      "${tagged_source_snapshot}"

    __znaphodl__load_latest_common_snapshot

    if [[ ! "${latest_common_snapshot}" ]]; then
      echo >&2 '[ERROR] Unable to find a common snapshot in' \
        "datasets ${source_dataset} and ${target_dataset};" \
        'aborting'
      return 1
    fi

    echo >&2 "Latest common snapshot: ${latest_common_snapshot}"

    if [[
      "${tagged_source_snapshot}" == "${latest_common_snapshot}"
    ]]; then
      echo >&2 "[WARNING] no change in latest common snapshot"

      if [[ "${log_available_space}" -eq 0 ]]; then
        echo >&2 "[INFO] Nothing to do for ${latest_common_snapshot}"
      fi
    else
      __znaphodl__move_tag_to_latest_common_snapshot
    fi
  fi

  trap - EXIT INT HUP TERM
  __znaphodl__lockfile_cleanup

  if [[ "${log_available_space}" -ne 0 ]]; then
    echo >&2 "Querying available space on ${target_dataset_key}"
    __znaphodl__load_target_dataset_space_available
    echo >&2 "Available space on ${target_dataset_key}:" \
      "${target_dataset_space_available}"

    last_query_timestamp_property_name="${PROPERTY_NAMESPACE}`
      `:dst_${target_dataset_key}_last_query_timestamp"
    echo >&2 "Setting property" \
      "${last_query_timestamp_property_name}"
    sudo zfs set \
      "${last_query_timestamp_property_name}=$(xdate '+%F %X')" \
      "${source_dataset}"

    space_available_property_name="${PROPERTY_NAMESPACE}`
      `:dst_${target_dataset_key}_space_available"
    echo >&2 "Setting property ${space_available_property_name}"
    sudo zfs set \
      "${space_available_property_name}`
        `=${target_dataset_space_available}" \
      "${source_dataset}"
  fi

  echo >&2 "Done"
}

export -f __znaphodl
