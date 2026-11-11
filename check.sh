#!/usr/bin/env bash
# サイトが見られるかを確かめる。1つでもだめなら終了コード 1（＝ GitHub からメールが届く）。
#   使い方: bash check.sh sites.txt
# sites.txt の1行 = 「URL  必ず含まれるはずの文字」（# で始まる行は飛ばす）
set -u
LIST="${1:-sites.txt}"
TRIES="${TRIES:-3}"   # 失敗したら、1分おいてあと2回やり直す（一瞬の不調では知らせない）
SSL_DAYS=14      # SSL 証明書の期限がこれより近づいたら知らせる
BAD='Fatal error|重大なエラー|データベース接続確立エラー|Error establishing a database connection|技術的な問題が発生しました|There has been a critical error'

fail=0
report=""

check_once() {
	local url="$1" must="$2" body code time
	body=$(mktemp)
	read -r code time < <(curl -s -L -o "$body" -w '%{http_code} %{time_total}' --max-time 30 \
		-A 'Mozilla/5.0 (site-monitor; +https://github.com/mk-partners4716/site-monitor)' "$url" || echo "000 0")
	if [ "$code" != "200" ]; then
		echo "HTTP $code"; rm -f "$body"; return 1
	fi
	if grep -Eq "$BAD" "$body"; then
		echo "エラーの表示あり"; rm -f "$body"; return 1
	fi
	if [ -n "$must" ] && ! grep -Fq "$must" "$body"; then
		echo "「$must」が見当たらない（中身がおかしい）"; rm -f "$body"; return 1
	fi
	rm -f "$body"
	echo "OK ${time}s"
	return 0
}

while read -r url must; do
	[ -z "${url:-}" ] && continue
	case "$url" in \#*) continue ;; esac
	result=""
	for i in $(seq 1 $TRIES); do
		if result=$(check_once "$url" "${must:-}"); then
			break
		fi
		[ "$i" -lt "$TRIES" ] && sleep 60
	done
	case "$result" in
		OK*) report+="✅ $url  $result"$'\n' ;;
		*)   report+="❌ $url  $result（${TRIES}回とも）"$'\n'; fail=1 ;;
	esac
done < "$LIST"

# SSL 証明書の期限（ドメインごとに1回）
for host in $(grep -Eo 'https://[^/ ]+' "$LIST" | sed 's#https://##' | sort -u); do
	end=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
	if [ -z "$end" ]; then
		report+="❌ $host  SSL 証明書を読めない"$'\n'; fail=1; continue
	fi
	left=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
	if [ "$left" -lt "$SSL_DAYS" ]; then
		report+="❌ $host  SSL 証明書の期限まであと ${left}日（$end）"$'\n'; fail=1
	else
		report+="✅ $host  SSL 証明書 あと ${left}日"$'\n'
	fi
done

printf '%s' "$report"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{ echo "### サイトの確認 $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')"; echo; printf '%s' "$report" | sed 's/^/- /'; } >> "$GITHUB_STEP_SUMMARY"
fi
exit $fail
