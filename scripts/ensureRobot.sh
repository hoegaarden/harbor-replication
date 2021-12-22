#!/usr/bin/env bash

set -e
set -u
set -o pipefail

readonly D="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

: "${USER:=replication}"
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

ensureUser() {
	local robotUser="robot\$${USER}"
	local userData
	local payload

	userData="$(
		api api/v2.0/robots | jq --arg user "$robotUser" '.[] | select(.name == $user)'
	)"

	payload="$(jq -n --arg user "$USER" "$(cat "${D}/../robot.create.json")")"

	if [ -z "$userData" ] ; then
		# create
		api "api/v2.0/robots" -X POST --data "${payload}" \
			| jq .
	else
		# update
		local id
		id="$( jq .id <<< "$userData" )"
		api "api/v2.0/robots/${id}" -X PATCH --data "$payload" \
			| jq --arg id "$id" --arg user "$robotUser" '.name = $user | .id = $id'
	fi
}

main() {
	ensureUser | jq --arg url "$API_BASE" '.url = $url'
}

main "$@"
