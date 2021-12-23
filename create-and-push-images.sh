#!/usr/bin/env bash

set -e
set -u
set -o pipefail

: "${1?needs to be the project you want to push the images too}"
: "${2:=100}"

readonly REG='core.harbor.domain'
readonly IMG="${REG}/${1}/test-image"
readonly TDIR="$(mktemp -d)"
readonly SIZE='4M'

trap 'rm -rf "${TDIR}"' EXIT

main() {
	printf 'FROM scratch\nADD file file' > "${TDIR}/Dockerfile"

	local count="${2:-100}"
	local uuid="$( cat /proc/sys/kernel/random/uuid )"
	local i="${IMG}-${uuid}"

	local j=$count
	while (( j-- ))
	do
		dd if=/dev/urandom bs="${SIZE}" count=1 of="${TDIR}/file"
		docker build -t "${i}:${j}" "${TDIR}"
	done

	j=$count
	while (( j-- ))
	do
		docker push "${i}:${j}"
		docker image rm "${i}:${j}"
	done
}

main "$@"
