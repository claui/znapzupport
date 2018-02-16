function __zpoolz__cleanup {
  [[ "${fifoname:-}" ]] && rm "${fifoname}"
  [[ "${fifodir:-}" ]] && rmdir "${fifodir}"
}

export -f __zpoolz__cleanup

function __zpoolz__load_poolnames {
  local fifodir fifoname zpool_pid zpool_status

  trap __zpoolz__cleanup EXIT INT HUP TERM
  fifodir="$(mktemp -d)"
  fifoname="${fifodir}/zpoolz.$RANDOM.fifo"
  mkfifo -m0600 "${fifoname}" || return 1

  (zpool list -H -o name) > "${fifoname}" &
  zpool_pid="$!"
  IFS=$'\n' read -a poolnames -d '' < "${fifoname}" || true

  wait "${zpool_pid}" || zpool_status="$?"

  __zpoolz__cleanup
  trap - EXIT INT HUP TERM
  return "${zpool_status:-0}"
}

export -f __zpoolz__load_poolnames

function __zpoolz {
  local poolnames

  __zpoolz__load_poolnames
  printf '%s\n' "${poolnames[@]}"
}

export -f __zpoolz
