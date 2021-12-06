#! /bin/bash
# shellcheck shell=bash

set -u

## @@BEGIN@@

YA_INSTALLER_VARIANT=provider
YA_INSTALLER_CORE="${YA_INSTALLER_CORE:-v0.4.1}"

## @@END@@

YA_INSTALLER_WASI=${YA_INSTALLER_WASI:-v0.2.2}
YA_INSTALLER_VM=${YA_INSTALLER_VM:-v0.2.9}

version_name() {
	local name

	name=${1#pre-rel-}
	printf "%s" "${name#v}"
}

say() {
    printf 'golem-installer: %s\n' "$1"
}

err() {
    say "$1" >&2
    exit 1
}

need_cmd() {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}

check_cmd() {
    command -v "$1" > /dev/null 2>&1
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
        wget --https-only "$1" -O "$2"
    else
        err "Unknown downloader"   # should not reach here
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
    for _path in $PATH
    do
        if [ "$_path" = "$_required" ]; then
            IFS="$_save_ifs"
            return
        fi
    done
    IFS="$_save_ifs"

    case "${SHELL:-/bin/sh}" in
      */bash) _rcfile=".bashrc" ;;
      */zsh) _rcfile=".zshrc" ;;
      *) _rcfile=".profile"
        ;;
    esac

    say "" >&2
    say "Add $_required to your path" >&2
    say 'HINT:   echo '\''export PATH="$HOME/.local/bin:$PATH"'\'" >> ~/${_rcfile}" >&2
    say "Update your current terminal." >&2
    say 'HINT:   export PATH="$HOME/.local/bin:$PATH"' >&2
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

check_provider_terms_of_use() {
    local _dir="$YA_INSTALLER_DATA/terms"

    cat <<EOF >&2

By installing & running this software you declare that you have read, understood and hereby accept the disclaimers and
privacy warnings found at
  https://handbook.golem.network/see-also/terms
and
  https://handbook.golem.network/see-also/provider-subsidy-terms

EOF
    check_terms_accepted "$YA_INSTALLER_DATA/terms" "testnet-01.tag" "subsidy-01.tag"
}

check_terms_accepted() {
    local _tagdir="$1"
    local _tags=${@:2}

    files_exist "$_tagdir" $_tags && return
    while ! files_exist "$_tagdir" $_tags; do
        read -r -u 2 -p "Do you accept the terms and conditions? [yes/no]: " ANS || exit 1
        if [ "$ANS" = "yes" ]; then
            mkdir -p "$_tagdir"
            for _tag in $_tags; do
                touch "$_tagdir/$_tag"
            done
        elif [ "$ANS" = "no" ]; then
            exit 1
        else
            say "wrong answer: '$ANS'"
        fi
    done
}

files_exist() {
    for _file in ${@:2}; do
        test ! -f "$1/$_file" && return 1
    done
    return 0
}

detect_dist() {
    local _ostype _cputype

    _ostype="$(uname -s)"
    _cputype="$(uname -m)"

    if [ "$_ostype" = Darwin ] && [ "$_cputype" = i386 ]; then
        # Darwin `uname -m` lies
        if sysctl hw.optional.x86_64 | grep -q ': 1'; then
            _cputype=x86_64
        fi
    fi

    case "$_cputype" in
        x86_64 | x86-64 | x64 | amd64)
            _cputype=x86_64
            ;;
        *)
            err "invalid cputype: $_cputype"
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
    (downloader "$_url" - | tar -C "$YA_INSTALLER_DATA/bundles" -xz -f - ) || return 1
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


install_bins() {
    local _bin _dest _ln

    _dest="$2"
    if [ "$_dest" = "/usr/bin" ] || [ "$_dest" = "/usr/local/bin" ]; then
      _ln="cp"
      test -w "$_dest" || {
        _ln="sudo cp"
        say "to install to $_dest, root priviliges required"
      }
    else
      _ln="ln -sf"
    fi

    for _bin in "$1"/*
    do
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

main() {
    local _ostype _src_core _bin _src_wasi _src_vm

    downloader --check
    need_cmd uname
    need_cmd chmod
    need_cmd mkdir
    need_cmd rm
    need_cmd rmdir

    if [ "$YA_INSTALLER_VARIANT" = "provider" ]; then
      check_provider_terms_of_use
    else
      check_terms_of_use
    fi

    say "installing to $YA_INSTALLER_BIN"

    test -d "$YA_INSTALLER_BIN" || mkdir -p "$YA_INSTALLER_BIN"

    _ostype="$(detect_dist)"

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
        RUST_LOG=error "$_src_core/golemsp" setup <&2
      )
    fi

    ensurepath "$YA_INSTALLER_BIN"
}

main "$@" || exit 1
