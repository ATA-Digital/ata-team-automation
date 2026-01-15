#!/bin/bash
# Gathers daily code activity for team members across all repos in an organization

set -e

ORG="$1"
TEAM_MEMBERS="$2"

# Use Central Time for date calculation
export TZ="America/Chicago"
TODAY=$(date +%Y-%m-%d)

echo "Gathering activity for $TODAY (Central Time)" >&2

# Parse team members into arrays
declare -A USERNAMES
declare -A DISPLAY_NAMES

while IFS= read -r line; do
  if [[ -n "$line" ]]; then
    username=$(echo "$line" | cut -d: -f1)
    displayname=$(echo "$line" | cut -d: -f2)
    USERNAMES["$username"]=1
    DISPLAY_NAMES["$username"]="$displayname"
  fi
done <<< "$TEAM_MEMBERS"

# Initialize results - only tracking TODAY's activity
declare -A LINES_ADDED
declare -A LINES_REMOVED
declare -A COMMIT_COUNT
declare -A PRS_CREATED
declare -A PRS_MERGED
declare -A ISSUES_CREATED
declare -A ISSUES_CLOSED
declare -A REPOS_CONTRIBUTED

for username in "${!USERNAMES[@]}"; do
  LINES_ADDED["$username"]=0
  LINES_REMOVED["$username"]=0
  COMMIT_COUNT["$username"]=0
  PRS_CREATED["$username"]=0
  PRS_MERGED["$username"]=0
  ISSUES_CREATED["$username"]=0
  ISSUES_CLOSED["$username"]=0
  REPOS_CONTRIBUTED["$username"]=""
done

# Helper function to add repo to user's list
add_repo() {
  local username="$1"
  local repo="$2"
  if [[ -z "${REPOS_CONTRIBUTED[$username]}" ]]; then
    REPOS_CONTRIBUTED["$username"]="$repo"
  elif [[ ! "${REPOS_CONTRIBUTED[$username]}" =~ (^|,)$repo(,|$) ]]; then
    REPOS_CONTRIBUTED["$username"]="${REPOS_CONTRIBUTED[$username]},$repo"
  fi
}

# Get all repos in the organization
repos=$(gh repo list "$ORG" --limit 100 --json name --jq '.[].name')

