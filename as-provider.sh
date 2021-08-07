#! /bin/bash
# shellcheck shell=bash

set -u

YA_INSTALLER_VARIANT=provider
YA_INSTALLER_CORE="${YA_INSTALLER_CORE:-v0.7.3}"

YA_INSTALLER_WASI=${YA_INSTALLER_WASI:-0.2.2}
YA_INSTALLER_VM=${YA_INSTALLER_VM:-0.2.8}

version_name() {
	local name

	name=${1#pre-rel-}
}

need_cmd() {
    if ! check_cmd "$1"; then
        exit 1
    fi
}

check_cmd() {
    command -v "$1" > /dev/null 2>&1
}

assert_nz() {
    if [ -z "$1" ]; then exit 1; fi
}

downloader() {
    local _dld
    _dld=wget

    if [ "$1" = --check ]; then
        need_cmd "$_dld"
    elif [ "$_dld" = wget ]; then
        wget -q --https-only "$1" -O "$2"
    else
        exit 1
    fi
}

autodetect_bin() {
    local _current_bin

    _current_bin="$(command -v yagna)"

    if [ -z "$_current_bin" ]; then
        echo -n "/usr/bin"
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

    exit 1
}

YA_INSTALLER_DATA=${YA_INSTALLER_DATA:-/usr/share/ya-installer}
YA_INSTALLER_BIN=${YA_INSTALLER_BIN:-$(autodetect_bin)}
YA_INSTALLER_LIB=${YA_INSTALLER_LIB:-/usr/lib/yagna}

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
            exit 1
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
            exit 1
    esac
    echo -n "$_ostype"
}


download_core() {
    local _ostype _variant _url

    _ostype="$1"
    _variant="$2"
    sudo mkdir -p "$YA_INSTALLER_DATA/bundles"

    _url="https://github.com/golemfactory/yagna/releases/download/${YA_INSTALLER_CORE}/golem-${_variant}-${_ostype}-${YA_INSTALLER_CORE}.tar.gz"
    (downloader "$_url" - | sudo tar -C "$YA_INSTALLER_DATA/bundles" -xz -f - ) || return 1
    echo -n "$YA_INSTALLER_DATA/bundles/golem-${_variant}-${_ostype}-${YA_INSTALLER_CORE}"
}

#
download_wasi() {
    local _ostype _url

    _ostype="$1"
    test -d "$YA_INSTALLER_DATA/bundles" || sudo mkdir -p "$YA_INSTALLER_DATA/bundles"

    _url="https://github.com/golemfactory/ya-runtime-wasi/releases/download/v${YA_INSTALLER_WASI}/ya-runtime-wasi-${_ostype}-v${YA_INSTALLER_WASI}.tar.gz"
    downloader "$_url" - | sudo tar -C "$YA_INSTALLER_DATA/bundles" -xz -f -
    echo -n "$YA_INSTALLER_DATA/bundles/ya-runtime-wasi-${_ostype}-v${YA_INSTALLER_WASI}"
}

download_vm() {
    local _ostype _url

    _ostype="$1"
    test -d "$YA_INSTALLER_DATA/bundles" || sudo mkdir -p "$YA_INSTALLER_DATA/bundles"

    _url="https://github.com/golemfactory/ya-runtime-vm/releases/download/v${YA_INSTALLER_VM}/ya-runtime-vm-${_ostype}-v${YA_INSTALLER_VM}.tar.gz"
    (downloader "$_url" - | sudo tar -C "$YA_INSTALLER_DATA/bundles" -xz -f -) || exit 1
    echo -n "$YA_INSTALLER_DATA/bundles/ya-runtime-vm-${_ostype}-v${YA_INSTALLER_VM}"
}


install_bins() {
    local _bin _dest _ln

    _dest="$2"
    if [ "$_dest" = "/usr/bin" ] || [ "$_dest" = "/usr/local/bin" ]; then
      _ln="cp"
      test -w "$_dest" || {
        _ln="sudo cp"
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
  sudo mkdir -p "$_dst"

  (cd "$_src" && sudo cp -r ./* "$_dst")
}

main() {
    local _ostype _src_core _bin _src_wasi _src_vm

    downloader --check
    need_cmd uname
    need_cmd chmod
    need_cmd mkdir
    need_cmd rm
    need_cmd rmdir

    test -d "$YA_INSTALLER_BIN" || sudo mkdir -p "$YA_INSTALLER_BIN"

    _ostype="$(detect_dist)"

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
      install_plugins "$_src_wasi" "$YA_INSTALLER_LIB"
      test -n "$_src_vm" && install_plugins "$_src_vm" "$YA_INSTALLER_LIB"
      (
        PATH="$YA_INSTALLER_BIN:$PATH"
      )
    fi

    ensurepath "$YA_INSTALLER_BIN"
}

main "$@" || exit 1
