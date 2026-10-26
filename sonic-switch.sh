#!/bin/sh

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 SonicDE Community

# shellcheck disable=SC2009,SC2016,SC2059,SC2086

set -eu


# Constants

VER='0.9.0'
HOMEPAGE='https://sonicde.org'
REPO_HOMEPAGE='https://sonicde-artix.github.io'

PGP_KEY_ID=72AAA51726BC3C29
PGP_KEY_FILE=sonicde-artixlinux.asc
PGP_KEY_URL="$REPO_HOMEPAGE/$PGP_KEY_FILE"

BINPKG_REPOS="\
stable
stable-testing
beta"
REPO_NAME_TPL='sonicde-%s'
REPO_URL_TPL='https://github.com/sonicde-artix/%s/releases/download/$arch'

KNOWN_LMS='emptty gdm greetd lemurs lightdm lxdm ly plasmalogin sddm slim soniclogin xdm'
NUL=/dev/null

DISTRO_TYPE='Artix Linux'
OS_RELEASE_RE="^ID=['\"]*artix['\"]*$"


# Messages

CHOOSE_BINPKG_REPO_MSG='Please select the SonicDE repository you want to use:'
FPRINT_MSG='Please compare the key fingerprint to the one at %s. Does it look right?'
INTRO_MSG='SonicDE.org sonic-switch.sh, version: %s.

This script will install SonicDE on your system. Please run it from a terminal only! The script will try to automatically replace any conflicting KDE components with the SonicDE equivalents. If that fails, please interactively answer any questions.
'
LM_SWITCH_MSG='SonicDE comes with the Sonic Login Manager which is highly recommended when migrating from Wayland-based setups. Do you want to switch to the Sonic Login Manager?'
THANKS_MSG='Thank you for choosing SonicDE! Please see %s for any further information.'


# Errors

NO_CURL_WGET_ERR='No ''curl'' or ''wget'' command found. Please install one of them.'
NO_DOAS_SUDO_ERR='No ''doas'' or ''sudo'' command found. Please install one of them.'
DISTRO_ERR='This script only works on %s systems. Please see https://sonicde.org for SonicDE packages suitable for other distributions and operating systems. Aborting.'
WRONG_FPRINT_ERR='Wrong fingerprint. Aborting.'


# Functions

chooserepo() {
	printf '%s\n' "$1"
	printf '%s\n' "$2" | cut -d '|' -f 1 | nl -b a -w 1 -s ') '
	printf '0) exit script\n'
	_max=$(printf '%s\n' "$2" | wc -l)
	while :; do
		IFS= read -r _choice || die 1 'Input closed.'
		case $_choice in
			0) die 1 'Exiting.' ;;
			''|*[!0-9]*) continue ;;
		esac
		test $_choice -gt 0 -a $_choice -le $_max && break
	done
	printf '%s\n' "$2" | cut -d '|' -f 1 | sed -n "$_choice"p > repo
}

findinit() {
	_init=$(ps -p 1 -o comm=)
	test "$_init" = 'init' && _init='openrc'
	test "$_init" = 's6-svscan' && _init='s6'
	printf '%s\n' "$_init"
}

findloginman() {
	_regex=$(printf '%s' "$KNOWN_LMS" | tr ' ' '|')
	ps -A -o comm= | grep -E "^(${_regex})$" | head -n 1 || :
}

msg() {
	fstring=$1; shift
	printf "\n$fstring\n" "$@"
}

svenable() {
	case "$1" in
		dinit) $2 dinitctl enable "$3" ;;
		openrc) $2 rc-update add "$3" default ;;
		runit) $2 ln -s /etc/runit/sv/$3 /run/runit/service/ ;;
		s6) $2 s6 set enable $3 && $2 s6 set commit && $2 s6 live install ;;
	esac
}

