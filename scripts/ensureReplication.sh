#!/usr/bin/env bash

set -e
set -u
set -o pipefail

readonly D="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

: "${REG_NAME?needs to be the name for the remote harbor}"
: "${REP_NAME?needs to be the name for the replication policy}"
: "${REMOTE_INFO?needs to be the coordinates and the creds for the remote registry}"
: "${API_BASE?needs to be the base URL for harbor}"
: "${API_USER:=admin}"
: "${API_PASS?needs to be the admin password for harbor}"
: "${API_CA_FILE?needs to be the CA of harbor}"

api() {
	local path="$1" ; shift

	curl --fail --silent -L -H 'Content-Type: application/json' -u "${API_USER}:${API_PASS}" \
		--cacert "${API_CA_FILE}" \
		"${API_BASE}/${path}" \
		"$@"
}

jq() {
	command jq -c -S "$@"
}

ensureReg() {
	local regData
	local payload
	local pass

	regData="$(
		api api/v2.0/registries | jq --arg regName "$REG_NAME" '.[] | select(.name == $regName)'
	)"

	pass="$( jq -r .secret "$REMOTE_INFO" )"
	payload="$(
		jq -n \
			--arg name "$REG_NAME" \
			--arg pass "${pass}" \
			--arg user "$( jq -r .name "$REMOTE_INFO" )" \
			--arg url  "$( jq -r .url "$REMOTE_INFO" )" \
			"$(cat "${D}/../registry.create.json")"
	)"

	if [ -z "$regData" ] ; then
		# create
		api "api/v2.0/registries" -X POST --data "${payload}"
	else
		# update
		local id
		id="$( jq .id <<< "$regData" )"
		api "api/v2.0/registries/${id}" -X PUT --data "$payload"
	fi

    api api/v2.0/registries \
        | jq --arg pass "$pass" --arg regName "$REG_NAME" '.[] | select(.name == $regName) | .credential.access_secret = $pass'
}

ensureReplication() {
	local regData="$1"
	local repData
	local payload

	repData="$(
		api "api/v2.0/replication/policies" | jq --arg name "$REP_NAME" '.[] | select(.name == $name)'
	)"

	payload="$(
		jq -n \
			--arg name "$REP_NAME" \
			--argjson destReg "${regData}" \
			"$(cat "${D}/../replicationPolicy.create.json")"
	)"

	if [ -z "$repData" ] ; then
		# create
		api "api/v2.0/replication/policies" -X POST --data "${payload}"
	else
		# update
		local id
		id="$( jq .id <<< "$repData" )"
		api "api/v2.0/replication/policies/${id}" -X PUT --data "$payload"
	fi
}

main() {
	local regData

	regData="$( ensureReg )"
	ensureReplication "${regData}"
}

main "$@"
