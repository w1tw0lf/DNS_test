#!/usr/bin/env bash
#
# dns_test.sh — probe the DNS resolver your network hands you (typically the
# router) over plain DNS, DNS-over-TLS (DoT) and DNS-over-HTTPS (DoH), on both
# IPv4 and IPv6, then ping the target domain.
#
# The resolver is auto-discovered from the system — /etc/resolv.conf first,
# then NetworkManager / systemd-resolved / scutil, then the default gateway.
# No public DNS servers are hard-coded; everything is tested against *your*
# network. If the resolver advertises encrypted endpoints via DDR
# (RFC 9462/9463, the _dns.resolver.arpa SVCB record) those are used for the
# DoH test.
#
# Dependencies:
#   * dig            — bind / bind-utils / dnsutils; DoT & DoH need dig >= 9.18
#   * ping / ping -6 — iputils on Linux, built in on macOS
#
# Usage:
#   ./dns_test.sh [domain]        # prompts for the domain if not given
#   NO_COLOR=1 ./dns_test.sh ...  # disable coloured output

set -u

command -v dig >/dev/null 2>&1 || {
    echo "error: 'dig' is required (install bind / bind-utils / dnsutils)." >&2
    exit 1
}

# --------------------------------------------------------------------- style
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RST=$'\033[0m'
    RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; CYN=$'\033[36m'
else
    BOLD='' DIM='' RST='' RED='' GRN='' YLW='' CYN=''
fi
OK_MARK="${GRN}✓${RST}"
BAD_MARK="${RED}✗${RST}"
SEP=$'\037'                 # unit separator — never appears in our row data
OS=$(uname -s)

# ------------------------------------------------------------------- helpers
hr() {                      # hr <n> [char] — print <char> (default ─) n times
    local n=${1:-0} ch=${2:-─}
    (( n < 1 )) && return
    printf "${ch}%.0s" $(seq 1 "$n")
}
section() {                 # section <title> — underlined heading
    printf '\n  %s%s%s\n  %s\n' "$BOLD" "$1" "$RST" "$(hr ${#1} ═)"
}

ping4() {                   # ping4 <host> [count] — exit status = reachability
    if [[ "$OS" == Darwin ]]; then ping  -c "${2:-1}" -t 3 "$1" 2>/dev/null
    else                           ping  -c "${2:-1}" -W 2 "$1" 2>/dev/null; fi
}
ping6() {
    if [[ "$OS" == Darwin ]] && command -v ping6 >/dev/null 2>&1; then
        ping6 -c "${2:-1}" "$1" 2>/dev/null
    else
        ping -6 -c "${2:-1}" -W 2 "$1" 2>/dev/null
    fi
}
ping_avg_ms() {             # read ping output on stdin -> average RTT ("a.b")
    sed -n 's@.*= *[0-9.]*/\([0-9.]*\)/.*@\1@p'
}
ping_loss() {               # read ping output on stdin -> packet loss percent
    sed -n 's/.*[, ]\([0-9.]*\)% packet loss.*/\1/p'
}