for repo in $repos; do
  full_repo="$ORG/$repo"
  echo "Scanning $repo..." >&2

  # Get commits merged TODAY for each team member
  for username in "${!USERNAMES[@]}"; do
    # Use committer date (when merged to main) with proper ISO8601 format
    commits_data=$(gh api "repos/$full_repo/commits" \
      --jq "[.[] | select(.commit.committer.date | . >= \"${TODAY}T00:00:00\" and . < \"${TODAY}T23:59:59\") | select(.author.login == \"$username\")]" \
      2>/dev/null || echo "[]")

    commit_count=$(echo "$commits_data" | jq 'length')

    if [[ "$commit_count" -gt 0 ]]; then
      echo "  Found $commit_count commits by $username" >&2
      COMMIT_COUNT["$username"]=$((COMMIT_COUNT["$username"] + commit_count))
      add_repo "$username" "$repo"

      # Get stats for each commit
      for sha in $(echo "$commits_data" | jq -r '.[].sha'); do
        stats=$(gh api "repos/$full_repo/commits/$sha" --jq '.stats | "\(.additions // 0) \(.deletions // 0)"' 2>/dev/null || echo "0 0")
        additions=$(echo "$stats" | cut -d' ' -f1)
        deletions=$(echo "$stats" | cut -d' ' -f2)
        LINES_ADDED["$username"]=$((LINES_ADDED["$username"] + additions))
        LINES_REMOVED["$username"]=$((LINES_REMOVED["$username"] + deletions))
      done
    fi
  done

  # Get PRs CREATED today by team members
  for username in "${!USERNAMES[@]}"; do
    prs_created=$(gh api "repos/$full_repo/pulls?state=all&sort=created&direction=desc&per_page=100" \
      --jq "[.[] | select(.created_at >= \"${TODAY}T00:00:00\" and .created_at < \"${TODAY}T23:59:59\") | select(.user.login == \"$username\")] | length" \
      2>/dev/null || echo "0")

    if [[ "$prs_created" -gt 0 ]]; then
      echo "  $username created $prs_created PRs" >&2
      PRS_CREATED["$username"]=$((PRS_CREATED["$username"] + prs_created))
      add_repo "$username" "$repo"
    fi
  done

  # Get PRs MERGED today by team members
  for username in "${!USERNAMES[@]}"; do
    prs_merged=$(gh api "repos/$full_repo/pulls?state=closed&sort=updated&direction=desc&per_page=100" \
      --jq "[.[] | select(.merged_at != null) | select(.merged_at >= \"${TODAY}T00:00:00\" and .merged_at < \"${TODAY}T23:59:59\") | select(.user.login == \"$username\")] | length" \
      2>/dev/null || echo "0")

    if [[ "$prs_merged" -gt 0 ]]; then
      echo "  $username merged $prs_merged PRs" >&2
      PRS_MERGED["$username"]=$((PRS_MERGED["$username"] + prs_merged))
      add_repo "$username" "$repo"
    fi
  done

  # Get issues CREATED today by team members
  for username in "${!USERNAMES[@]}"; do
    issues_created=$(gh api "repos/$full_repo/issues?state=all&sort=created&direction=desc&per_page=100&creator=$username" \
      --jq "[.[] | select(.pull_request == null) | select(.created_at >= \"${TODAY}T00:00:00\" and .created_at < \"${TODAY}T23:59:59\")] | length" \
      2>/dev/null || echo "0")

    if [[ "$issues_created" -gt 0 ]]; then
      echo "  $username created $issues_created issues" >&2
      ISSUES_CREATED["$username"]=$((ISSUES_CREATED["$username"] + issues_created))
      add_repo "$username" "$repo"
    fi
  done

  # Get issues CLOSED today by team members (as assignee)
  for username in "${!USERNAMES[@]}"; do
    issues_closed=$(gh api "repos/$full_repo/issues?state=closed&sort=updated&direction=desc&per_page=100&assignee=$username" \
      --jq "[.[] | select(.pull_request == null) | select(.closed_at >= \"${TODAY}T00:00:00\" and .closed_at < \"${TODAY}T23:59:59\")] | length" \
      2>/dev/null || echo "0")

    if [[ "$issues_closed" -gt 0 ]]; then
      echo "  $username closed $issues_closed issues" >&2
      ISSUES_CLOSED["$username"]=$((ISSUES_CLOSED["$username"] + issues_closed))
      add_repo "$username" "$repo"
    fi
  done
done

# Output JSON report
echo "{"
echo "  \"date\": \"$TODAY\","
echo "  \"organization\": \"$ORG\","
echo "  \"team\": ["

first=true
for username in "${!USERNAMES[@]}"; do
  if [ "$first" = true ]; then
    first=false
  else
    echo ","
  fi

  total_lines=$((LINES_ADDED["$username"] + LINES_REMOVED["$username"]))

  # Convert comma-separated repos to JSON array
  repos_json="[]"
  if [[ -n "${REPOS_CONTRIBUTED[$username]}" ]]; then
    repos_json=$(echo "${REPOS_CONTRIBUTED[$username]}" | tr ',' '\n' | sort -u | jq -R . | jq -s .)
  fi

  cat << EOF
    {
      "username": "$username",
      "displayName": "${DISPLAY_NAMES[$username]}",
      "linesAdded": ${LINES_ADDED[$username]},
      "linesRemoved": ${LINES_REMOVED[$username]},
      "totalLines": $total_lines,
      "commits": ${COMMIT_COUNT[$username]},
      "prsCreated": ${PRS_CREATED[$username]},
      "prsMerged": ${PRS_MERGED[$username]},
      "issuesCreated": ${ISSUES_CREATED[$username]},
      "issuesClosed": ${ISSUES_CLOSED[$username]},
      "repos": $repos_json
    }
EOF
done

echo ""
echo "  ]"
echo "}"
