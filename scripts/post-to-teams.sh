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
  prCount=$(echo "$member" | jq -r '.openPRs.count')
  grandTotal=$(echo "$member" | jq -r '.grandTotal')

  # Format the value string
  if [[ "$mergedCommits" -gt 0 ]] || [[ "$prCount" -gt 0 ]]; then
    value="**$grandTotal lines** (Merged: +$mergedAdd/-$mergedDel"
    if [[ "$prCount" -gt 0 ]]; then
      value="$value | PRs: +$prAdd/-$prDel"
    fi
    value="$value)"
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
            "type": "TextBlock",
            "text": "**Team Total: $TEAM_TOTAL lines** (+$TEAM_ADDITIONS / -$TEAM_DELETIONS)",
            "wrap": true,
            "spacing": "Medium",
            "weight": "Bolder",
            "color": "Accent"
          },
          {
            "type": "FactSet",
            "facts": [$FACTS],
            "spacing": "Medium"
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
