source libexec/dataset_id.bash
source libexec/zpoolz.bash

function __znaplizt__summarize_dataset {
  local dataset

  dataset="${1?}"
  echo '# Summary'
  zfs get -H -o name,property,value \
    used,logicalused,usedbydataset`
      `,referenced,logicalreferenced,usedbysnapshots \
    "${dataset}" \
    | xargs -r printf '%s    %-18s%10s\n'
}

export -f __znaplizt__summarize_dataset

function __znaplizt {
  local OPTARG
  local OPTIND=1
  local option

  local backup_dataset
  local backup_datasets=()
  local backup_poolname
  local backup_selected=1
  local dataset=
  local dataset_id=
  local dataset_last_component
  local given_dataset_id=
  local home_datasets=()
  local home_poolname
  local home_selected=1
  local poolnames
  local summarize=0
  local verbose=0

  while getopts ':bhsvm:' option; do
    case "${option}" in
    b)
      home_selected=0
      ;;
    h)
      backup_selected=0
      ;;
    s)
      summarize=1
      ;;
    v)
      verbose=1
      ;;
    m)
      given_dataset_id="${OPTARG}"
      ;;
    ':')
      printf >&2 "Option -%s requires an argument.\n" "${OPTARG}"
      return 1
      ;;
    '?')
      echo >&2 "Usage:" \
        "$(basename -- "$0") [-b|-h] [-s] [-v] [-m dataset_id]" \
        "[pool] ..."
      return 1
      ;;
    esac
  done

  shift "$((OPTIND-1))"

  if [[ "$#" -gt 0 ]]; then
    poolnames=("$@")
  else
    if ! __zpoolz__load_poolnames; then
      echo >&2 "Unable to identify pool names"
      return 1
    fi
  fi

  if [[ "${#poolnames[@]}" -eq 0 ]]; then
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
    if [[ "${given_dataset_id}" ]]; then
      if {
        ! __dataset_id__load_dataset_record -r \
          -m "${given_dataset_id}" "${home_poolname}"
      }; then
        continue
      fi
    else
      if {
        ! __dataset_id__load_dataset_record -r "${home_poolname}"
      }; then
        continue
      fi
    fi

    if [[ "${home_selected}" -ne 0 ]]; then
      home_datasets+=("${dataset}")
    fi

    if [[ "${backup_selected}" -ne 0 ]]; then
      dataset_last_component="${dataset##*/}"

      if [[ "${verbose}" -ne 0 ]]; then
        echo >&2 "Looking for backup datasets of ${dataset}"
      fi

      for backup_poolname in "${poolnames[@]}"; do
        backup_dataset="${backup_poolname}/backup/${dataset_id}`
          `/${dataset_last_component}"
        if {
          zfs list -H -o name -t filesystem \
            "${backup_dataset}" >/dev/null 2>&1;
        }; then
          backup_datasets+=("${backup_dataset}")
        fi
      done
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

    if [[ "${summarize}" -ne 0 ]]; then
      __znaplizt__summarize_dataset "${dataset}"
    fi
  done
  for dataset in "${backup_datasets[@]}"; do
    echo $'\nBackup dataset'

    zfs list -d 1 \
      -o name,used,logicalreferenced,written \
      -s creation -t all "${dataset}"

    if [[ "${summarize}" -ne 0 ]]; then
      __znaplizt__summarize_dataset "${dataset}"
    fi
  done
}

export -f __znaplizt
