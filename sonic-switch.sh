#!/bin/sh

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 SonicDE Community

# shellcheck disable=SC2009,SC2016,SC2059,SC2086

set -eu


# Constants

VER='0.8.0'
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
LOG=$HOME/sonic-switch.log
NUL=/dev/null

DISTRO_TYPE='Artix Linux'
OS_RELEASE_RE="^ID=['\"]*artix['\"]*$"


# Messages

CHOOSE_BINPKG_REPO_MSG='Please select the SonicDE repository you want to use:'
FPRINT_MSG='Please compare the key fingerprint to the one at %s. Does it look right?'
INTRO_MSG='SonicDE.org sonic-switch.sh, version: %s.

This script will install SonicDE on your system. It will restart your graphical session so please save all your work. It will also replace any conflicting KDE components with the SonicDE equivalents.
'
INSTALL_MSG='The installation of the SonicDE packages will start in %d seconds. It''s running in the background to continue in case your GUI session is getting terminated. You can find an installation log at %s.'
LM_SWITCH_MSG='You''re currently using the `%s` login manager. SonicDE comes with the Sonic Login Manager which is highly recommended when migrating from Wayland-based setups. Do you want to switch to the Sonic Login Manager?'
THANKS_MSG='Thank you for choosing SonicDE! Please see %s for any further information.'


# Errors

NO_CURL_WGET_ERR='No ''curl'' or ''wget'' command found. Please install one of them.'
NO_DOAS_SUDO_ERR='No ''doas'' or ''sudo'' command found. Please install one of them.'
DISTRO_ERR='This script only works on %s systems. Please see https://sonicde.org for SonicDE packages suitable for other distributions and operating systems. Aborting.'
WRONG_FPRINT_ERR='Wrong fingerprint. Aborting.'


# Functions

chooserepo() {
	printf '%s\n' "$1"
	printf '%s\n' "$2" | cut -d '|' -f 1 | grep -n '.*' | sed 's/:/) /g'
	_max=$(printf '%s\n' "$2" | wc -l)
	printf '0:exit script\n'
	while :; do
		IFS= read -r _choice || die 1 'Input closed.'
		test "$_choice" = 0 && die 1 'Exiting.'
		case $_choice in
			''|*[!0-9]*) continue ;;
			*) : ;;
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

svstart() {
	case "$1" in
		dinit) $2 dinitctl start "$3" ;;
		openrc) $2 rc-service "$3" start ;;
		runit) $2 sv start "$3" ;;
		s6) $2 s6-rc start "$3" ;;
	esac
}

svstopstr() {
	case "$1" in
		dinit) _cmd="dinitctl stop '$2'" ;;
		openrc) _cmd="rc-service '$2' stop" ;;
		runit) _cmd="sv stop '$2'" ;;
		s6) _cmd="s6-rc stop '$2'" ;;
	esac
	printf '%s\n' "$_cmd"
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

packey="$sudo pacman-key"
pacinst="$sudo pacman --sync --needed"
pkgs='sonicde-meta'
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
if [ -z "$lmname" ] ; then
	msg 'Couldn''t identify your login manager. Keeping it.'
elif [ "$lmname" != soniclogin ] && yesno "$LM_SWITCH_MSG" "$lmname" ; then
	slminst=1
fi

msg 'Updating your system:'
$pacinst --refresh --sysupgrade --noconfirm

msg 'Installing the dependencies of SonicDE:'
$pacinst --print --print-format '%r %n' $pkgs > deps
while read -r repo pkg; do
	test "$repo" = "$dbname" && continue
	extdeps="${extdeps:-} ${pkg}"
done < deps
test -n "${extdeps:-}" && $pacinst --asdeps --noconfirm $extdeps

msg 'Downloading the SonicDE packages:'
yes | $pacinst --downloadonly $pkgs

msg 'Assembling the installation script'
printf 'set -eu; exec >> ''%s'' 2>&1; sleep 3
	yes | pacman --sync --needed %s\n' "$LOG" "$pkgs" > install.sh
init=$(findinit)
if [ "$slminst" = 1 ] ; then
	test "$init" = dinit && cat >> install.sh <<-DINIT
		dinitctl stop '$lmname'
		dinitctl disable '$lmname'
		yes | pacman -S --needed 'sonic-login-manager-$init'
		dinitctl enable soniclogin
		dinitctl start soniclogin
	DINIT
	test "$init" = openrc && cat >> install.sh <<-OPENRC
		rc-service '$lmname' stop
		rc-update del '$lmname' default
		yes | pacman -S --needed 'sonic-login-manager-$init'
		rc-update add soniclogin default
		rc-service soniclogin start
	OPENRC
	test "$init" = runit && cat >> install.sh <<-RUNIT
		sv stop '$lmname'
		rm /run/runit/service/'$lmname'
		yes | pacman -S --needed 'sonic-login-manager-$init'
		ln -s /etc/runit/sv/soniclogin /run/runit/service/
		sv start soniclogin
	RUNIT
	test "$init" = s6 && cat >> install.sh <<-S6
		s6-rc stop '$lmname'
		s6 set disable '$lmname'
		yes | pacman -S --needed 'sonic-login-manager-$init'
		s6 set enable soniclogin
		s6-rc start soniclogin
		s6 set commit && s6 live install
	S6
fi
chmod a+x install.sh

msg 'Initializing the job scheduler'
deinst=
if ! pacman -Q at >$NUL ; then
	yes | $pacinst at at-$init
	deinst="yes | pacman -Rns at at-$init"
fi
if ! ps -eo comm | grep -q '^atd$' ; then
	svstart "$init" "$sudo" atd
	svstopstr "$init" atd >> install.sh
fi
printf '%s\n' "$deinst" >> install.sh

msg "$INSTALL_MSG" 3 "$LOG"
msg "$THANKS_MSG" "$HOMEPAGE"

: > "$LOG"
$sudo at -f "$(pwd)"/install.sh now
tail -f "$LOG"
