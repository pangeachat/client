#!/usr/bin/env bash
# The per-PR preview's sticky comment (deployment.instructions.md → Preview Deploys).
#
# One bot comment per PR. Its first line is the machine-readable marker every
# preview_deploy.yaml job reads back, so "is this PR armed, and at which commit?"
# is one GitHub API call and needs no cloud credentials:
#
#   <!-- pangea-preview state=<armed|building|failed|off> sha=<full head sha> -->
#
# Usage (needs GH_TOKEN and GH_REPO):
#   preview_sticky_comment.sh read  <pr>                       # prints "<state> <sha>", or nothing
#   preview_sticky_comment.sh write <pr> <state> <sha> <file>  # upsert: marker line + file contents
set -euo pipefail

MARKER='<!-- pangea-preview'
cmd=$1
pr=$2

# The bot's sticky comment, as "<id>\t<first line>" — empty when there is none.
sticky() {
  gh api --paginate "repos/$GH_REPO/issues/$pr/comments" \
    --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$MARKER\"))) | \"\(.id)\t\(.body | split(\"\n\")[0])\"" \
    | head -1
}

case "$cmd" in
  read)
    sticky | sed -nE 's/^[0-9]+\t<!-- pangea-preview state=([a-z]+) sha=([0-9a-f]+) -->.*/\1 \2/p'
    ;;
  write)
    state=$3; sha=$4; body_file=$5
    tmp=$(mktemp)
    { printf '%s state=%s sha=%s -->\n' "$MARKER" "$state" "$sha"; cat "$body_file"; } > "$tmp"
    id=$(sticky | cut -f1)
    if [ -n "$id" ]; then
      gh api -X PATCH "repos/$GH_REPO/issues/comments/$id" -F body=@"$tmp" >/dev/null
    else
      gh api -X POST "repos/$GH_REPO/issues/$pr/comments" -F body=@"$tmp" >/dev/null
    fi
    rm -f "$tmp"
    ;;
  *)
    echo "usage: $0 read <pr> | write <pr> <state> <sha> <body-file>" >&2
    exit 2
    ;;
esac