# ------------------------------------------------------------- dig capability
DIG_DOT=false DIG_DOH=false
DIG_VER=$(dig -v 2>&1 | awk 'NR==1{print $2}')          # e.g. 9.20.22
_maj=${DIG_VER%%.*}; _rest=${DIG_VER#*.}; _min=${_rest%%.*}
if [[ "$_maj" =~ ^[0-9]+$ && "$_min" =~ ^[0-9]+$ ]] \
   && { (( _maj > 9 )) || { (( _maj == 9 )) && (( _min >= 18 )); }; }; then
    DIG_DOT=true DIG_DOH=true
fi

# ---------------------------------------------------------- resolver discovery
RES_V4='' RES_V6='' RES_SRC='' GATEWAY='' DOH_HOST='' DOH_URL=''

is_v6()   { [[ "$1" == *:* ]]; }
is_stub() { [[ "$1" == 127.* || "$1" == ::1 ]]; }      # local stub, not the router
add_ns()  {                 # remember the first non-stub IPv4 / IPv6 nameserver
    local ip=${1%%%*}                                  # drop %zone on link-local v6
    [[ -z "$ip" ]] && return
    if is_v6 "$ip"; then [[ -z "$RES_V6" ]] && ! is_stub "$ip" && RES_V6=$ip
    else                 [[ -z "$RES_V4" ]] && ! is_stub "$ip" && RES_V4=$ip; fi
}

discover_gateway() {
    if [[ "$OS" == Darwin ]]; then
        GATEWAY=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')
    else
        GATEWAY=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    fi
}

discover_resolvers() {
    discover_gateway

    # 1) /etc/resolv.conf — the most direct source
    if [[ -r /etc/resolv.conf ]]; then
        while read -r kw val _; do
            [[ "$kw" == nameserver ]] && add_ns "$val"
        done < /etc/resolv.conf
    fi

    # 2) only a stub (127.0.0.53 / 127.0.0.1 / ::1) or nothing found? ask the
    #    network layer what that stub actually forwards to
    if [[ -z "$RES_V4" || -z "$RES_V6" ]]; then
        if command -v resolvectl >/dev/null 2>&1; then
            while read -r ip; do add_ns "$ip"; done < <(
                resolvectl status 2>/dev/null | awk '
                    /Current DNS Server:/ {print $NF}
                    /DNS Servers:/        {for (i=3;i<=NF;i++) print $i}')
        fi
        if command -v nmcli >/dev/null 2>&1; then
            while read -r ip; do add_ns "$ip"; done < <(
                nmcli dev show 2>/dev/null | awk '/^IP[46]\.DNS\[/{print $NF}')
        fi
        if [[ "$OS" == Darwin ]] && command -v scutil >/dev/null 2>&1; then
            while read -r ip; do add_ns "$ip"; done < <(
                scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/{print $NF}')
        fi
    fi

    # 3) last resort: the default gateway is very often the resolver as well
    [[ -z "$RES_V4" && -n "$GATEWAY" && "$GATEWAY" != *:* ]] && RES_V4=$GATEWAY

    if [[ -n "$RES_V4$RES_V6" ]]; then
        if [[ -n "$GATEWAY" && "$RES_V4" == "$GATEWAY" ]]; then
            RES_SRC="router / default gateway"
        else
            RES_SRC="system DNS configuration"
        fi
    fi
}

discover_doh() {            # DDR: does the resolver advertise an encrypted endpoint?
    local out line prio target path
    out=$(dig +timeout=3 +tries=1 +short SVCB _dns.resolver.arpa 2>/dev/null) || return
    while read -r line; do
        [[ -z "$line" ]] && continue
        prio=$(awk '{print $1}' <<<"$line"); [[ "$prio" == 0 ]] && continue   # AliasMode
        target=$(awk '{print $2}' <<<"$line"); target=${target%.}
        [[ -z "$target" || "$target" == . ]] && continue
        # interested in the HTTPS (h2/h3) record; dohpath may be printed as key7
        grep -qiE 'alpn=.?h[23]|dohpath=|key7=' <<<"$line" || continue
        path=$(grep -oiE '(dohpath|key7)="?[^" ]+' <<<"$line" | head -n1 \
               | sed -E 's/^(dohpath|key7)="?//; s/\{[^}]*\}//')
        [[ -z "$path" ]] && path="/dns-query"
        DOH_HOST=$target
        DOH_URL="https://${target}${path}"
        return
    done <<<"$out"
}

# -------------------------------------------------------------------- queries
# query <mode plain|tls|https> <server> <rrtype> <name>
#   line 1   : "<STATUS>\t<ms-or-dash>"
#   lines 2+ : record rdata, one per line
# STATUS is a DNS rcode (NOERROR/NXDOMAIN/SERVFAIL/REFUSED/...) or one of
# TIMEOUT / CONNREFUSED / UNREACHABLE / TLSFAIL / HTTPFAIL / ERROR / UNSUPPORTED.
query() {
    local mode=$1 server=$2 rrtype=$3 name=$4
    local -a o=(+timeout=3 +tries=1 +noall +comments +answer +stats)
    case "$mode" in
        tls)   $DIG_DOT || { printf 'UNSUPPORTED\t-\n'; return; }; o+=(+tls)   ;;
        https) $DIG_DOH || { printf 'UNSUPPORTED\t-\n'; return; }; o+=(+https) ;;
    esac
    local out st ms
    out=$(dig "${o[@]}" "@$server" "$rrtype" "$name" 2>&1)
    ms=$(awk '/;; Query time:/{print $4; exit}' <<<"$out"); [[ -z "$ms" ]] && ms='-'
    st=$(awk -F'status: ' '/->>HEADER<<-/{sub(/,.*/,"",$2); print $2; exit}' <<<"$out")
    if [[ -z "$st" ]]; then                       # no DNS response at all
        if   grep -qiE 'tls'                        <<<"$out"; then st=TLSFAIL
        elif grep -qiE 'http|doh'                   <<<"$out"; then st=HTTPFAIL
        elif grep -qiE 'reset|refused'              <<<"$out"; then st=CONNREFUSED
        elif grep -qiE 'unreachable'                <<<"$out"; then st=UNREACHABLE
        elif grep -qiE 'timed out|no servers could' <<<"$out"; then st=TIMEOUT
        else                                                       st=ERROR; fi
        printf '%s\t%s\n' "$st" "$ms"
        return
    fi
    printf '%s\t%s\n' "$st" "$ms"
    awk -v t="$rrtype" '!/^;/ && $4 == t {print $NF}' <<<"$out"
}

# -------------------------------------------------------------------- results
declare -a ROWS             # each entry: c1 SEP c2 SEP c3 SEP c4 SEP kind
add_row() { ROWS+=("$1$SEP$2$SEP$3$SEP$4$SEP$5"); }

# describe <mode> <status> <n-records> <first-record>  ->  sets DESC, KIND
DESC='' KIND=''
describe() {
    local mode=$1 st=$2 n=$3 first=$4
    case "$st" in
        NOERROR)
            if (( n > 0 )); then DESC=$first; KIND=ok
            else                 DESC="no record of this type"; KIND=warn; fi ;;
        NXDOMAIN)    DESC="NXDOMAIN (no such domain)";   KIND=warn ;;
        SERVFAIL)    DESC="SERVFAIL (resolver failed)";  KIND=bad  ;;
        REFUSED)     DESC="REFUSED (query refused)";     KIND=bad  ;;
        UNSUPPORTED) DESC="needs dig 9.18+ (have ${DIG_VER:-?})"; KIND=info ;;
        NORES)       DESC="no resolver for this family"; KIND=info ;;
        TLSFAIL)     DESC="TLS failed (cert mismatch / self-signed?)"; KIND=warn ;;
        HTTPFAIL)    DESC="HTTPS reached but DoH request failed";      KIND=warn ;;
        TIMEOUT|CONNREFUSED|UNREACHABLE)
            case "$mode" in
                tls)   DESC="not offered (port 853 closed/filtered)"; KIND=warn ;;
                https) DESC="not offered (port 443 / endpoint unavailable)"; KIND=warn ;;
                *)     case "$st" in
                           TIMEOUT)     DESC="timed out";          KIND=bad ;;
                           CONNREFUSED) DESC="connection refused"; KIND=bad ;;
                           *)           DESC="network unreachable";KIND=bad ;;
                       esac ;;
            esac ;;
        *) DESC="error: $st"; KIND=bad ;;
    esac
}

