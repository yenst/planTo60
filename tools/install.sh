#!/usr/bin/env bash
# Links this repo into every WoW Forever / Classic install it finds as
# Interface/AddOns/planTo60, so edits show up in game after a /reload.
# Pass --copy to copy the addon files instead (no tests/tools/.git).
#   tools/install.sh [--copy] [WOW_DIR]
# WOW_DIR defaults to $WOW_DIR, then the usual Battle.net-under-Wine location.
set -euo pipefail

mode=link
if [[ "${1:-}" == "--copy" ]]; then
    mode=copy
    shift
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
wow="${1:-${WOW_DIR:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft}}"
installed=0

for flavor in _forever_ _classic_beta_ _classic_era_; do
    [[ -d "$wow/$flavor" ]] || continue
    addons="$wow/$flavor/Interface/AddOns"
    mkdir -p "$addons"
    # Older installs used the folder name "pt60"; remove that link if it points here.
    if [[ -L "$addons/pt60" && "$(readlink "$addons/pt60")" == "$repo"* ]]; then
        rm "$addons/pt60"
    fi
    rm -rf "$addons/planTo60"
    if [[ $mode == link ]]; then
        ln -s "$repo" "$addons/planTo60"
    else
        mkdir "$addons/planTo60"
        cp -r "$repo"/planTo60.toc "$repo"/*.lua "$repo"/embeds.xml "$repo"/Media "$addons/planTo60/"
        if [[ -d "$repo/Libs" ]]; then
            cp -r "$repo/Libs" "$addons/planTo60/"
        fi
    fi
    echo "$mode: $addons/planTo60"
    installed=$((installed + 1))
done

if [[ $installed -eq 0 ]]; then
    echo "No _forever_ / _classic_beta_ / _classic_era_ folder under: $wow" >&2
    exit 1
fi
