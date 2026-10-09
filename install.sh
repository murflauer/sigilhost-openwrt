#!/bin/sh
REPO="murflauer/sigilhost-openwrt"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

if uci -q get podkop.main >/dev/null; then PKG=podkop
elif uci -q get forkop.main >/dev/null; then PKG=forkop
else echo "Podkop/Forkop не найден"; exit 1; fi
SEC=main

[ $# -eq 0 ] && WANT=all || WANT=$(echo "$*" | tr 'A-Z' 'a-z')

TREE=$(wget -qO- "https://api.github.com/repos/$REPO/git/trees/$BRANCH?recursive=1") \
  || { echo "GitHub API недоступен"; exit 1; }

echo "$TREE" | jsonfilter -e '@.tree[@.type="blob"].path' | grep '\.lst$' | while read -r path; do
  dir=${path%%/*}
  [ "$dir" = "$path" ] && continue      
  d=$(echo "$dir" | tr 'A-Z' 'a-z')
  case " $WANT " in *" all "*|*" $d "*) ;; *) continue ;; esac

  case "$path" in
    *[iI][pP].lst) opt=remote_subnet_lists ;;
    *)             opt=remote_domain_lists ;;
  esac

  url="$RAW/$path"
  uci -q get $PKG.$SEC.$opt | grep -qF "$url" || uci add_list $PKG.$SEC.$opt="$url"
  echo "+ $path"
done

uci set $PKG.$SEC.update_interval='1d'
uci commit $PKG
/etc/init.d/$PKG restart
