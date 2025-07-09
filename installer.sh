#! /bin/bash
# shellcheck shell=bash

set -eu

GOLEM_ACCEPT_TOS="${GOLEM_ACCEPT_TOS:-no}"
BATCH_MODE="${BATCH_MODE:-no}"

## @@BEGIN_SELECT_VERSION@@

YA_INSTALLER_VARIANT=provider
YA_INSTALLER_CORE="${YA_INSTALLER_CORE:-v0.4.1}"

## @@END_SELECT_VERSION@@

YA_INSTALLER_WASI=${YA_INSTALLER_WASI:-v0.2.2}
YA_INSTALLER_VM=${YA_INSTALLER_VM:-v0.4.2}

version_name() {
    local name

    name=${1#pre-rel-}
    printf "%s" "${name#v}"
}

say() {
    printf 'golem-installer: %s\n' "$1"
}

err() {
    echo -e "\033[1;31m$1\033[0m" >&2
    exit 1
}

need_cmd() {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

assert_nz() {
    if [ -z "$1" ]; then err "assert_nz $2"; fi
}

downloader() {
    local _dld
    if check_cmd curl; then
        _dld=curl
    elif check_cmd wget; then
        _dld=wget
    else
        _dld='curl or wget' # to be used in error message of need_cmd
    fi

    if [ "$1" = --check ]; then
        need_cmd "$_dld"
    elif [ "$_dld" = curl ]; then
        curl --proto '=https' --silent --show-error --fail --location "$1" --output "$2"
    elif [ "$_dld" = wget ]; then
        wget -O "$2" --https-only "$1"
    else
        err "Unknown downloader" # should not reach here
    fi
}

autodetect_bin() {
    local _current_bin

    _current_bin="$(command -v yagna)"

    if [ -z "$_current_bin" ]; then
        echo -n "$HOME/.local/bin"
        return
    fi
    dirname "$_current_bin"
}

ensurepath() {
    local _required _save_ifs _path _rcfile

    _required="$1"
    _save_ifs="$IFS"
    IFS=":"
    for _path in $PATH; do
        if [ "$_path" = "$_required" ]; then
            IFS="$_save_ifs"
            return
        fi
    done
    IFS="$_save_ifs"

    case "${SHELL:-/bin/sh}" in
    */bash) _rcfile=".bashrc" ;;
    */zsh) _rcfile=".zshrc" ;;
    *)
        _rcfile=".profile"
        ;;
    esac

    echo -e "\e[1;31m\n[ATTENTION REQUIRED]\e[0m"
    echo -e "\e[1;34mTo ensure your system can find the Golem binaries, please include '$_required' within your path, by following the instructions below.\e[0m"
    echo -e "\e[1;33m1. Add the path to your configuration file:\e[0m"
    echo -e "\e[0;32m   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/${_rcfile}\e[0m"
    echo -e "\e[1;33m2. Apply the changes in your current terminal:\e[0m"
    echo -e "\e[0;32m   export PATH=\"\$HOME/.local/bin:\$PATH\"\e[0m"

    exit 1
}

YA_INSTALLER_DATA=${YA_INSTALLER_DATA:-$HOME/.local/share/ya-installer}
YA_INSTALLER_BIN=${YA_INSTALLER_BIN:-$(autodetect_bin)}
YA_INSTALLER_LIB=${YA_INSTALLER_LIB:-$HOME/.local/lib/yagna}

check_terms_of_use() {
    cat <<EOF >&2

By installing & running this software you declare that you have read, understood and hereby accept the disclaimer and
privacy warning found at https://handbook.golem.network/see-also/terms

EOF
    check_terms_accepted "$YA_INSTALLER_DATA/terms" "testnet-01.tag"
}

create_tags() {
    local _dir="$1"
    mkdir -p "$_dir"
    shift
    local _tag
    for _tag in "$@"; do
        touch "${_dir}/${_tag}"
    done
}

