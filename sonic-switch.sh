#!/bin/sh
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 SonicDE Community

# shellcheck disable=SC2009
# shellcheck disable=SC2016
set -e -u


# Functions

msg() {
	printf "$1\n"
}

yesno() {
	printf "$1 (y/n): " ; read -r _ANS
	test "$_ANS" = 'y' -o "$_ANS" = 'Y'  && return 0
}

die() {
	printf "$1\n" ; exit 1
}

thank_you() {
	printf "$THANKS_MSG\n"
	cd "$_OLDPWD"
	exit 0
}


# Constants

VERS='0.7.0'
PGP_KEY='72AAA51726BC3C29'
ORIG_URL='https://sonicde-artix.github.io'
REPO_URL="$ORIG_URL/\$arch"

OLD_URLS="$(cat <<-'EO_OLDURLS'
	https://artixlinux.duckdns.org/repos/sonicde
	https://xlibre.net/repo/arch_based/x86_64/sonicde
	https://x11libre.net/repo/arch_based/x86_64/sonicde
EO_OLDURLS
)"

KNOWN_LMS='emptty gdm greetd lemurs ligthdm lxdm ly sddm slim soniclogin xdm'
THANKS_MSG="\nThank you for choosing SonicDE! Please see $ORIG_URL for any further information."
_OLDPWD="$(pwd)"

DL_CMD=
test "$(command -v curl)" && DL_CMD='curl --remote-name'
test "$(command -v wget)" && DL_CMD='wget --no-globber'

SUDO_CMD=
test "$(command -v doas)" && SUDO_CMD='doas'
test "$(command -v sudo)" && SUDO_CMD='sudo'


# Pretext and Prechecks


cat <<-EO_INTRO
	SonicDE.org sonic-switch.sh, version: $VERS.

	This script will install SonicDE on your Artix Linux system. It will restart your
	graphical session so please save all your work. It will also silently replace the
	conflicting KDE components with the SonicDE ones.
EO_INTRO

test "$DL_CMD" || die '\nNo `curl` or `wget` command found. Please install one.'
test "$SUDO_CMD" || die '\nNo `doas` or `sudo` command found. Please install one.'

test "$(grep -i "^ID=['\"]*artix['\"]*$" /etc/os-release)" || die "$(cat <<-'EO_NOART'

	This script only works on Artix Linux. Please see https://sonicde.org for SonicDE
	packages suitable for other distributions and operating systems. Aborting.
EO_NOART
)"

yesno "\nAre you ready to switch to SonicDE?" || exit 0


# Main

_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}"/sonic-switch.XXXXXXXX)"
cd "$_WORKDIR" || die "\nCouldn't change into workdir ${_WORKDIR}."

set +e
$SUDO_CMD pacman-key -l "$PGP_KEY" >/dev/null 2>pacman-key.err
if [ "$(cat pacman-key.err)" ] ; then
	set -e
	msg '\nImporting the SonicDE for Artix Linux package signing key:'
	$DL_CMD https://sonicde-artix.github.io/sonicde-artixlinux.asc
	sudo pacman-key --add sonicde-artixlinux.asc
	sudo pacman-key --finger "$PGP_KEY"
	yesno "$(cat <<-EO_FPM
		Please compare the key fingerprint to the one at $ORIG_URL.
		Does it look right?
EO_FPM
)" || die '\nWrong fingerprint. Aborting.'
	sudo pacman-key --lsign-key "$PGP_KEY"
fi

set +e
RES="$(grep '^\[sonicde\]' /etc/pacman.conf)"
if [ "$RES" ] ; then
	RES="$(printf '%s' "$OLD_URLS" | grep -Ff - /etc/pacman.conf)"
	test "$RES" && die "$(cat <<-EO_DUPREPO

		There are old [sonicde] repository URLs in your \`/etc/pacman.conf\`.
		Please replace any of these:
		$(printf '%s' "$OLD_URLS" | sed 's/^/Server = /g')
		with:
		Server = $REPO_URL
EO_DUPREPO
)"
else
	set -e
	msg '\nAdding the SonicDE repository to your `/etc/pacman.conf`:'
	$SUDO_CMD tee -a /etc/pacman.conf <<-EO_REPO

	[sonicde]
	Server = $REPO_URL
EO_REPO
fi
set -e


msg '\nUpdating your packages:'
$SUDO_CMD pacman -Syyu

msg "$(cat <<-'EO_INST'

	Installing SonicDE. If you''re being asked to remove any KDE packages in favor
	of the SonicDE ones, please press ''y'' for yes.

EO_INST
)"
$SUDO_CMD pacman -S --needed sonicde-meta


## Login Manager Replacement

set +e
_RE="$(printf '%s' "$KNOWN_LMS" | tr ' ' '|')"
LM_NAME="$(ps -A -o comm= | grep -E "^(${_RE})$")"

test "$LM_NAME" = 'soniclogin' && thank_you
yesno "$(cat <<-EO_LMSW

	You're currently using the \`$LM_NAME\` login manager. Do you want to switch to the
	Sonic Login Manager?
EO_LMSW
)" || thank_you

set -e

$SUDO_CMD pacman -S --needed --noconfirm sonic-login-manager

INIT_NAME="$(ps -p 1 -o comm=)"
test "$INIT_NAME" = 'init' && INIT_NAME='openrc'
test "$INIT_NAME" = 's6-svscan' && INIT_NAME='s6'


case "$INIT_NAME" in
	dinit)
		SWITCH_CMD="$(cat <<-EO_DINTPL
			dinitctl stop "$LM_NAME"
			dinitctl disable "$LM_NAME"
			yes | pacman -S --needed "sonic-login-manager-${INIT_NAME}"
			dinitctl enable soniclogin
			dinitctl start soniclogin
EO_DINTPL
		)" ;;
	openrc)
		SWITCH_CMD="$(cat <<-EO_ORCTPL
			rc-service "$LM_NAME" stop
			rc-update del "$LM_NAME" default
			yes | pacman -S --needed "sonic-login-manager-${INIT_NAME}"
			rc-update add soniclogin default
			rc-service soniclogin start
EO_ORCTPL
		)" ;;
	runit)
		SWITCH_CMD="$(cat <<-EO_RUNTPL
			sv stop "$LM_NAME"
			rm /run/runit/service/"$LM_NAME"
			yes | pacman -S --needed "sonic-login-manager-${INIT_NAME}"
			ln -s /etc/runit/sv/soniclogin /run/runit/service/
			sv start soniclogin
EO_RUNTPL
		)" ;;

	s6)
		SWITCH_CMD="$(cat <<-EO_S6TPL
			s6-rc stop "$LM_NAME"
			s6 set disable "$LM_NAME"
			yes | pacman -S --needed "sonic-login-manager-${INIT_NAME}"
			s6 set enable soniclogin
			s6-rc start soniclogin
			s6 set commit && s6 live install
EO_S6TPL
		)" ;;
	*) die "Unknown init: ${INIT_NAME}. Aborting." ;;
esac

msg "$THANKS_MSG"
msg '\nSwitching to the Sonic Login Manager (soniclogin) in 3 seconds.'
msg "You can find a log at ${_WORKDIR}/nohup.out."
sleep 3

nohup $SUDO_CMD sh -c "$SWITCH_CMD"
