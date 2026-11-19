#!/usr/bin/env bash
# Reads Google Search Console for simpleshrink.com through gum
# (https://github.com/ehmo/gum), which is installed inside WSL because it has
# no Windows build. Prints JSON.
#
# From Windows (Git Bash, PowerShell, a Claude run):
#   wsl.exe -e bash "/mnt/c/Users/shrik/OneDrive/Desktop/Storage App/automation/gsc.sh" query 28
# From inside WSL:
#   bash automation/gsc.sh query 28
#
#   setup            one time: store your Google OAuth client, then sign in
#   login            sign in again (expired access, or to use another account)
#   status           is gum signed in?
#   sites            the properties this account can read
#   query [days]     searches: clicks, impressions, CTR, position (default 28 days)
#   page  [days]     the same, per page
#   date  [days]     the same, per day
#   both  [days]     per search and page together (which search lands where)
#   inspect <url>    is this URL indexed?
#
# gum keeps the sign-in in the Linux "login" keyring. WSL has no desktop to
# unlock one, so each call starts a private session bus and unlocks the keyring
# with a random password kept in ~/.config/gum/keyring-pass (readable only by
# you). Both live inside WSL and never enter this repo.
set -euo pipefail

SITE="sc-domain:simpleshrink.com"
# Read-only access to Search Console, nothing else.
SCOPE="https://www.googleapis.com/auth/webmasters.readonly"
GUM="${GUM:-$HOME/.local/bin/gum}"

if [ ! -x "$GUM" ]; then
  echo "gum isn't installed in WSL at $GUM. See automation/README.md." >&2
  exit 127
fi

# Re-run inside a session bus with the keyring unlocked.
if [ -z "${GSC_IN_SESSION:-}" ]; then
  export GSC_IN_SESSION=1
  # Sign-in prints its address on stderr and then waits, so show it live.
  case "${1:-}" in
    setup|login) exec dbus-run-session -- bash "$0" "$@" ;;
  esac
  noise="$(mktemp)"
  status=0
  dbus-run-session -- bash "$0" "$@" 2>"$noise" || status=$?
  # The session bus chatters on stderr; pass on only what gum itself said.
  grep -v -E 'dbus-daemon|SpiRegistry|org\.a11y|Gcr-WARNING|^$' "$noise" >&2 || true
  rm -f "$noise"
  exit "$status"
fi
PASS_FILE="$HOME/.config/gum/keyring-pass"
if [ ! -f "$PASS_FILE" ]; then
  (umask 077; mkdir -p "$(dirname "$PASS_FILE")"; head -c 24 /dev/urandom | base64 > "$PASS_FILE")
fi
tr -d '
' < "$PASS_FILE" | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1 || true
sleep 1.5

cmd="${1:-status}"
days="${2:-28}"

# Search Console's numbers arrive two to three days late.
end="$(date -d '2 days ago' +%F)"
start="$(date -d "$((days + 2)) days ago" +%F)"

analytics() {
  "$GUM" read searchconsole.searchanalytics.query --format json --max-items all \
    --args "{\"siteUrl\":\"$SITE\",\"body\":{\"startDate\":\"$start\",\"endDate\":\"$end\",\"dimensions\":$1,\"rowLimit\":1000}}"
}

case "$cmd" in
  setup)
    echo "Paste the OAuth client from Google Cloud (APIs & Services > Credentials > your Desktop client)."
    read -r -p "Client ID: " client_id
    read -r -s -p "Client secret (hidden): " client_secret
    echo
    printf '%s' "$client_secret" | "$GUM" auth use-oauth-client --client-id "$client_id" --secret-stdin
    unset client_secret
    echo "Now sign in. Open the address below in your browser and choose the Google account that owns the Search Console property."
    "$GUM" login --scope "$SCOPE" --no-browser
    "$GUM" read searchconsole.sites.list --format json
    ;;
  # --switch-account: a re-login may pick a different Google account on purpose.
  login) "$GUM" login --scope "$SCOPE" --no-browser --switch-account ;;
  status) "$GUM" auth status ;;
  sites) "$GUM" read searchconsole.sites.list --format json ;;
  query) analytics '["query"]' ;;
  page) analytics '["page"]' ;;
  date) analytics '["date"]' ;;
  both) analytics '["query","page"]' ;;
  inspect)
    "$GUM" read searchconsole.urlInspection.index.inspect --format json \
      --args "{\"body\":{\"inspectionUrl\":\"${2:?give a URL}\",\"siteUrl\":\"$SITE\"}}"
    ;;
  *)
    sed -n '2,22p' "$0" >&2
    exit 2
    ;;
esac
