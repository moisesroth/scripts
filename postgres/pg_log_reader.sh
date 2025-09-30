#!/usr/bin/env bash

# ./pg_log_reader_gawk.sh --file postgresql.csv --follow
# ./pg_log_reader_gawk.sh --file postgresql.csv --level 'ERROR|WARNING'
# ./pg_log_reader_gawk.sh --file postgresql.csv --level '^LOG$'
# ./pg_log_reader_gawk.sh --file postgresql.csv --maxlen 160


set -euo pipefail

FILE=""
FOLLOW=0
LEVEL=""
MAXLEN=0

usage(){ echo "uso: $0 --file <postgres.csv> [-F|--follow] [--level '<regex>'] [--maxlen N]"; }

while (( $# )); do
  case "$1" in
    --file) FILE="$2"; shift 2;;
    -F|--follow) FOLLOW=1; shift;;
    --level) LEVEL="$2"; shift 2;;
    --maxlen) MAXLEN="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "opção desconhecida: $1" >&2; usage; exit 1;;
  esac
done

[[ -z "$FILE" ]] && { echo "erro: informe --file <postgres.csv>" >&2; exit 1; }
[[ ! -f "$FILE" ]] && { echo "erro: arquivo não encontrado: $FILE" >&2; exit 1; }

run_gawk() {
  gawk -v want_level="$LEVEL" -v maxlen="$MAXLEN" '
  BEGIN {
    # CSV robusto: campo vazio, não-aspado sem vírgula, ou aspado com aspas dobradas internas
    FPAT = "([^,]*)|(\"([^\"]|\"\")*\")"
    ENVIRON["TZ"] = "UTC"
  }
  function unq(s,    t){             # remove aspas externas e desdobra aspas internas
    if (s ~ /^"/) { t = substr(s,2,length(s)-2); gsub(/""/,"\"",t); return t }
    return s
  }
  function fmt_ago(total,    d,h,m,s,rem) {
    if (total < 0) total = 0
    d = int(total/86400); rem = total%86400
    h = int(rem/3600);    rem = rem%3600
    m = int(rem/60);      s = rem%60
    return sprintf("[+%02d:%02d:%02d:%02d]", d,h,m,s)
  }
  function ts_to_epoch(ts,    t, m) {
    t = unq(ts)
    gsub(/\.[0-9]+ /, " ", t)      # tira .mmm
    sub(/ UTC$/, "", t)            # tira sufixo UTC
    if (match(t, /([0-9]{4})-([0-9]{2})-([0-9]{2})[ ]([0-9]{2}):([0-9]{2}):([0-9]{2})/, m)) {
      return mktime(sprintf("%s %s %s %s %s %s", m[1],m[2],m[3],m[4],m[5],m[6]))
    }
    return 0
  }
  function maybe_trunc(s, n) {
    if (n <= 0 || length(s) <= n) return s
    return substr(s,1,n-1) "…"
  }

  {
    # pegue o "agora" a cada linha (bom para --follow)
    now = systime()

    ts  = $1
    lvl = unq($12)
    msg = unq($14)
    app = unq($23)
    bkt = unq($24)

    # filtro de nível por REGEX (se informado)
    if (want_level != "" && lvl !~ want_level) next

    label = (app != "" ? app : bkt)

    epoch = ts_to_epoch(ts)
    prefix = (epoch>0 ? fmt_ago(now - epoch) : "[" unq(ts) "]")

    if (maxlen > 0) msg = maybe_trunc(msg, maxlen)

    # saída: [+DD:HH:MM:SS] TIMESTAMP [LEVEL] (label) message
    out = prefix " " unq(ts)
    if (lvl != "")   out = out " [" lvl "]"
    if (label != "") out = out " (" label ")"
    if (msg != "")   out = out " " msg

    print out
  }'
}

if (( FOLLOW )); then
  tail -n 0 -F -- "$FILE" | run_gawk
else
  run_gawk < "$FILE"
fi
