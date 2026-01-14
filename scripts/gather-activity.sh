#!/bin/bash
# Gathers daily code activity for team members across all repos in an organization

set -e

ORG="$1"
TEAM_MEMBERS="$2"
TODAY=$(date -u +%Y-%m-%d)

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
declare -A PR_COUNT

for username in "${!USERNAMES[@]}"; do
  MERGED_ADDITIONS["$username"]=0
  MERGED_DELETIONS["$username"]=0
  PR_ADDITIONS["$username"]=0
  PR_DELETIONS["$username"]=0
  COMMIT_COUNT["$username"]=0
  PR_COUNT["$username"]=0
done

# Get all repos in the organization
repos=$(gh repo list "$ORG" --limit 100 --json name --jq '.[].name')

for repo in $repos; do
  full_repo="$ORG/$repo"

  # Get commits from today for each team member
  for username in "${!USERNAMES[@]}"; do
    # Get commits by this author today
    commits=$(gh api "repos/$full_repo/commits" \
      --jq "[.[] | select(.commit.author.date | startswith(\"$TODAY\")) | select(.author.login == \"$username\")] | length" \
      2>/dev/null || echo "0")

    if [[ "$commits" -gt 0 ]]; then
      COMMIT_COUNT["$username"]=$((COMMIT_COUNT["$username"] + commits))

      # Get stats for each commit
      commit_shas=$(gh api "repos/$full_repo/commits" \
        --jq "[.[] | select(.commit.author.date | startswith(\"$TODAY\")) | select(.author.login == \"$username\") | .sha] | .[]" \
        2>/dev/null || echo "")

      for sha in $commit_shas; do
        stats=$(gh api "repos/$full_repo/commits/$sha" --jq '.stats | "\(.additions) \(.deletions)"' 2>/dev/null || echo "0 0")
        additions=$(echo "$stats" | cut -d' ' -f1)
        deletions=$(echo "$stats" | cut -d' ' -f2)
        MERGED_ADDITIONS["$username"]=$((MERGED_ADDITIONS["$username"] + additions))
        MERGED_DELETIONS["$username"]=$((MERGED_DELETIONS["$username"] + deletions))
      done
    fi
  done

  # Get open PRs by team members
  for username in "${!USERNAMES[@]}"; do
    prs=$(gh pr list --repo "$full_repo" --author "$username" --state open --json additions,deletions 2>/dev/null || echo "[]")

    pr_count=$(echo "$prs" | jq 'length')
    PR_COUNT["$username"]=$((PR_COUNT["$username"] + pr_count))

    additions=$(echo "$prs" | jq '[.[].additions] | add // 0')
    deletions=$(echo "$prs" | jq '[.[].deletions] | add // 0')

    PR_ADDITIONS["$username"]=$((PR_ADDITIONS["$username"] + additions))
    PR_DELETIONS["$username"]=$((PR_DELETIONS["$username"] + deletions))
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
        "count": ${PR_COUNT[$username]},
        "additions": ${PR_ADDITIONS[$username]},
        "deletions": ${PR_DELETIONS[$username]},
        "total": $pr_total
      },
      "grandTotal": $grand_total
    }
EOF
done

echo ""
echo "  ]"
echo "}"