svdisable() {
	case "$1" in
		dinit) $2 dinitctl disable "$3" ;;
		openrc) $2 rc-update del "$3" default ;;
		runit) $2 rm /run/runit/service/$3 ;;
		s6) $2 s6 set disable $3 ;;
	esac
}

svstart() {
	case "$1" in
		dinit) $2 dinitctl start "$3" ;;
		openrc) $2 rc-service "$3" start ;;
		runit) $2 sv start "$3" ;;
		s6) $2 s6-rc start "$3" ;;
	esac
}

svstop() {
	case "$1" in
		dinit) $2 dinitctl stop "$3" ;;
		openrc) $2 rc-service "$3" stop ;;
		runit) $2 sv stop "$3" ;;
		s6) $2 s6-rc stop "$3" ;;
	esac
}

yesno() {
	fstring=$1; shift
	printf "$fstring (y/n): " "$@"
	read -r _answer
	test "$_answer" = 'y' -o "$_answer" = 'Y' && return 0
}

die() {
	rc=$1; fstring=$2; shift 2
	printf "\n$fstring\n" "$@"; exit "$rc"
}


# Intro and Prechecks

msg "$INTRO_MSG" "$VER"

command -v curl >$NUL && fetch='curl --fail --location --remote-name'
command -v wget >$NUL && fetch='wget --no-clobber'
test -n "${fetch:-}" || die 1 "$NO_CURL_WGET_ERR"

sudo=$(command -v sudo || command -v doas) || die 1 "$NO_DOAS_SUDO_ERR"
grep -Eq "$OS_RELEASE_RE" /etc/os-release || die 1 "$DISTRO_ERR" "$DISTRO_TYPE"

init=$(findinit)

packey="$sudo pacman-key"
pacinst="$sudo pacman --sync --needed"
pkgs="sonicde-meta-$init"
slminst=

if pacman -Qi $pkgs >$NUL 2>&1 ; then
	msg 'Found an installation of SonicDE. Goood!'
	die 0 "$THANKS_MSG" "$HOMEPAGE"
fi

yesno 'Are you ready to switch to SonicDE?' || exit 0


# Main

cd "$(mktemp -d)"

if ! $packey -l "$PGP_KEY_ID" >$NUL 2>&1 ; then
	msg 'Importing the package signing key:'
	$fetch "$PGP_KEY_URL"
	$packey --add "$PGP_KEY_FILE"
	$packey --finger "$PGP_KEY_ID"
	yesno "$FPRINT_MSG" "$REPO_HOMEPAGE" || die 1 "$WRONG_FPRINT_ERR"
	$packey --lsign-key "$PGP_KEY_ID"
fi

dbname=$(sed -En 's/^\[(sonicde.*)\]/\1/p' /etc/pacman.conf)
if [ -z "$dbname" ] ; then
	chooserepo "$CHOOSE_BINPKG_REPO_MSG" "$BINPKG_REPOS"
	dbname=$(printf "$REPO_NAME_TPL" "$(cat repo)")
	repourl=$(printf "$REPO_URL_TPL" "$(cat repo)")
	msg 'Adding the SonicDE repository to your ''/etc/pacman.conf'':'
	$sudo tee -a /etc/pacman.conf <<-EO_REPO

		[$dbname]
		Server = $repourl
	EO_REPO
fi

msg 'Analyzing your login manager setup'
lmname=$(findloginman)
if [ "$lmname" != soniclogin ] && yesno "$LM_SWITCH_MSG" "$lmname" ; then
	slminst=1
fi

msg 'Installing SonicDE'
yes | $pacinst --refresh --sysupgrade --noconfirm "$pkgs" 2>$NUL ||
	$pacinst --refresh --sysupgrade "$pkgs"

if [ "$slminst" = 1 ] ; then
	svstop "$init" "$sudo" "$lmname" || :
	svdisable "$init" "$sudo" "$lmname" || :
	yes | $pacinst sonic-login-manager-$init
	svstart "$init" "$sudo" soniclogin
	svenable "$init" "$sudo" soniclogin
fi
