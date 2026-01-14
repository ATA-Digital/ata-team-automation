#!/bin/bash
# Posts team activity report to Microsoft Teams via webhook

set -e

if [[ -z "$TEAMS_WEBHOOK_URL" ]]; then
  echo "Error: TEAMS_WEBHOOK_URL is not set"
  exit 1
fi

if [[ -z "$REPORT_DATA" ]]; then
  echo "Error: REPORT_DATA is not set"
  exit 1
fi

# Parse report data
DATE=$(echo "$REPORT_DATA" | jq -r '.date')
ORG=$(echo "$REPORT_DATA" | jq -r '.organization')

# Build the facts array for each team member, sorted by grandTotal descending
FACTS=""
while IFS= read -r member; do
  displayName=$(echo "$member" | jq -r '.displayName')
  mergedAdd=$(echo "$member" | jq -r '.merged.additions')
  mergedDel=$(echo "$member" | jq -r '.merged.deletions')
  mergedCommits=$(echo "$member" | jq -r '.merged.commits')
  prAdd=$(echo "$member" | jq -r '.openPRs.additions')
  prDel=$(echo "$member" | jq -r '.openPRs.deletions')
  openPrCount=$(echo "$member" | jq -r '.openPRs.count')
  prsCreated=$(echo "$member" | jq -r '.prsCreated')
  prsClosed=$(echo "$member" | jq -r '.prsClosed')
  issuesCreated=$(echo "$member" | jq -r '.issuesCreated')
  issuesClosed=$(echo "$member" | jq -r '.issuesClosed')
  grandTotal=$(echo "$member" | jq -r '.grandTotal')

  # Build activity parts
  parts=()

  # Code changes
  if [[ "$grandTotal" -gt 0 ]]; then
    parts+=("**$grandTotal lines** (+$mergedAdd/-$mergedDel merged")
    if [[ "$openPrCount" -gt 0 ]]; then
      parts[0]="${parts[0]}, +$prAdd/-$prDel in PRs)"
    else
      parts[0]="${parts[0]})"
    fi
  fi

  # PRs
  if [[ "$prsCreated" -gt 0 ]] || [[ "$prsClosed" -gt 0 ]]; then
    pr_part="PRs:"
    if [[ "$prsCreated" -gt 0 ]]; then
      pr_part="$pr_part $prsCreated opened"
    fi
    if [[ "$prsClosed" -gt 0 ]]; then
      if [[ "$prsCreated" -gt 0 ]]; then
        pr_part="$pr_part,"
      fi
      pr_part="$pr_part $prsClosed closed"
    fi
    parts+=("$pr_part")
  fi

  # Issues
  if [[ "$issuesCreated" -gt 0 ]] || [[ "$issuesClosed" -gt 0 ]]; then
    issue_part="Issues:"
    if [[ "$issuesCreated" -gt 0 ]]; then
      issue_part="$issue_part $issuesCreated opened"
    fi
    if [[ "$issuesClosed" -gt 0 ]]; then
      if [[ "$issuesCreated" -gt 0 ]]; then
        issue_part="$issue_part,"
      fi
      issue_part="$issue_part $issuesClosed closed"
    fi
    parts+=("$issue_part")
  fi

  # Join parts or show no activity
  if [[ ${#parts[@]} -gt 0 ]]; then
    value=$(IFS=' | '; echo "${parts[*]}")
  else
    value="No activity"
  fi

  if [[ -n "$FACTS" ]]; then
    FACTS="$FACTS,"
  fi
  FACTS="$FACTS{\"name\": \"$displayName\", \"value\": \"$value\"}"
done < <(echo "$REPORT_DATA" | jq -c '.team | sort_by(-.grandTotal) | .[]')

# Calculate team totals
TEAM_TOTAL=$(echo "$REPORT_DATA" | jq '[.team[].grandTotal] | add')
TEAM_ADDITIONS=$(echo "$REPORT_DATA" | jq '[.team[].merged.additions, .team[].openPRs.additions] | add')
TEAM_DELETIONS=$(echo "$REPORT_DATA" | jq '[.team[].merged.deletions, .team[].openPRs.deletions] | add')
TEAM_PRS_CREATED=$(echo "$REPORT_DATA" | jq '[.team[].prsCreated] | add')
TEAM_PRS_CLOSED=$(echo "$REPORT_DATA" | jq '[.team[].prsClosed] | add')
TEAM_ISSUES_CREATED=$(echo "$REPORT_DATA" | jq '[.team[].issuesCreated] | add')
TEAM_ISSUES_CLOSED=$(echo "$REPORT_DATA" | jq '[.team[].issuesClosed] | add')

# Create the Teams Adaptive Card payload
PAYLOAD=$(cat << EOF
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": {
        "\$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": [
          {
            "type": "TextBlock",
            "size": "Large",
            "weight": "Bolder",
            "text": "Daily Team Activity Report",
            "style": "heading"
          },
          {
            "type": "TextBlock",
            "text": "$DATE | $ORG",
            "isSubtle": true,
            "spacing": "None"
          },
          {
            "type": "ColumnSet",
            "spacing": "Medium",
            "columns": [
              {
                "type": "Column",
                "width": "auto",
                "items": [
                  {
                    "type": "TextBlock",
                    "text": "**Code**",
                    "weight": "Bolder",
                    "color": "Accent"
                  },
                  {
                    "type": "TextBlock",
                    "text": "$TEAM_TOTAL lines",
                    "spacing": "None"
                  }
                ]
              },
              {
                "type": "Column",
                "width": "auto",
                "items": [
                  {
                    "type": "TextBlock",
                    "text": "**PRs**",
                    "weight": "Bolder",
                    "color": "Accent"
                  },
                  {
                    "type": "TextBlock",
                    "text": "$TEAM_PRS_CREATED opened / $TEAM_PRS_CLOSED closed",
                    "spacing": "None"
                  }
                ]
              },
              {
                "type": "Column",
                "width": "auto",
                "items": [
                  {
                    "type": "TextBlock",
                    "text": "**Issues**",
                    "weight": "Bolder",
                    "color": "Accent"
                  },
                  {
                    "type": "TextBlock",
                    "text": "$TEAM_ISSUES_CREATED opened / $TEAM_ISSUES_CLOSED closed",
                    "spacing": "None"
                  }
                ]
              }
            ]
          },
          {
            "type": "TextBlock",
            "text": "**Individual Activity**",
            "weight": "Bolder",
            "spacing": "Medium"
          },
          {
            "type": "FactSet",
            "facts": [$FACTS],
            "spacing": "Small"
          }
        ]
      }
    }
  ]
}
EOF
)

# Send to Teams
response=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$TEAMS_WEBHOOK_URL")

http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [[ "$http_code" -ge 200 ]] && [[ "$http_code" -lt 300 ]]; then
  echo "Successfully posted to Teams"
else
  echo "Failed to post to Teams. HTTP $http_code: $body"
  exit 1
fi
