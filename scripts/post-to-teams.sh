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

# Calculate team totals
TEAM_LINES=$(echo "$REPORT_DATA" | jq '[.team[].totalLines] | add // 0')
TEAM_COMMITS=$(echo "$REPORT_DATA" | jq '[.team[].commits] | add // 0')
TEAM_PRS_CREATED=$(echo "$REPORT_DATA" | jq '[.team[].prsCreated] | add // 0')
TEAM_PRS_MERGED=$(echo "$REPORT_DATA" | jq '[.team[].prsMerged] | add // 0')
TEAM_ISSUES_CREATED=$(echo "$REPORT_DATA" | jq '[.team[].issuesCreated] | add // 0')
TEAM_ISSUES_CLOSED=$(echo "$REPORT_DATA" | jq '[.team[].issuesClosed] | add // 0')

# Build individual member sections
MEMBER_BLOCKS=""
while IFS= read -r member; do
  displayName=$(echo "$member" | jq -r '.displayName')
  linesAdded=$(echo "$member" | jq -r '.linesAdded')
  linesRemoved=$(echo "$member" | jq -r '.linesRemoved')
  totalLines=$(echo "$member" | jq -r '.totalLines')
  commits=$(echo "$member" | jq -r '.commits')
  prsCreated=$(echo "$member" | jq -r '.prsCreated')
  prsMerged=$(echo "$member" | jq -r '.prsMerged')
  issuesCreated=$(echo "$member" | jq -r '.issuesCreated')
  issuesClosed=$(echo "$member" | jq -r '.issuesClosed')
  repos=$(echo "$member" | jq -r '.repos | join(", ")')

  # Check if there's any activity
  hasActivity=false
  if [[ "$totalLines" -gt 0 ]] || [[ "$prsCreated" -gt 0 ]] || [[ "$prsMerged" -gt 0 ]] || [[ "$issuesCreated" -gt 0 ]] || [[ "$issuesClosed" -gt 0 ]]; then
    hasActivity=true
  fi

  if [[ "$hasActivity" == "true" ]]; then
    if [[ "$totalLines" -gt 0 ]]; then
      codeText="+$linesAdded / -$linesRemoved ($commits commits)"
    else
      codeText="—"
    fi
    prText="$prsCreated created / $prsMerged merged"
    issueText="$issuesCreated created / $issuesClosed closed"
    if [[ -n "$repos" ]]; then
      reposText="$repos"
    else
      reposText="—"
    fi
  else
    codeText="—"
    prText="—"
    issueText="—"
    reposText="—"
  fi

  if [[ -n "$MEMBER_BLOCKS" ]]; then
    MEMBER_BLOCKS="$MEMBER_BLOCKS,"
  fi

  MEMBER_BLOCKS="$MEMBER_BLOCKS
          {
            \"type\": \"Container\",
            \"spacing\": \"Medium\",
            \"separator\": true,
            \"items\": [
              {
                \"type\": \"TextBlock\",
                \"text\": \"$displayName\",
                \"weight\": \"Bolder\",
                \"size\": \"Medium\"
              },
              {
                \"type\": \"ColumnSet\",
                \"spacing\": \"Small\",
                \"columns\": [
                  {
                    \"type\": \"Column\",
                    \"width\": \"stretch\",
                    \"items\": [
                      {
                        \"type\": \"TextBlock\",
                        \"text\": \"Code\",
                        \"isSubtle\": true,
                        \"size\": \"Small\"
                      },
                      {
                        \"type\": \"TextBlock\",
                        \"text\": \"$codeText\",
                        \"spacing\": \"None\",
                        \"wrap\": true
                      }
                    ]
                  },
                  {
                    \"type\": \"Column\",
                    \"width\": \"stretch\",
                    \"items\": [
                      {
                        \"type\": \"TextBlock\",
                        \"text\": \"PRs\",
                        \"isSubtle\": true,
                        \"size\": \"Small\"
                      },
                      {
                        \"type\": \"TextBlock\",
                        \"text\": \"$prText\",
                        \"spacing\": \"None\",
                        \"wrap\": true
                      }
                    ]
                  },
                  {
                    \"type\": \"Column\",
                    \"width\": \"stretch\",
                    \"items\": [
                      {
                        \"type\": \"TextBlock\",
                        \"text\": \"Issues\",
                        \"isSubtle\": true,
                        \"size\": \"Small\"
                      },
                      {
                        \"type\": \"TextBlock\",
                        \"text\": \"$issueText\",
                        \"spacing\": \"None\",
                        \"wrap\": true
                      }
                    ]
                  }
                ]
              },
              {
                \"type\": \"TextBlock\",
                \"text\": \"Repos: $reposText\",
                \"isSubtle\": true,
                \"size\": \"Small\",
                \"wrap\": true,
                \"spacing\": \"Small\"
              }
            ]
          }"
done < <(echo "$REPORT_DATA" | jq -c '.team | sort_by(-.totalLines) | .[]')

# Create the Teams Adaptive Card payload with full width
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
        "msteams": {
          "width": "Full"
        },
        "body": [
          {
            "type": "TextBlock",
            "size": "Large",
            "weight": "Bolder",
            "text": "Daily Team Activity Report"
          },
          {
            "type": "TextBlock",
            "text": "$DATE | $ORG",
            "isSubtle": true,
            "spacing": "None"
          },
          {
            "type": "Container",
            "style": "emphasis",
            "spacing": "Medium",
            "items": [
              {
                "type": "TextBlock",
                "text": "Team Totals",
                "weight": "Bolder"
              },
              {
                "type": "ColumnSet",
                "columns": [
                  {
                    "type": "Column",
                    "width": "stretch",
                    "items": [
                      {
                        "type": "TextBlock",
                        "text": "Code",
                        "isSubtle": true,
                        "size": "Small"
                      },
                      {
                        "type": "TextBlock",
                        "text": "$TEAM_LINES lines ($TEAM_COMMITS commits)",
                        "weight": "Bolder",
                        "color": "Accent",
                        "spacing": "None"
                      }
                    ]
                  },
                  {
                    "type": "Column",
                    "width": "stretch",
                    "items": [
                      {
                        "type": "TextBlock",
                        "text": "PRs",
                        "isSubtle": true,
                        "size": "Small"
                      },
                      {
                        "type": "TextBlock",
                        "text": "$TEAM_PRS_CREATED created / $TEAM_PRS_MERGED merged",
                        "weight": "Bolder",
                        "color": "Accent",
                        "spacing": "None"
                      }
                    ]
                  },
                  {
                    "type": "Column",
                    "width": "stretch",
                    "items": [
                      {
                        "type": "TextBlock",
                        "text": "Issues",
                        "isSubtle": true,
                        "size": "Small"
                      },
                      {
                        "type": "TextBlock",
                        "text": "$TEAM_ISSUES_CREATED created / $TEAM_ISSUES_CLOSED closed",
                        "weight": "Bolder",
                        "color": "Accent",
                        "spacing": "None"
                      }
                    ]
                  }
                ]
              }
            ]
          },
          $MEMBER_BLOCKS
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