check_terms_accepted() {
    local _tagdir="$1"
    shift

    [ "$GOLEM_ACCEPT_TOS" = "yes" ] && create_tags "$_tagdir" "$@"

    files_exist "$_tagdir" "$@" && return
    local _read_opts="-r -u 2"
    [ "${BASH_VERSION:-no}" = "no" ] && _read_opts=-r
    while ! files_exist "$_tagdir" "$@"; do
        # shellcheck disable=SC2162,SC2229
        read ${_read_opts} -p "Do you accept the terms and conditions? [yes/no]: " ANS || exit 1
        if [ "$ANS" = "yes" ]; then
            create_tags "$_tagdir" "$@"
        elif [ "$ANS" = "no" ]; then
            exit 1
        else
            say "wrong answer: '$ANS'"
        fi
    done
}

files_exist() {
    local dir=$1
    shift
    for _file in "$@"; do
        test ! -f "$dir/$_file" && return 1
    done
    return 0
}

detect_dist() {
    local _ostype _cputype

    _ostype="$(uname -s)"
    _cputype="$(uname -m)"

    if [ "$_ostype" = Darwin ]; then
        if [ "$_cputype" = i386 ]; then
            # Darwin `uname -m` lies
            if sysctl hw.optional.x86_64 | grep -q ': 1'; then
                _cputype=x86_64
            fi
        fi

        case "$_cputype" in arm64 | aarch64)
            if [ "$YA_INSTALLER_VARIANT" = "provider" ]; then
                err "We do not support running a provider on ARM devices yet. Please use an x86_64 machine to install the provider."
            fi
            # On macOS M1 we want to run x86 binaries using Rosetta,
            # because we don't have compatible ARM builds.
            _cputype=x86_64
            ;;
        esac

    fi

    case "$_cputype" in
    x86_64 | x86-64 | x64 | amd64)
        _cputype=x86_64
        ;;
    *)
        if [ "$YA_INSTALLER_VARIANT" = "provider" ]; then
            err "We do not support running a provider on ARM devices yet. Please use an x86_64 machine to install the provider."
        fi
        ;;
    esac
    case "$_ostype" in
    Linux)
        _ostype=linux
        ;;
    Darwin)
        _ostype=osx
        ;;
    MINGW* | MSYS* | CYGWIN*)
        _ostype=windows
        ;;
    *)
        err "invalid os type: $_ostype"
        ;;
    esac
    echo -n "$_ostype"
}

_dl_head() {
    local _sep
    _sep="-----"
    _sep="$_sep$_sep$_sep$_sep"
    printf "%-20s %25s\n" " Component " " Version" >&2
    printf "%-20s %25s\n" "-----------" "$_sep" >&2
}

_dl_start() {
    printf "%-20s %25s " "$1" "$(version_name "$2")" >&2
}

_dl_end() {
    printf "[done]\n" >&2
}

download_core() {
    local _ostype _variant _url

    _ostype="$1"
    _variant="$2"
    mkdir -p "$YA_INSTALLER_DATA/bundles"

    _url="https://github.com/golemfactory/yagna/releases/download/${YA_INSTALLER_CORE}/golem-${_variant}-${_ostype}-${YA_INSTALLER_CORE}.tar.gz"
    _dl_start "golem core" "$YA_INSTALLER_CORE"
    (downloader "$_url" - | tar -C "$YA_INSTALLER_DATA/bundles" -xz -f -) || return 1
    _dl_end
    echo -n "$YA_INSTALLER_DATA/bundles/golem-${_variant}-${_ostype}-${YA_INSTALLER_CORE}"
}

