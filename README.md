![SonicDE on Artix Linux](./docs/img/screenshot.jpg)

# SonicDE Packages for Artix Linux Systems

This third-party repository provides [SonicDE](https://sonicde.org) x86_64 binary  packages for [Artix Linux](https://artixlinux.org). SonicDE, or the Sonic Desktop Environment, aims to preserve and improve the X11-specific aspects of KDE. You can learn more about SonicDE at [sonicde.org](https://sonicde.org/).

## Installing SonicDE Manually

### Adding the Public Package Signing Key to pacman

First, please download the public OpenPGP signing key [`sonicde-artixlinux.asc`](https://sonicde-artix.github.io/sonicde-artixlinux.asc) used to sign the packages and add it to the pacman keyring:

```shell
curl -O https://sonicde-artix.github.io/sonicde-artixlinux.asc
sudo pacman-key --add sonicde-artixlinux.asc
sudo pacman-key --finger 72AAA51726BC3C29
sudo pacman-key --lsign-key 72AAA51726BC3C29
```
You can read more about package signing on the [pacman/Package signing - ArchWiki](https://wiki.archlinux.org/title/Pacman/Package_signing#Adding_unofficial_keys) page.

### Adding the Repository to Pacman

Once you added the public key, also add an entry for the SonicDE repository to the end of the file `/etc/pacman.conf`:

```shell
sudo tee -a /etc/pacman.conf <<'EOF'
[sonicde]
Server = https://sonicde-artix.github.io/$arch
EOF
```

Run `pacman` to update all package indexes and installed packages:

```shell
sudo pacman -Syyu
```

### Installing SonicDE

Installing SonicDE is as easy as installing the `sonicde-meta` package:

```shell
sudo pacman -S sonicde-meta
```

The included packages will replace any of their installed KDE counterparts. When asked, just answer with `y `. To make use of SonicDE, log out of your desktop session and log in again.

In case you get kicked out of a running KDE session while you're installing SonicDE, just re-run `pacman` after you logged in again and let it install the missing packages:

```shell
sudo pacman -S sonicde-meta
```

When done, start the program `System Settings` and verify that you're running SonicDE on the "About this System" page. You do? Congratulations!

## Migrating From Older Repositories

There are, or rather were, two older repositories containing SonicDE third-party packages for Artix Linux. These could be found at the following addresses:

* https://artixlinux.duckdns.org/repos/sonicde
* https://x11libre.net/repo/arch_based/x86_64/sonicde

Please note that the packages at these locations are no longer being updated. You can migrate to our repository by importing our PGP key as described above in "Adding the Public Package Signing Key to pacman" and then running `pacman -Syu`.

## Getting in Contact

Please report any enhancement requests or issues with this repository at [Issues · sonicde-artix/sonicde-artix](https://github.com/sonicde-artix/sonicde-artix/issues). If you have a specific issue, please see the [list of package repositories](https://github.com/orgs/sonicde-artix/repositories?q=topic%3Apackage) and report it there. In case you need help, want to report success, or talk about other aspects, please also check the official SonicDE channels.

<img src="./docs/icons/bluesky.svg">&nbsp;[Bluesky](https://bsky.app/profile/sonicdesktop.bsky.social)&nbsp; <img src="./docs/icons/discord.svg">&nbsp;[Discord](https://discord.gg/cNZMQ62u5S) &nbsp; <img src="./docs/icons/mastodon.svg">&nbsp;[Mastodon](https://mastodon.social/@sonicdesktop) &nbsp; <img src="./docs/icons/matrix.svg">&nbsp;[Matrix](https://matrix.to/#/#sonicdesktop:matrix.org) &nbsp; <img src="./docs/icons/oftc.svg">&nbsp;[OFTC IRC](https://webchat.oftc.net/?channels=sonicde%2Csonicde-devel%2Csonicde-dist&uio=MT11bmRlZmluZWQb1) &nbsp; <img src="./docs/icons/telegram.svg">&nbsp;[Telegram](https://t.me/sonic_de) &nbsp; <img src="./docs/icons/x.svg">&nbsp;[X (Twitter)](https://x.com/SonicDesktop)


