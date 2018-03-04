function __znaphodl__cleanup {
  [[ "${fifoname:-}" ]] && rm "${fifoname}"
  [[ "${fifodir:-}" ]] && rmdir "${fifodir}"
}

export -f __znaphodl__cleanup

function __znaphodl__load_latest_common_snapshot {
  latest_common_snapshot="$(
    comm -12 \
      <(
        zfs list -d 1 -H -o name \
          -s creation -t snapshot "${source_dataset}"
      ) \
      <(
        if [[ "${target_hostname}" ]]; then
          set -- sudo ssh "${target_hostname}"
        else
          set --
        fi
        "$@" zfs list -d 1 -H -o name \
          -s creation -t snapshot "${target_dataset}" \
          | awk -F @ -v "ds=${source_dataset}" \
            '{ print ds"@"$2 }'
      ) \
      | tail -1
  )"
}

export -f __znaphodl__load_latest_common_snapshot

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

function __znaphodl__load_target_dataset_record {
  local pid exitstatus fifodir fifoname

  trap __znaphodl__cleanup EXIT INT HUP TERM
  fifodir="$(mktemp -d)"
  fifoname="${fifodir}/znaphodl.$RANDOM.fifo"
  mkfifo -m0600 "${fifoname}" || return 1

  (__znaphodl__target_dataset_record) > "${fifoname}" &
  pid="$!"
  IFS=$'\t' read -d $'\n' target_dataset target_hostname \
    < "${fifoname}" \
    || true

  wait "${pid}" || exitstatus="$?"

  __znaphodl__cleanup
  trap - EXIT INT HUP TERM
  return "${exitstatus:-0}"
}

export -f __znaphodl__load_target_dataset_record

function __znaphodl__load_tagged_source_snapshot {
  tagged_source_snapshot="$(
    zfs list -r -H -t snapshot -o name "${source_dataset}" \
      | xxargs -r -n 1 zfs holds -r -H \
      | awk -F '\t' -v "tag=${source_hold_tag}" \
        '$2 == tag && found {
          print "Duplicate tag: "tag > "/dev/stderr"; exit 1
        }
        $2 == tag { found = 1; print $1 }'
  )"
}

export -f __znaphodl__load_tagged_source_snapshot

function __znaphodl {
  local latest_common_snapshot source_dataset source_hold_tag
  local tagged_source_snapshot target_dataset target_hostname
  local target_dataset_key

  set -eu
  sudo -v

  source_dataset="${1?}"
  target_dataset_key="${2?}"

  __znaphodl__load_target_dataset_record

  if [[ "${target_hostname}" ]]; then
    set -- sudo ssh "${target_hostname}"
  else
    set --
  fi
  "$@" zfs list "${target_dataset}" >/dev/null

  source_hold_tag="remote/${target_dataset}"

  echo "Auditing snapshot tag: ${source_hold_tag}"

  __znaphodl__load_tagged_source_snapshot

  if [[ ! "${tagged_source_snapshot}" ]]; then
    echo >&2 "[ERROR] Tag ${source_hold_tag} not found" \
      "on ${source_dataset}"
    echo >&2 '[INFO] Run `zfs hold '"${source_hold_tag}"'`' \
      'on a common snapshot manually'
    return 1
  fi

  echo "Previously tagged snapshot: ${tagged_source_snapshot}"

  __znaphodl__load_latest_common_snapshot

  if [[ ! "${latest_common_snapshot}" ]]; then
    echo >&2 '[ERROR] Unable to find a common snapshot in' \
      "datasets ${source_dataset} and ${target_dataset};" \
      'aborting'
    return 1
  fi

  echo "Latest common snapshot: ${latest_common_snapshot}"

  if [[
    "${tagged_source_snapshot}" == "${latest_common_snapshot}"
  ]]; then
    echo >&2 "[WARNING] no change in latest common snapshot"
    echo >&2 "[INFO] Nothing to do for ${latest_common_snapshot}"
    return 0
  fi

  echo "Holding latest snapshot: ${latest_common_snapshot}"
  sudo zfs hold "${source_hold_tag}" \
    "${latest_common_snapshot}"

  echo "Releasing tagged snapshot: ${tagged_source_snapshot}"
  sudo zfs release "${source_hold_tag}" \
    "${tagged_source_snapshot}"

  echo "Tag ${source_hold_tag} has been moved successfully"
  echo "Done"
}

export -f __znaphodl
