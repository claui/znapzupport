function __dataset_id__print_usage {
  echo "Usage:" \
    "$(basename -- "$0") [-r] filesystem ..."
}

export -f __dataset_id__print_usage


function __dataset_id__cleanup {
  [[ "${fifoname:-}" ]] && rm "${fifoname}"
  [[ "${fifodir:-}" ]] && rmdir "${fifodir}"
}

export -f __dataset_id__cleanup


function __dataset_id__load_dataset_record {
  local pid exitstatus fifodir fifoname

  trap __dataset_id__cleanup EXIT INT HUP TERM
  fifodir="$(mktemp -d)"
  fifoname="${fifodir}/dataset_id.$RANDOM.fifo"
  mkfifo -m0600 "${fifoname}" || return 1

  (__dataset_id__dataset_record "$@") > "${fifoname}" &
  pid="$!"
  IFS=$'\t' read -d $'\n' dataset dataset_id < "${fifoname}" \
    || true

  wait "${pid}" || exitstatus="$?"

  __dataset_id__cleanup
  trap - EXIT INT HUP TERM
  return "${exitstatus:-0}"
}

export -f __dataset_id__load_dataset_record


function __dataset_id__dataset_record {
  local DATASET_ID_PROPERTY_NAME='cat.claudi:id'

  local dataset_id
  local OPTIND=1
  local option
  local parent_dataset
  local recursive=0

  while getopts ':rm:' option; do
    case "${option}" in
    m)
      dataset_id="${OPTARG}"
      ;;
    r)
      recursive=1
      ;;
    '?')
      __dataset_id__print_usage >&2
      return 1
      ;;
    esac
  done

  shift "$(($OPTIND-1))"

  parent_dataset="$1"

  if [[ ! "${parent_dataset}" ]]; then
    __dataset_id__print_usage >&2
    return 1
  fi

  (
    set -o pipefail --
    if [[ "${recursive}" -ne 0 ]]; then
      set -- -r "$@"
    fi
    if [[ "${dataset_id}" ]]; then
      zfs get "$@" -H -o name,value,source -t filesystem \
        "${DATASET_ID_PROPERTY_NAME}" "${parent_dataset}" \
        | awk -v "dataset_id=${dataset_id}" -F '\t' '
          $2 == dataset_id && $3 == "local" {
            print $1"\t"$2; found=1; exit
          }
          END { exit !found }
        '
    else
      zfs get "$@" -H -o name,value,source -t filesystem \
        "${DATASET_ID_PROPERTY_NAME}" "${parent_dataset}" \
        | awk -F '\t' '
          $3 == "local" { print $1"\t"$2; found=1; exit }
          END { exit !found }
        '
    fi
  )

  return "$?"
}

export -f __dataset_id__dataset_record
