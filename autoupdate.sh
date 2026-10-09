#!/bin/sh
# sigil-autoupdate: вопросник автообновления списков на OpenWrt.
# Обновление выполняется в 03:00 по Москве (пересчитывается в часовой пояс роутера).
#
# Использование:
#   sh autoupdate.sh            - задаст вопрос
#   sh autoupdate.sh daily      - раз в день
#   sh autoupdate.sh weekly     - раз в неделю (понедельник)
#   sh autoupdate.sh off        - отключить автообновление
#
# Если запускаете через "wget -O - URL | sh", вопрос читается с /dev/tty.

UPDATE_SCRIPT=/usr/bin/sigil-update
CRONFILE=/etc/crontabs/root
TAG="# sigil-autoupdate"

calc_time() {
  off=$(date +%z)            
  sign=${off%"${off#?}"}
  hh=${off#?}; hh=${hh%??}; hh=${hh#0}; hh=${hh:-0}
  mm=${off#???}; mm=${mm#0}; mm=${mm:-0}
  t=$((hh * 60 + mm))
  [ "$sign" = "-" ] && t=$((-t))

  DAY_SHIFT=0
  if [ "$t" -lt 0 ]; then
    t=$((t + 1440)); DAY_SHIFT=-1
  elif [ "$t" -ge 1440 ]; then
    t=$((t - 1440)); DAY_SHIFT=1
  fi
  L_HOUR=$((t / 60))
  L_MIN=$((t % 60))
}

write_update_script() {
  cat > "$UPDATE_SCRIPT" <<'EOF'
#!/bin/sh
# Обновление списков: перезапуск сервиса заставляет его заново подтянуть rule-set'ы.
# Если у вашего Forkop/Podkop есть отдельная команда обновления списков - замените её здесь.
for s in forkop podkop; do
  if [ -x "/etc/init.d/$s" ]; then
    logger -t sigil-update "обновление списков: перезапуск $s"
    "/etc/init.d/$s" restart
    exit $?
  fi
done
logger -t sigil-update "ни forkop, ни podkop не найдены в /etc/init.d"
exit 1
EOF
  chmod +x "$UPDATE_SCRIPT"
}

remove_cron() {
  [ -f "$CRONFILE" ] || return 0
  grep -v "$TAG" "$CRONFILE" > /tmp/crontab.sigil 2>/dev/null
  cat /tmp/crontab.sigil > "$CRONFILE"
  rm -f /tmp/crontab.sigil
}

reload_cron() {
  /etc/init.d/cron enable  >/dev/null 2>&1
  /etc/init.d/cron restart >/dev/null 2>&1
}

mode="$1"

if [ -z "$mode" ]; then
  calc_time
  printf 'Как обновлять списки автоматически?\n'
  printf '  1) Раз в день\n'
  printf '  2) Раз в неделю (понедельник)\n'
  printf '  3) Не обновлять (отключить)\n'
  printf 'Время: 03:00 по Москве (на этом роутере это %02d:%02d).\n' "$L_HOUR" "$L_MIN"
  printf 'Ваш выбор [1-3]: '
  if [ -t 0 ]; then read -r ans; else read -r ans < /dev/tty; fi
  case "$ans" in
    1) mode=daily ;;
    2) mode=weekly ;;
    3) mode=off ;;
    *) echo "Неверный выбор, ничего не изменено."; exit 1 ;;
  esac
fi

case "$mode" in
  daily|weekly)
    calc_time
    write_update_script
    remove_cron
    if [ "$mode" = "daily" ]; then
      dow="*"
    else
      dow=$(( (1 + DAY_SHIFT + 7) % 7 ))
    fi
    echo "$L_MIN $L_HOUR * * $dow $UPDATE_SCRIPT $TAG" >> "$CRONFILE"
    reload_cron
    printf 'Готово: автообновление %s, 03:00 МСК (локально %02d:%02d).\n' \
      "$([ "$mode" = daily ] && echo 'раз в день' || echo 'раз в неделю')" "$L_HOUR" "$L_MIN"
    ;;
  off)
    remove_cron
    reload_cron
    echo "Автообновление отключено."
    ;;
  *)
    echo "Неизвестный режим: $mode (допустимо: daily, weekly, off)"
    exit 1
    ;;
esac
