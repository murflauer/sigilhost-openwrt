#!/bin/sh
# sigilhost-openwrt: добавляет списки из папок репо в Podkop/Forkop
# Для каждой папки создаётся секция sigil_<папка> (sigil_ai, sigil_roblox ...)
# Использование: install.sh [папка ...]   (без аргументов = все папки)
REPO="murflauer/sigilhost-openwrt"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

if [ -f /etc/config/forkop ]; then PKG=forkop
elif [ -f /etc/config/podkop ]; then PKG=podkop
else echo "Podkop/Forkop не найден"; exit 1; fi

[ $# -eq 0 ] && WANT=all || WANT=$(echo "$*" | tr 'A-Z' 'a-z')

# секции нового формата: config section '...'
SECS=$(uci -q show "$PKG" | sed -n "s/^$PKG\.\([^.=]*\)=section\$/\1/p")
TPL=""
for s in $SECS; do
  case "$s" in sigil_*) ;; *) TPL=$s; break ;; esac
done
if [ -n "$SECS" ]; then MULTI=1; else MULTI=0; fi

# копирует настройки подключения из шаблонной секции в новую ($1)
copy_template() {
  [ -n "$TPL" ] || return 0
  uci -q export "$PKG" | awk -v s="$TPL" -v q="'" '
    $1=="config" { n=$3; gsub(q,"",n); on=(n==s); next }
    on && ($1=="option" || $1=="list") {
      if ($2 ~ /^(community_lists|remote_|user_|local_|fully_routed|.*ruleset)/) next
      v=$0; sub(/^[ \t]*(option|list)[ \t]+[^ \t]+[ \t]+/,"",v); gsub(q,"",v)
      print $1 "\t" $2 "\t" v
    }' |
  while IFS="$(printf '\t')" read -r kind key val; do
    if [ "$kind" = option ]; then uci set "$PKG.$1.$key=$val"
    else uci add_list "$PKG.$1.$key=$val"; fi
  done
}

TREE=$(wget -qO- "https://api.github.com/repos/$REPO/git/trees/$BRANCH?recursive=1") \
  || { echo "GitHub API недоступен"; exit 1; }

echo "$TREE" | jsonfilter -e '@.tree[@.type="blob"].path' | grep '\.lst$' | while read -r path; do
  dir=${path%%/*}
  [ "$dir" = "$path" ] && continue
  d=$(printf '%s' "$dir" | tr 'A-Z' 'a-z')
  case " $WANT " in *" all "*|*" $d "*) ;; *) continue ;; esac

  if [ "$MULTI" = 1 ]; then
    SEC="sigil_$(printf '%s' "$d" | tr -c 'a-z0-9' '_')"
    if ! uci -q get "$PKG.$SEC" >/dev/null; then
      uci set "$PKG.$SEC=section"
      copy_template "$SEC"
    fi
  else
    SEC=main        # старая версия: секция одна
  fi

  case "$path" in
    *[iI][pP].lst) opt=remote_subnet_lists ;;
    *)             opt=remote_domain_lists ;;
  esac
  url="$RAW/$path"
  uci -q get "$PKG.$SEC.$opt" | grep -qF "$url" || uci add_list "$PKG.$SEC.$opt=$url"
  echo "$SEC <- $path"
done

uci commit "$PKG"
/etc/init.d/"$PKG" restart