#
download_wasi() {
    local _ostype _url

    _ostype="$1"
    test -d "$YA_INSTALLER_DATA/bundles" || mkdir -p "$YA_INSTALLER_DATA/bundles"

    _url="https://github.com/golemfactory/ya-runtime-wasi/releases/download/${YA_INSTALLER_WASI}/ya-runtime-wasi-${_ostype}-${YA_INSTALLER_WASI}.tar.gz"
    _dl_start "wasi runtime" "$YA_INSTALLER_WASI"
    downloader "$_url" - | tar -C "$YA_INSTALLER_DATA/bundles" -xz -f -
    _dl_end
    echo -n "$YA_INSTALLER_DATA/bundles/ya-runtime-wasi-${_ostype}-${YA_INSTALLER_WASI}"
}

download_vm() {
    local _ostype _url

    _ostype="$1"
    test -d "$YA_INSTALLER_DATA/bundles" || mkdir -p "$YA_INSTALLER_DATA/bundles"

    _url="https://github.com/golemfactory/ya-runtime-vm/releases/download/${YA_INSTALLER_VM}/ya-runtime-vm-${_ostype}-${YA_INSTALLER_VM}.tar.gz"
    _dl_start "vm runtime" "$YA_INSTALLER_VM"
    (downloader "$_url" - | tar -C "$YA_INSTALLER_DATA/bundles" -xz -f -) || err "failed to download $_url"
    _dl_end
    echo -n "$YA_INSTALLER_DATA/bundles/ya-runtime-vm-${_ostype}-${YA_INSTALLER_VM}"
}

download_resources() {
    local _resources_dir _url
    _resources_dir="$(mktemp -d /tmp/ya_installer_resources.XXXXXX)"
    _url="https://github.com/golemfactory/ya-installer-resources/releases/latest/download/resources.tar.gz"
    _dl_start "Downloading certificates and whitelists" ""
    (downloader "$_url" - | tar -C "$_resources_dir" -xz -f -) || err "failed to download $_url"
    [[ -d "$_resources_dir/certs" ]] || mkdir "$_resources_dir/certs"
    _dl_end
    echo -n "$_resources_dir"
}

