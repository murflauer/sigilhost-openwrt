#!/bin/sh
REPO="murflauer/sigilhost-openwrt"
SRS_URL="https://github.com/$REPO/releases/download/srs"

CONST=/usr/lib/forkop/core/constants.uc
RULES=/usr/lib/forkop/singbox/rulesets.uc
JS=/www/luci-static/resources/view/forkop/main.js

for f in $CONST $RULES $JS; do
  [ -f "$f" ] || { echo "нет файла $f"; exit 1; }
  grep -q 'sigil_' "$f" || cp -f "$f" "$f.sigil-orig"  
done

insert_after() {
  awk -v pat="$2" -v add="$3" '{print} !d && $0==pat {print add; d=1}' "$1" > "$1.tmp" \
    && cat "$1.tmp" > "$1" && rm -f "$1.tmp"
}

IDS=$(wget -qO- "https://api.github.com/repos/$REPO/git/trees/main?recursive=1" \
  | jsonfilter -e '@.tree[@.type="blob"].path' | grep '/.*\.lst$' | cut -d/ -f1 | sort -u \
  | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]/_/g;s/^/sigil_/')

grep -qF '"sigil_"' "$RULES" || insert_after "$RULES" 'function community_url(name) {' \
  "    if (substr(as_string(name), 0, 6) == \"sigil_\")\n        return \"$SRS_URL/\" + as_string(name) + \".srs\";"

for id in $IDS; do
  wget -q -O /dev/null "$SRS_URL/$id.srs" || { echo "пропуск $id: нет $SRS_URL/$id.srs"; continue; }

  grep -q " $id[ \"]" "$CONST" || sed -i "/c.COMMUNITY_SERVICES = env/ s/\");\$/ $id\");/" "$CONST"
  grep -q "^    $id: true," "$RULES" || insert_after "$RULES" 'const COMMUNITY_SERVICES = {' "    $id: true,"
  grep -q "^  $id: " "$JS" || insert_after "$JS" 'var DOMAIN_LIST_OPTIONS = {' "  $id: \"$id\","
  echo "добавлен: $id"
done

rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
/etc/init.d/rpcd restart
/etc/init.d/forkop restart
echo "Готово. Обнови страницу LuCI через Ctrl+F5."