# run_test <label> <mode plain|tls|https> <family v4|v6> <active true|false>
run_test() {
    local label=$1 mode=$2 fam=$3 active=$4
    local server rrtype famlbl
    if [[ $fam == v4 ]]; then server=$RES_V4; rrtype=A;    famlbl=IPv4
    else                      server=$RES_V6; rrtype=AAAA; famlbl=IPv6; fi
    # DoH: prefer the DDR-advertised hostname (it has a real, verifiable cert)
    [[ $mode == https && -n "$DOH_HOST" ]] && server=$DOH_HOST

    if [[ "$active" != true || -z "$server" ]]; then
        describe "$mode" NORES 0 ''
        add_row "$label" "$famlbl" "-" "$DESC" "$KIND"
        return
    fi

    local out st ms
    out=$(query "$mode" "$server" "$rrtype" "$DOMAIN")
    { read -r st ms; } <<<"$out"
    local -a recs=(); local r
    while read -r r; do [[ -n "$r" ]] && recs+=("$r"); done < <(tail -n +2 <<<"$out")
    describe "$mode" "$st" "${#recs[@]}" "${recs[0]:-}"

    local tcol="-"; [[ "$ms" =~ ^[0-9]+$ ]] && tcol="${ms} ms"
    if [[ "$KIND" == ok && ${#recs[@]} -gt 0 ]]; then
        local i
        for ((i = 0; i < ${#recs[@]}; i++)); do
            if (( i == 0 )); then add_row "$label" "$famlbl" "$tcol" "${recs[i]}" ok
            else                  add_row ""       ""        ""      "${recs[i]}" ok; fi
        done
    else
        add_row "$label" "$famlbl" "$tcol" "$DESC" "$KIND"
    fi
}

ping_row() {                # ping_row <family v4|v6> <active true|false>
    local fam=$1 active=$2 famlbl out avg loss
    [[ $fam == v4 ]] && famlbl=IPv4 || famlbl=IPv6
    if [[ "$active" != true ]]; then
        add_row Ping "$famlbl" "-" "skipped (no $famlbl)" info
        return
    fi
    if [[ $fam == v4 ]]; then out=$(ping4 "$DOMAIN" 4); else out=$(ping6 "$DOMAIN" 4); fi
    avg=$(printf '%s\n' "$out" | ping_avg_ms)
    loss=$(printf '%s\n' "$out" | ping_loss)
    if [[ -n "$avg" ]]; then
        local t; t=$(printf '%.1f ms' "$avg" 2>/dev/null) || t="${avg} ms"
        add_row Ping "$famlbl" "$t" "${loss:-0}% packet loss" ok
    elif [[ $fam == v6 ]]; then
        add_row Ping "$famlbl" "-" "no reply (no AAAA record?)" warn
    else
        add_row Ping "$famlbl" "-" "no reply (host down / no A record?)" warn
    fi
}

render_table() {
    local h1="Test" h2="Family" h3="Time" h4="Result"
    local w1=${#h1} w2=${#h2} w3=${#h3} w4=${#h4}
    local row c1 c2 c3 c4 k
    for row in "${ROWS[@]}"; do
        IFS=$SEP read -r c1 c2 c3 c4 k <<<"$row"
        (( ${#c1} > w1 )) && w1=${#c1}
        (( ${#c2} > w2 )) && w2=${#c2}
        (( ${#c3} > w3 )) && w3=${#c3}
        (( ${#c4} > w4 )) && w4=${#c4}
    done
    local L M B
    L="  ┌─$(hr $w1)─┬─$(hr $w2)─┬─$(hr $w3)─┬─$(hr $w4)─┐"
    M="  ├─$(hr $w1)─┼─$(hr $w2)─┼─$(hr $w3)─┼─$(hr $w4)─┤"
    B="  └─$(hr $w1)─┴─$(hr $w2)─┴─$(hr $w3)─┴─$(hr $w4)─┘"
    printf '\n%s\n' "$L"
    printf '  │ %s%-*s%s │ %s%-*s%s │ %s%*s%s │ %s%-*s%s │\n' \
        "$BOLD" $w1 "$h1" "$RST" "$BOLD" $w2 "$h2" "$RST" \
        "$BOLD" $w3 "$h3" "$RST" "$BOLD" $w4 "$h4" "$RST"
    printf '%s\n' "$M"
    local prev='' started=0
    for row in "${ROWS[@]}"; do
        IFS=$SEP read -r c1 c2 c3 c4 k <<<"$row"
        if [[ -n "$c1" && $started -eq 1 && "$c1" != "$prev" ]]; then
            printf '%s\n' "$M"
        fi
        [[ -n "$c1" ]] && { prev=$c1; started=1; }
        local col=''
        case "$k" in ok) col=$GRN;; warn) col=$YLW;; bad) col=$RED;; info) col=$CYN;; esac
        printf '  │ %-*s │ %-*s │ %s%*s%s │ %s%-*s%s │\n' \
            $w1 "$c1" $w2 "$c2" "$DIM" $w3 "$c3" "$RST" "$col" $w4 "$c4" "$RST"
    done
    printf '%s\n' "$B"
}

# ------------------------------------------------------------------------ main
printf '\n  %sDNS Test%s %s· local resolver probe%s\n  %s\n' \
    "$BOLD" "$RST" "$DIM" "$RST" "$(hr 33)"

# --- target domain ---
DOMAIN=${1:-}
if [[ -z "$DOMAIN" ]]; then
    printf '\n'
    read -rp "  Domain to test [google.com]: " DOMAIN
    DOMAIN=${DOMAIN:-google.com}
fi
if ! [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$ ]]; then
    printf '  %sInvalid domain:%s %q\n' "$RED" "$RST" "$DOMAIN" >&2
    exit 1
fi

# --- discovery ---
section "Resolver discovery"
discover_resolvers
discover_doh
printf '    %-10s %s%s\n' "IPv4"    "${RES_V4:-${YLW}not found${RST}}" \
       "${RES_V4:+${DIM}  (${RES_SRC})${RST}}"
printf '    %-10s %s\n'   "IPv6"    "${RES_V6:-${YLW}not found${RST}}"
printf '    %-10s %s\n'   "Gateway" "${GATEWAY:-${DIM}unknown${RST}}"
printf '    %-10s %s\n'   "DoH/DDR" "${DOH_URL:-${DIM}not advertised${RST}}"
$DIG_DOT || printf '    %s(dig %s < 9.18 — DoT/DoH tests will be skipped)%s\n' \
                   "$DIM" "${DIG_VER:-?}" "$RST"
if [[ -z "$RES_V4$RES_V6" ]]; then
    printf '\n  %sCould not discover any DNS resolver — nothing to test.%s\n' "$RED" "$RST" >&2
    exit 1
fi

# --- connectivity (probe the discovered resolvers) ---
section "Connectivity"
V4_UP=false V6_UP=false
if [[ -n "$RES_V4" ]]; then
    if ping4 "$RES_V4" 1 >/dev/null; then V4_UP=true
    elif [[ -n "$(dig +timeout=2 +tries=1 +short . NS "@$RES_V4" 2>/dev/null)" ]]; then V4_UP=true; fi
fi
if [[ -n "$RES_V6" ]]; then
    if ping6 "$RES_V6" 1 >/dev/null; then V6_UP=true
    elif [[ -n "$(dig +timeout=2 +tries=1 +short . NS "@$RES_V6" 2>/dev/null)" ]]; then V6_UP=true; fi
fi
$V4_UP && printf '    %-10s %s\n' "IPv4" "$OK_MARK resolver reachable" \
       || printf '    %-10s %s\n' "IPv4" "$BAD_MARK ${DIM}no IPv4 resolver / unreachable${RST}"
$V6_UP && printf '    %-10s %s\n' "IPv6" "$OK_MARK resolver reachable" \
       || printf '    %-10s %s\n' "IPv6" "$BAD_MARK ${DIM}no IPv6 resolver / unreachable${RST}"
if ! $V4_UP && ! $V6_UP; then
    printf '\n  %sNeither resolver is reachable — aborting.%s\n' "$RED" "$RST" >&2
    exit 1
fi

# --- run the probes ---
section "Tests for \"$DOMAIN\""
run_test DNS  plain v4 "$V4_UP"
run_test DNS  plain v6 "$V6_UP"
run_test DoT  tls   v4 "$V4_UP"
run_test DoT  tls   v6 "$V6_UP"
run_test DoH  https v4 "$V4_UP"
run_test DoH  https v6 "$V6_UP"
ping_row v4 "$V4_UP"
ping_row v6 "$V6_UP"

render_table
printf '\n'
