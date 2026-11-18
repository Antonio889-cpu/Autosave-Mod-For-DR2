#!/usr/bin/env bash
# Installs the DR2 Autosave mod into the Windows copy of the game that Steam runs through Proton.
set -euo pipefail

GAME_FOLDER="Danganronpa 2 Goodbye Despair"
GAME_EXE="DR2_us.exe"
DLL="d3dx9_43.dll"
ORIGINAL="$DLL.original"
INI="dr2_autosave.ini"
LOG="dr2_autosave.log"
MARK="DR2 Autosave"
LAUNCH_OPTIONS='WINEDLLOVERRIDES="d3dx9_43=n,b" %command%'
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

action=install
game_dir=""
interval=""
notify=""
backups=""
moved_foreign=0
target=""

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: bash install.sh [options]

  --interval MINUTES  Autosave every 2, 5, 10, 15 or 30 minutes (default: 5)
  --notify            Show the on-screen notification (default: off on Linux)
  --no-notify         Hide the on-screen notification
  --backups           Keep backup copies of the save file (default: on)
  --no-backups        Do not keep backup copies
  --game-dir PATH     Use this game folder instead of searching for it
  --uninstall         Remove the mod. Your saves are kept
  --help              Show this help
EOF
}

while (($#)); do
    case "$1" in
        --interval) (($# >= 2)) || die "--interval needs a value."; interval=$2; shift ;;
        --notify) notify=1 ;;
        --no-notify) notify=0 ;;
        --backups) backups=1 ;;
        --no-backups) backups=0 ;;
        --game-dir) (($# >= 2)) || die "--game-dir needs a path."; game_dir=$2; shift ;;
        --uninstall) action=uninstall ;;
        --help | -h) usage; exit 0 ;;
        *) die "Unknown option: $1. Use --help to see the options." ;;
    esac
    shift
done

valid_interval() {
    case "$1" in 2 | 5 | 10 | 15 | 30) return 0 ;; *) return 1 ;; esac
}

if [[ -n $interval ]] && ! valid_interval "$interval"; then
    die "The interval must be 2, 5, 10, 15 or 30 minutes."
fi

read_u32() {
    od -An -tu4 -j "$2" -N4 "$1" | tr -d ' \n'
}

# Returns 0 for the supported build, 1 when the exe is missing, 2 for any other build.
check_game() {
    local exe="$1/$GAME_EXE" size pe
    [[ -f $exe ]] || return 1
    size=$(wc -c <"$exe")
    ((size >= 64)) || return 2
    pe=$(read_u32 "$exe" 60)
    [[ $pe =~ ^[0-9]+$ ]] && ((pe + 84 <= size)) || return 2
    [[ $(read_u32 "$exe" $((pe + 8))) == $((0x57C6D776)) ]] || return 2
    [[ $(read_u32 "$exe" $((pe + 80))) == $((0x489000)) ]] || return 2
}

steam_libraries() {
    local root
    for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
        [[ -d $root ]] || continue
        printf '%s\n' "$root"
        [[ -f $root/steamapps/libraryfolders.vdf ]] || continue
        sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$root/steamapps/libraryfolders.vdf" |
            sed 's/\\\\/\\/g'
    done
}

find_game() {
    local library candidate native=""
    if [[ -n $game_dir ]]; then
        [[ -d $game_dir ]] || die "Folder not found: $game_dir"
        target=$game_dir
    else
        while IFS= read -r library; do
            candidate="$library/steamapps/common/$GAME_FOLDER"
            [[ -d $candidate ]] || continue
            if [[ -f $candidate/$GAME_EXE ]]; then
                target=$candidate
                break
            fi
            native=$candidate
        done < <(steam_libraries)
    fi

    if [[ -z $target && -z $native ]]; then
        die "Game not found. Install it with Steam, or use --game-dir PATH."
    fi
    if [[ -z $target || ! -f $target/$GAME_EXE ]]; then
        die "This is the native Linux copy of the game. In Steam open Properties > Compatibility, force a Proton version, let the download finish, then run this script again."
    fi
}

is_ours() {
    [[ -f $1 ]] && grep -aq "$MARK" "$1"
}

require_game_closed() {
    if command -v pgrep >/dev/null 2>&1 && pgrep -f 'DR2_us\.exe' >/dev/null 2>&1; then
        die "Close the game first, then run this script again."
    fi
}

ini_value() {
    [[ -f $target/$INI ]] || return 0
    sed -n "s/^$1=\([0-9][0-9]*\)[[:space:]]*\$/\1/p" "$target/$INI" | head -n 1
}

rollback() {
    rm -f -- "$target/$DLL.new" "$target/$INI.new"
    if ((moved_foreign)); then
        rm -f -- "$target/$DLL"
        mv -f -- "$target/$ORIGINAL" "$target/$DLL"
    fi
}

install_mod() {
    local status=0 source="$SCRIPT_DIR/$DLL" dll="$target/$DLL" original="$target/$ORIGINAL" foreign=0
    check_game "$target" || status=$?
    ((status == 0)) || die "This copy of the game is not supported. The mod needs the current Steam Windows version."
    is_ours "$source" || die "$DLL is missing from the mod package. Extract the whole archive and try again."

    if [[ -e $dll ]] && ! is_ours "$dll"; then
        foreign=1
        [[ ! -e $original ]] || die "Another mod is using $DLL in the game folder. Remove it first."
    fi

    [[ -n $interval ]] || interval=$(ini_value IntervalMinutes)
    valid_interval "${interval:-}" || interval=5
    [[ -n $notify ]] || notify=$(ini_value ShowNotification)
    [[ $notify == 1 ]] || notify=0
    [[ -n $backups ]] || backups=$(ini_value KeepBackups)
    [[ $backups == 0 ]] || backups=1

    trap rollback EXIT
    cp -- "$source" "$dll.new" || die "Could not write to the game folder."
    cmp -s -- "$source" "$dll.new" || die "The mod file was not written correctly."
    printf '[Autosave]\r\nIntervalMinutes=%s\r\nShowNotification=%s\r\nKeepBackups=%s\r\n' \
        "$interval" "$notify" "$backups" >"$target/$INI.new" || die "Could not write the settings."
    if ((foreign)); then
        mv -- "$dll" "$original" || die "Could not keep the existing $DLL."
        moved_foreign=1
    fi
    mv -f -- "$dll.new" "$dll" || die "Could not install the mod."
    mv -f -- "$target/$INI.new" "$target/$INI" || die "Could not save the settings."
    trap - EXIT

    cat <<EOF
Mod installed in:
  $target

Settings: every $interval minutes, notification $( ((notify)) && echo on || echo off), backups $( ((backups)) && echo on || echo off)

One last step. In Steam open the game's Properties > General and set Launch Options to:

  $LAUNCH_OPTIONS

Without this line Proton does not load the mod.
EOF
}

uninstall_mod() {
    if is_ours "$target/$DLL"; then
        rm -f -- "$target/$DLL"
    fi
    if [[ -e $target/$ORIGINAL && ! -e $target/$DLL ]]; then
        mv -- "$target/$ORIGINAL" "$target/$DLL"
    fi
    rm -f -- "$target/$INI" "$target/$LOG"
    printf 'Mod removed. Your saves were not touched.\nYou can now clear the Launch Options in Steam.\n'
}

find_game
require_game_closed
if [[ $action == install ]]; then install_mod; else uninstall_mod; fi
