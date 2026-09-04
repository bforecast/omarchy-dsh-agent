#!/usr/bin/env bash
# Poll the marketplace submission issue; email the GitHub-account email when the
# approval state changes. Baseline snapshot lives in .github/marketplace-state.json
# and is committed back after each observed change.
set -euo pipefail

ISSUE_URL="https://github.com/$WATCH_REPO/issues/$WATCH_ISSUE"
STATE_FILE=".github/marketplace-state.json"
SNAPSHOT_TMP="$(mktemp)"

trap 'rm -f "$SNAPSHOT_TMP"' EXIT

# Fingerprint: anything a reviewer/bot could change.
gh api "repos/$WATCH_REPO/issues/$WATCH_ISSUE" \
  --jq '{ state, stateReason, updatedAt, labels: [.labels[].name], comments }' >"$SNAPSHOT_TMP"

changed=false
if [[ ! -f $STATE_FILE ]]; then
  echo "No baseline yet; storing current state (first run, no email)."
  changed=false
elif diff -q "$SNAPSHOT_TMP" "$STATE_FILE" >/dev/null 2>&1; then
  echo "No change since last check."
else
  changed=true
fi

cp "$SNAPSHOT_TMP" "$STATE_FILE"

if [[ $changed == false ]]; then
  if [[ -z $(git status --porcelain -- "$STATE_FILE") ]]; then
    exit 0
  fi
  # baseline creation: commit without emailing
  git add "$STATE_FILE"
  git -c user.name="marketplace-watch" -c user.email="marketplace-watch@users.noreply.github.com" \
    commit -q -m "marketplace-watch: record baseline state" || true
  git push -q origin HEAD || true
  exit 0
fi

echo "Change detected -> notifying ${SMTP_TO:-$SMTP_FROM}"
# Compose a short email body from the current issue data.
BODY_TMP="$(mktemp)"; trap 'rm -f "$SNAPSHOT_TMP" "$BODY_TMP"' EXIT
{
  echo "Marketplace submission progress changed."
  echo
  echo "Issue: $ISSUE_URL"
  gh api "repos/$WATCH_REPO/issues/$WATCH_ISSUE" --jq '"Title:   " + .title'
  gh api "repos/$WATCH_REPO/issues/$WATCH_ISSUE" --jq '"State:   " + .state + " (" + ((.state_reason // "none")) + ")"'
  gh api "repos/$WATCH_REPO/issues/$WATCH_ISSUE" --jq '"Labels:  " + ([.labels[].name] | join(", "))'
  echo
  echo "Latest activity:"
  gh api "repos/$WATCH_REPO/issues/$WATCH_ISSUE/comments?per_page=3" --jq \
    '.[] | "--- " + .user.login + " @ " + .created_at + "\n" + (.body[0:700])'
} >"$BODY_TMP"

if [[ -z ${SMTP_PASS:-} || -z ${SMTP_FROM:-} ]]; then
  echo "SMTP secrets not configured; skipping email (state recorded)."
  echo "Set repository secrets: GMAIL_ADDRESS and GMAIL_APP_PASSWORD (and NOTIFY_EMAIL)."
else
  python3 - "$BODY_TMP" <<'PY'
import os, smtplib, sys
from email.mime.text import MIMEText
from email.utils import formataddr

body = open(sys.argv[1], encoding="utf-8").read()
to = os.environ.get("SMTP_TO") or os.environ.get("SMTP_FROM")
msg = MIMEText(body, "plain", "utf-8")
msg["Subject"] = "[omarchy-dsh-agent] Marketplace issue #4820 status changed"
msg["From"] = formataddr(("marketplace-watch", os.environ["SMTP_FROM"]))
msg["To"] = to
with smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ["SMTP_PORT"]), timeout=30) as s:
    s.starttls()
    s.login(os.environ["SMTP_FROM"], os.environ["SMTP_PASS"])
    s.sendmail(os.environ["SMTP_FROM"], [to], msg.as_string())
print("email sent to", to)
PY
fi

git add "$STATE_FILE"
git -c user.name="marketplace-watch" -c user.email="marketplace-watch@users.noreply.github.com" \
  commit -q -m "marketplace-watch: issue #4820 status changed" || true
git push -q origin HEAD || true