install_bins() {
    local _bin _dest _ln

    _dest="$2"
    if [ "$_dest" = "/usr/bin" ] || [ "$_dest" = "/usr/local/bin" ]; then
        _ln="cp"
        test -w "$_dest" || {
            _ln="sudo cp"
            say "to install to $_dest, root privileges required"
        }
    else
        _ln="ln -sf"
    fi

    for _bin in "$1"/*; do
        if [ -f "$_bin" ] && [ -x "$_bin" ]; then
            #echo -- $_ln -- "$_bin" "$_dest"
            $_ln -- "$_bin" "$_dest"
        fi
    done
}

install_plugins() {
    local _src _dst

    _src="$1"
    _dst="$2/plugins"
    mkdir -p "$_dst"

    (cd "$_src" && cp -r ./* "$_dst")
}

setup_provider() {
local _bin_dir _resources_dir
_bin_dir="$1"
_resources_dir=$(download_resources) || exit 1

## @@BEGIN_SETUP_PROVIDER@@
## @@END_SETUP_PROVIDER@@

rm -rf "$_resources_dir"
}

main() {
    local _ostype _src_core _bin _src_wasi _src_vm

    _ostype="$(detect_dist)" || exit 1
    downloader --check
    need_cmd uname
    need_cmd chmod
    need_cmd mkdir
    need_cmd rm
    need_cmd rmdir

    check_terms_of_use

    say "installing to $YA_INSTALLER_BIN"

    test -d "$YA_INSTALLER_BIN" || mkdir -p "$YA_INSTALLER_BIN"

    _dl_head
    _src_core=$(download_core "$_ostype" "$YA_INSTALLER_VARIANT") || return 1
    if [ "$YA_INSTALLER_VARIANT" = "provider" ]; then
        _src_wasi=$(download_wasi "$_ostype")
        if [ "$_ostype" = "linux" ]; then
            _src_vm=$(download_vm "$_ostype") || exit 1

        fi
    fi

    install_bins "$_src_core" "$YA_INSTALLER_BIN"
    if [ "$YA_INSTALLER_VARIANT" = "provider" ]; then
        install_plugins "$_src_core/plugins" "$YA_INSTALLER_LIB"
        # Cleanup core plugins to make ya-provider use ~/.local/lib/yagna/plugins
        rm -rf "$_src_core/plugins"
        install_plugins "$_src_wasi" "$YA_INSTALLER_LIB"
        test -n "$_src_vm" && install_plugins "$_src_vm" "$YA_INSTALLER_LIB"
        (
            PATH="$YA_INSTALLER_BIN:$PATH"
            if test "${BATCH_MODE}" = "no"; then
                RUST_LOG=error "$_src_core/golemsp" setup <&2 || exit 1
            fi
            setup_provider "$_src_core"
        )
    fi

    ensurepath "$YA_INSTALLER_BIN"

#golemsp-systemd-updater.sh
#v1.05
#installs or updates golemsp.service file in systemd to allow for prefered golemsp state to persist across system reboots
#
#

if [ ! -f "$HOME/.local/bin/golemsp" ]; then
     echo " "
     echo -e "\033[0;91mError -  GolemSP binary not found\033[0m"
     echo -e "\033[0;91mError -  Systemd Service Failed Install\033[0m"
     echo " "
     echo " "
else
  if [ ! -f "/usr/bin/systemctl" ]; then
    echo " "
    echo -e "\033[0;91mSystemd not found, GolemSP service not installed.\033[0m"
    echo " "
  else
   echo " "
   echo " "
   echo "Install or Update GolemSP systemd service? [y|n] press enter for [yes]"
   echo " "
   read -rsn1 yn
    if [[ ! ${yn} = [Nn]* ]]; then
#delete old golemsp.service here
	  if [[ -f "/etc/systemd/system/golemsp.service" ]]; then
			sudo systemctl disable golemsp
			sudo rm /etc/systemd/system/golemsp.service
#script terminates to early in this case....
      fi   
#User is added to kvm group, without it service will not start without user login.
      sudo usermod -a -G kvm $USER
#writes the service
      sudo bash -c "cat << 'EOF' > /usr/lib/systemd/system/golemsp.service

#Installed by golemsp-systemd.updater.sh v1.05
[Unit]
 Description=Start GolemSP
 After=network-online.target
#Makes sure GolemSP isn't started before KVM
 Requires=open-vm-tools.service
 After=open-vm-tools.service


[Service]
 Type=simple
 Restart=on-failure
#Default RestartSec is 100ms and can take up measurable system resources
 RestartSec=900
#Keeps service from timing out.
 TimeoutSec=600
 User=$USER
 ExecStart=$HOME/.local/bin/golemsp run
 Environment=PATH=$HOME/.local/bin/
 #KillSignal=SIGINT sends keyboard ctrl+c to active golemsp session for a graceful shutdown.
 KillSignal=SIGINT

[Install]
  WantedBy=multi-user.target
EOF"

                 sudo systemctl daemon-reload
                 sudo systemctl enable golemsp
                   echo " "
                   echo -e "\033[0;32mSystemd Service successfuly installed for GolemSP.\033[0m"
                   echo " "
                   echo "You can now enable or disable GolemSP on system startup using command."
                   echo " "
                   echo "       systemctl [enable|disable] golemsp"
                   echo " "
                   echo " "
                   echo " "
                   echo "Start or stop the golemsp service for the current session using command."
                   echo " "
                   echo "       systemctl [start|stop] golemsp"
                   echo " "
                   echo " "
                   echo " "
                   echo "More useful commands."
                   echo " "
                   echo "       systemctl --help"
                   echo " "
                   echo "       golemsp --help"
                   echo " "
                   echo "       journalctl -u golemsp --lines=20 --follow"
                   echo " "
                   echo " "
				   
	
	fi
	
     
  
  fi
fi
#golemsp-systemd-updater.sh end
}

main "$@" || exit 1
