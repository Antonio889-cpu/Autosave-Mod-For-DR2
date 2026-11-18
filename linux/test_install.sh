#!/usr/bin/env bash
# Exercises install.sh against fake Steam folders. Never touches a real game folder.
set -uo pipefail
export LC_ALL=C

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
pkg="$tmp/package"
mkdir -p "$pkg"
tr -d '\r' <"$here/install.sh" >"$pkg/install.sh"
printf 'fake mod DR2 Autosave build' >"$pkg/d3dx9_43.dll"
fails=0

check() {
    if [[ $2 == "$3" ]]; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n      got:  %s\n      want: %s\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}
has() {
    if [[ $2 == *"$3"* ]]; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n      output: %s\n' "$1" "$2"; fails=$((fails + 1)); fi
}
put_u32() {
    local b
    b=$(printf '\\%03o\\%03o\\%03o\\%03o' $(($3 & 255)) $((($3 >> 8) & 255)) $((($3 >> 16) & 255)) $((($3 >> 24) & 255)))
    printf "$b" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}
make_exe() {
    head -c 512 /dev/zero >"$1/DR2_us.exe"
    put_u32 "$1/DR2_us.exe" 60 128
    put_u32 "$1/DR2_us.exe" 136 "$2"
    put_u32 "$1/DR2_us.exe" 208 $((0x489000))
}
new_game() {
    local d="$tmp/games/$1/Danganronpa 2 Goodbye Despair"
    mkdir -p "$d"
    make_exe "$d" $((0x57C6D776))
    printf '%s' "$d"
}
names() { (cd "$1" && ls -A | tr '\n' ','); }
run() { output=$(HOME="$tmp/home" bash "$pkg/install.sh" "$@" 2>&1); code=$?; }

mkdir -p "$tmp/home"
run
check 'no Steam folder fails' "$code" 1
has 'no Steam folder explains' "$output" 'Game not found'

native="$tmp/home/.local/share/Steam/steamapps/common/Danganronpa 2 Goodbye Despair"
mkdir -p "$native"
run
check 'native Linux copy fails' "$code" 1
has 'native Linux copy asks for Proton' "$output" 'force a Proton version'

library="$tmp/SD Card/Steam Library"
game="$library/steamapps/common/Danganronpa 2 Goodbye Despair"
mkdir -p "$game"
make_exe "$game" $((0x57C6D776))
printf '"libraryfolders"\n{\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$library" >"$tmp/home/.local/share/Steam/steamapps/libraryfolders.vdf"
run
check 'finds a second library with spaces' "$code" 0
check 'install adds dll and ini only' "$(names "$game")" 'DR2_us.exe,d3dx9_43.dll,dr2_autosave.ini,'
has 'prints the launch options' "$output" 'WINEDLLOVERRIDES="d3dx9_43=n,b" %command%'
check 'notification is off by default' "$(grep -c '^ShowNotification=0' "$game/dr2_autosave.ini")" 1
check 'ini uses Windows line endings' "$(tr -cd '\r' <"$game/dr2_autosave.ini" | wc -c | tr -d ' ')" 4

run --interval 15 --notify --no-backups
check 'options are accepted' "$code" 0
run
check 'reinstall keeps the interval' "$(grep -c '^IntervalMinutes=15' "$game/dr2_autosave.ini")" 1
check 'reinstall keeps the notification' "$(grep -c '^ShowNotification=1' "$game/dr2_autosave.ini")" 1
check 'reinstall keeps backups off' "$(grep -c '^KeepBackups=0' "$game/dr2_autosave.ini")" 1
check 'reinstall leaves no temp files' "$(names "$game")" 'DR2_us.exe,d3dx9_43.dll,dr2_autosave.ini,'

before=$(cat "$game/dr2_autosave.ini")
run --interval 7
check 'bad interval fails' "$code" 1
check 'bad interval changes nothing' "$(cat "$game/dr2_autosave.ini")" "$before"
run --bogus
check 'unknown option fails' "$code" 1

printf 'log' >"$game/dr2_autosave.log"
run --uninstall
check 'uninstall works' "$code" 0
check 'uninstall leaves a clean folder' "$(names "$game")" 'DR2_us.exe,'

other=$(new_game wrong)
make_exe "$other" 12345
run --game-dir "$other"
check 'wrong version fails' "$code" 1
has 'wrong version explains' "$output" 'not supported'
check 'wrong version changes nothing' "$(names "$other")" 'DR2_us.exe,'

short=$(new_game short)
printf 'tiny' >"$short/DR2_us.exe"
run --game-dir "$short"
check 'damaged exe fails' "$code" 1

foreign=$(new_game foreign)
printf 'someone else' >"$foreign/d3dx9_43.dll"
run --game-dir "$foreign"
check 'foreign dll install works' "$code" 0
check 'foreign dll is kept aside' "$(cat "$foreign/d3dx9_43.dll.original")" 'someone else'
run --game-dir "$foreign" --uninstall
check 'foreign dll is restored' "$(cat "$foreign/d3dx9_43.dll")" 'someone else'
check 'foreign backup is gone' "$(names "$foreign")" 'DR2_us.exe,d3dx9_43.dll,'

printf 'older' >"$foreign/d3dx9_43.dll.original"
run --game-dir "$foreign"
check 'two foreign dlls fail' "$code" 1
has 'two foreign dlls explain' "$output" 'Another mod'
check 'refusal keeps the dll' "$(cat "$foreign/d3dx9_43.dll")" 'someone else'
check 'refusal keeps the backup' "$(cat "$foreign/d3dx9_43.dll.original")" 'older'

clean=$(new_game clean)
mv "$pkg/d3dx9_43.dll" "$tmp/held.dll"
run --game-dir "$clean"
check 'missing mod file fails' "$code" 1
check 'missing mod file changes nothing' "$(names "$clean")" 'DR2_us.exe,'
mv "$tmp/held.dll" "$pkg/d3dx9_43.dll"

printf 'failures: %s\n' "$fails"
exit "$fails"
