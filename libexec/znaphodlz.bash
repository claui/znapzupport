source libexec/dataset_id.bash
source libexec/zpoolz.bash

function __znaphodlz {
  local debug=0
  local home_poolname
  local poolnames

  if ! __zpoolz__load_poolnames; then
    echo >&2 "Unable to identify pool names"
    return 1
  fi

  if [[ ! "${poolnames}" ]]; then
    echo >&2 "No pools found"
    return 1
  fi

  if [[ "${debug}" -ne 0 ]]; then
    echo >&2 "Found ${#poolnames[@]} pool(s)"
  fi

  if [[ "${debug}" -ne 0 ]]; then
    echo >&2 'Looking for home dataset'
  fi

  for home_poolname in "${poolnames[@]}"; do
    if {
      __dataset_id__load_dataset_record -r "$@" "${home_poolname}";
    }; then
      echo $'\n'"Home dataset ${dataset}"
      zfs list -H -t snapshot -o name "${dataset}" \
        | xargs -r -n 1 -P 16 zfs holds -r -H \
        | cut -f '1,2'
    fi
  done
}

export -f __znaphodlz
