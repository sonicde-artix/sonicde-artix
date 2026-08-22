#!/bin/sh

# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightInfo: 2026 callmetango for SonicDE

set -eu


# Environment

DOCKER_IMAGE="${DOCKER_IMAGE:-ghcr.io/archlinux/archlinux:latest}"


# Functions

start_container() {
	uid=$(id -u)
	docker run --detach --name arch \
		--volume "$GITHUB_WORKSPACE:/workspace" \
		"$DOCKER_IMAGE" sh -c "
			useradd -u $uid -m runner
			while : ; do sleep 3600 ; done
		"
}

cleanup() {
	docker rm --force arch >/dev/null 2>&1 || :
}


# Main

trap cleanup 0
trap 'cleanup; exit 1' HUP INT TERM

app=sonicde-arch-buildbot
botid=$(gh api "users/${app}[bot]" --jq .id)
started=0

git init .
git config user.name "${app}[bot]"
git config user.email "${botid}+${app}[bot]@users.noreply.github.com"
git remote add origin "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
git fetch --depth=1 origin "$GITHUB_REF_NAME"
git checkout -B "$GITHUB_REF_NAME" FETCH_HEAD

for pkgbuild in */PKGBUILD; do
	test "$pkgbuild" = '*/PKGBUILD' && break

	if [ $started -eq 0 ] ; then
		start_container
		started=1
	fi

	dir=${pkgbuild%/PKGBUILD}
	printf 'Generating %s/.SRCINFO ... ' "$dir"
	docker exec --user runner --workdir "/workspace/$dir" arch \
		sh -c 'makepkg --printsrcinfo' >"$dir/.SRCINFO"
	printf 'done\n'
done

status=$(git status --short)
printf '%s\n' "$status" | grep -q '\.SRCINFO$' || exit 0

git add -- */.SRCINFO
git commit --message 'Update .SRCINFOs'
git push origin "$GITHUB_REF_NAME"
