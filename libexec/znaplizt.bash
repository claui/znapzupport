source libexec/dataset_id.bash
source libexec/zpoolz.bash

function __znaplizt {
  local OPTIND=1
  local option

  local backup_dataset
  local backup_datasets=()
  local backup_poolname
  local backup_selected=1
  local dataset=
  local dataset_id=
  local verbose=0
  local home_datasets=()
  local home_poolname
  local home_selected=1
  local poolnames
  local username="$(whoami)"

  while getopts ':bvhm:' option; do
    case "${option}" in
    b)
      home_selected=0
      ;;
    h)
      backup_selected=0
      ;;
    m)
      dataset_id="${OPTARG}"
      ;;
    v)
      verbose=1
      ;;
    ':')
      printf >&2 "Option -%s requires an argument.\n" "${OPTARG}"
      return 1
      ;;
    '?')
      echo >&2 "Usage:" \
        "$(basename "$0") [-b|-h] [-v] [-m dataset_id]" \
        "[pool] ..."
      return 1
      ;;
    esac
  done

  shift "$(($OPTIND-1))"

  if [[ "$@" ]]; then
    poolnames=("$@")
  else
    __zpoolz__load_poolnames
    if [[ "$?" -ne 0 ]]; then
      echo >&2 "Unable to identify pool names"
      return 1
    fi
  fi

  if [[ ! "${poolnames[@]}" ]]; then
    echo >&2 "No pools found"
    return 1
  fi

  if [[ "${verbose}" -ne 0 ]]; then
    echo >&2 "Found ${#poolnames[@]} pool(s)"
  fi

  if [[ "${verbose}" -ne 0 ]]; then
    echo >&2 'Looking for home dataset'
  fi

  for home_poolname in "${poolnames[@]}"; do
    if {
      __dataset_id__load_dataset_record -r "${home_poolname}";
    }; then
      if [[ "${home_selected}" -ne 0 ]]; then
        home_datasets+=("${dataset}")
      fi

      if [[ "${backup_selected}" -ne 0 ]]; then
        if [[ "${verbose}" -ne 0 ]]; then
          echo >&2 "Looking for backup datasets of ${dataset}"
        fi

        for backup_poolname in "${poolnames[@]}"; do
          backup_dataset="${backup_poolname}/backup/${dataset_id}`
            `/${username}"
          if {
            zfs list -H -o name -t filesystem \
              "${backup_dataset}" >/dev/null 2>&1;
          }; then
            backup_datasets+=("${backup_dataset}")
          fi
        done
      fi
    fi
  done

  if [[ "${verbose}" -ne 0 ]]; then
    echo >&2 "Found ${#home_datasets[@]} home dataset(s)"
    echo >&2 "Found ${#backup_datasets[@]} backup dataset(s)"
  fi

  for dataset in "${home_datasets[@]}"; do
    echo $'\nHome dataset'
    zfs list -d 1 \
      -o name,userrefs,used,logicalreferenced,written \
      -s creation -t all "${dataset}"
  done
  for dataset in "${backup_datasets[@]}"; do
    echo $'\nBackup dataset'
    zfs list -d 1 \
      -o name,used,logicalreferenced,written \
      -s creation -t all "${dataset}"
  done
}

export -f __znaplizt
