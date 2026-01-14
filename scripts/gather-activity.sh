#!/bin/bash
# Gathers daily code activity for team members across all repos in an organization

set -e

ORG="$1"
TEAM_MEMBERS="$2"

# Use Central Time for date calculation
export TZ="America/Chicago"
TODAY=$(date +%Y-%m-%d)

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

# Initialize results
declare -A MERGED_ADDITIONS
declare -A MERGED_DELETIONS
declare -A PR_ADDITIONS
declare -A PR_DELETIONS
declare -A COMMIT_COUNT
declare -A OPEN_PR_COUNT
declare -A PRS_CREATED
declare -A PRS_CLOSED
declare -A ISSUES_CREATED
declare -A ISSUES_CLOSED
declare -A REPOS_CONTRIBUTED

for username in "${!USERNAMES[@]}"; do
  MERGED_ADDITIONS["$username"]=0
  MERGED_DELETIONS["$username"]=0
  PR_ADDITIONS["$username"]=0
  PR_DELETIONS["$username"]=0
  COMMIT_COUNT["$username"]=0
  OPEN_PR_COUNT["$username"]=0
  PRS_CREATED["$username"]=0
  PRS_CLOSED["$username"]=0
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

  # Get commits from today for each team member
  for username in "${!USERNAMES[@]}"; do
    # Get commits by this author today (using Central time date)
    commits=$(gh api "repos/$full_repo/commits?since=${TODAY}T00:00:00-06:00&until=${TODAY}T23:59:59-06:00&author=$username&per_page=100" \
      --jq 'length' \
      2>/dev/null || echo "0")

    if [[ "$commits" -gt 0 ]]; then
      COMMIT_COUNT["$username"]=$((COMMIT_COUNT["$username"] + commits))
      add_repo "$username" "$repo"

      # Get stats for each commit
      commit_shas=$(gh api "repos/$full_repo/commits?since=${TODAY}T00:00:00-06:00&until=${TODAY}T23:59:59-06:00&author=$username&per_page=100" \
        --jq '.[].sha' \
        2>/dev/null || echo "")

      for sha in $commit_shas; do
        stats=$(gh api "repos/$full_repo/commits/$sha" --jq '.stats | "\(.additions // 0) \(.deletions // 0)"' 2>/dev/null || echo "0 0")
        additions=$(echo "$stats" | cut -d' ' -f1)
        deletions=$(echo "$stats" | cut -d' ' -f2)
        MERGED_ADDITIONS["$username"]=$((MERGED_ADDITIONS["$username"] + additions))
        MERGED_DELETIONS["$username"]=$((MERGED_DELETIONS["$username"] + deletions))
      done
    fi
  done

  # Get open PRs by team members (for line counts)
  for username in "${!USERNAMES[@]}"; do
    prs=$(gh pr list --repo "$full_repo" --author "$username" --state open --json additions,deletions 2>/dev/null || echo "[]")

    pr_count=$(echo "$prs" | jq 'length')
    if [[ "$pr_count" -gt 0 ]]; then
      OPEN_PR_COUNT["$username"]=$((OPEN_PR_COUNT["$username"] + pr_count))
      add_repo "$username" "$repo"

      additions=$(echo "$prs" | jq '[.[].additions] | add // 0')
      deletions=$(echo "$prs" | jq '[.[].deletions] | add // 0')

      PR_ADDITIONS["$username"]=$((PR_ADDITIONS["$username"] + additions))
      PR_DELETIONS["$username"]=$((PR_DELETIONS["$username"] + deletions))
    fi
  done

  # Get PRs created today by team members
  for username in "${!USERNAMES[@]}"; do
    prs_created=$(gh api "repos/$full_repo/pulls?state=all&sort=created&direction=desc&per_page=50" \
      --jq "[.[] | select(.created_at >= \"${TODAY}T00:00:00\" and .created_at <= \"${TODAY}T23:59:59\") | select(.user.login == \"$username\")] | length" \
      2>/dev/null || echo "0")
    if [[ "$prs_created" -gt 0 ]]; then
      PRS_CREATED["$username"]=$((PRS_CREATED["$username"] + prs_created))
      add_repo "$username" "$repo"
    fi
  done

  # Get PRs closed/merged today by team members
  for username in "${!USERNAMES[@]}"; do
    prs_closed=$(gh api "repos/$full_repo/pulls?state=closed&sort=updated&direction=desc&per_page=50" \
      --jq "[.[] | select(.closed_at >= \"${TODAY}T00:00:00\" and .closed_at <= \"${TODAY}T23:59:59\") | select(.user.login == \"$username\")] | length" \
      2>/dev/null || echo "0")
    if [[ "$prs_closed" -gt 0 ]]; then
      PRS_CLOSED["$username"]=$((PRS_CLOSED["$username"] + prs_closed))
      add_repo "$username" "$repo"
    fi
  done

  # Get issues created today by team members
  for username in "${!USERNAMES[@]}"; do
    issues_created=$(gh api "repos/$full_repo/issues?state=all&sort=created&direction=desc&per_page=50&creator=$username" \
      --jq "[.[] | select(.created_at >= \"${TODAY}T00:00:00\" and .created_at <= \"${TODAY}T23:59:59\") | select(.pull_request == null)] | length" \
      2>/dev/null || echo "0")
    if [[ "$issues_created" -gt 0 ]]; then
      ISSUES_CREATED["$username"]=$((ISSUES_CREATED["$username"] + issues_created))
      add_repo "$username" "$repo"
    fi
  done

  # Get issues closed today by team members (as assignee)
  for username in "${!USERNAMES[@]}"; do
    issues_closed=$(gh api "repos/$full_repo/issues?state=closed&sort=updated&direction=desc&per_page=50&assignee=$username" \
      --jq "[.[] | select(.closed_at >= \"${TODAY}T00:00:00\" and .closed_at <= \"${TODAY}T23:59:59\") | select(.pull_request == null)] | length" \
      2>/dev/null || echo "0")
    if [[ "$issues_closed" -gt 0 ]]; then
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

  merged_total=$((MERGED_ADDITIONS["$username"] + MERGED_DELETIONS["$username"]))
  pr_total=$((PR_ADDITIONS["$username"] + PR_DELETIONS["$username"]))
  grand_total=$((merged_total + pr_total))

  # Convert comma-separated repos to JSON array
  repos_json="[]"
  if [[ -n "${REPOS_CONTRIBUTED[$username]}" ]]; then
    repos_json=$(echo "${REPOS_CONTRIBUTED[$username]}" | tr ',' '\n' | sort -u | jq -R . | jq -s .)
  fi

  cat << EOF
    {
      "username": "$username",
      "displayName": "${DISPLAY_NAMES[$username]}",
      "merged": {
        "commits": ${COMMIT_COUNT[$username]},
        "additions": ${MERGED_ADDITIONS[$username]},
        "deletions": ${MERGED_DELETIONS[$username]},
        "total": $merged_total
      },
      "openPRs": {
        "count": ${OPEN_PR_COUNT[$username]},
        "additions": ${PR_ADDITIONS[$username]},
        "deletions": ${PR_DELETIONS[$username]},
        "total": $pr_total
      },
      "prsCreated": ${PRS_CREATED[$username]},
      "prsClosed": ${PRS_CLOSED[$username]},
      "issuesCreated": ${ISSUES_CREATED[$username]},
      "issuesClosed": ${ISSUES_CLOSED[$username]},
      "repos": $repos_json,
      "grandTotal": $grand_total
    }
EOF
done

echo ""
echo "  ]"
echo "}"
