#!/usr/bin/env bash
# ./pg_log_reader.sh --file postgresql.csv --follow
# ./pg_log_reader.sh --file postgresql.csv --level 'ERROR|WARNING'
# ./pg_log_reader.sh --file postgresql.csv --level '^LOG$'
# ./pg_log_reader.sh --file postgresql.csv --maxlen 160
# ./pg_log_reader.sh --file postgresql.csv --extra detail,context,query
# ./pg_log_reader_2.sh --file /var/lib/postgresql/data/log/postgresql-2025-10-07_000000.csv --extra detail,context,query -F | Where-Object { $_ -notmatch "connection" }

set -euo pipefail

FILE=""
FOLLOW=0
LEVEL=""
MAXLEN=0
EXTRA=""   # comma-separated names: detail,context,query,hint,sqlstate,location,app,backend,leader_pid,query_id

usage(){
  echo "usage: $0 --file <csvlog> [-F|--follow] [--level '<regex>'] [--maxlen N] [--extra 'detail,context,query,hint']"
}

while (( $# )); do
  case "$1" in
    --file)    FILE="$2"; shift 2;;
    -F|--follow) FOLLOW=1; shift;;
    --level)   LEVEL="$2"; shift 2;;
    --maxlen)  MAXLEN="$2"; shift 2;;
    --extra)   EXTRA="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown option: $1" >&2; usage; exit 1;;
  esac
done

[[ -z "$FILE" ]] && { echo "error: provide --file <csvlog>" >&2; exit 1; }
[[ ! -f "$FILE" ]] && { echo "error: file not found: $FILE" >&2; exit 1; }

run_gawk() {
  gawk -v want_level="$LEVEL" -v maxlen="$MAXLEN" -v extra_names="$EXTRA" '
  BEGIN {
    # Robust CSV parsing (handles empty fields and quoted fields with doubled quotes)
    FPAT = "([^,]*)|(\"([^\"]|\"\")*\")"
    ENVIRON["TZ"] = "UTC"

    # Name -> index map for PostgreSQL csvlog columns
    #  1:log_time  12:error_severity  14:message  15:detail  16:hint
    #  19:context  20:query  22:location  23:application_name  24:backend_type
    #  25:leader_pid  26:query_id  13:sql_state_code
    col["log_time"]=1
    col["level"]=12; col["error_severity"]=12
    col["sqlstate"]=13; col["sql_state_code"]=13
    col["message"]=14
    col["detail"]=15
    col["hint"]=16
    col["context"]=19
    col["query"]=20
    col["query_pos"]=21
    col["location"]=22
    col["application_name"]=23; col["app"]=23
    col["backend_type"]=24; col["backend"]=24
    col["leader_pid"]=25
    col["query_id"]=26

    # Parse requested extras
    split(extra_names, extra_list, /[ ,]+/)
    for (i in extra_list) {
      n = extra_list[i]
      if (n == "") continue
      # normalize some common aliases
      if (n == "level") n = "error_severity"
      if (n == "sqlstate") n = "sql_state_code"
      if (n == "app") n = "application_name"
      if (n == "backend") n = "backend_type"

      if (n in col) {
        push_extras[n] = col[n]
        extras_order[++extras_count] = n
      }
    }
  }

  function unq(s, t){ # remove surrounding quotes and unescape doubled quotes
    if (s ~ /^"/) { t = substr(s,2,length(s)-2); gsub(/""/,"\"",t); return t }
    return s
  }

  function fmt_ago(total, d,h,m,s,rem) {
    if (total < 0) total = 0
    d = int(total/86400); rem = total%86400
    h = int(rem/3600); rem = rem%3600
    m = int(rem/60); s = rem%60
    return sprintf("[+%02d:%02d:%02d:%02d]", d,h,m,s)
  }

  function ts_to_epoch(ts, t, m) {
    t = unq(ts)
    gsub(/\.[0-9]+ /, " ", t)   # drop .mmm
    sub(/ UTC$/, "", t)         # drop trailing UTC
    if (match(t, /([0-9]{4})-([0-9]{2})-([0-9]{2})[ ]([0-9]{2}):([0-9]{2}):([0-9]{2})/, m)) {
      return mktime(sprintf("%s %s %s %s %s %s", m[1],m[2],m[3],m[4],m[5],m[6]))
    }
    return 0
  }

  function maybe_trunc(s, n) { if (n <= 0 || length(s) <= n) return s; return substr(s,1,n-1) "…" }

  {
    now = systime()
    ts  = $1
    lvl = unq($12)
    msg = unq($14)
    app = unq($23)
    bkt = unq($24)

    # Level filter (regex) if provided
    if (want_level != "" && lvl !~ want_level) next

    label = (app != "" ? app : bkt)

    epoch = ts_to_epoch(ts)
    prefix = (epoch>0 ? fmt_ago(now - epoch) : "[" unq(ts) "]")

    if (maxlen > 0) msg = maybe_trunc(msg, maxlen)

    # base output: [+DD:HH:MM:SS] TIMESTAMP [LEVEL] (label) message
    out = prefix " " unq(ts)
    if (lvl != "")   out = out " [" lvl "]"
    if (label != "") out = out " (" label ")"
    if (msg != "")   out = out " " msg

    # extras (if requested) -> key=value pairs, only when non-empty
    if (extras_count > 0) {
      extra_kv = ""
      for (i = 1; i <= extras_count; i++) {
        name = extras_order[i]
        idx  = push_extras[name]
        val  = unq($idx)
        if (val != "") {
          if (maxlen > 0) val = maybe_trunc(val, maxlen)
          if (extra_kv != "") extra_kv = extra_kv "; "
          extra_kv = extra_kv name "=" val
        }
      }
      if (extra_kv != "") out = out "  {" extra_kv "}"
    }

    print out
  }'
}

if (( FOLLOW )); then
  tail -n 0 -F -- "$FILE" | run_gawk
else
  run_gawk < "$FILE"
fi
