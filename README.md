# ATA Team Automation

Automated tooling for the ATA-Digital team, including daily activity reporting.

## Daily Team Activity Report

Posts a daily summary of code activity to Microsoft Teams for the development team.

### What It Reports

For each team member, the report includes:
- **Merged commits**: Lines added/removed in commits pushed to main branches today
- **Open PRs**: Lines added/removed in currently open pull requests
- **Total**: Combined activity across all repos in the ATA-Digital organization

### Schedule

Runs automatically at **6:00 PM ET** Monday through Friday.

Can also be triggered manually via the Actions tab.

## Setup

### 1. Create a Teams Incoming Webhook

1. In Microsoft Teams, go to the channel where you want reports posted
2. Click the **...** menu > **Connectors**
3. Search for **Incoming Webhook** and click **Configure**
4. Give it a name (e.g., "Daily Activity Report") and optionally upload an icon
5. Click **Create** and copy the webhook URL

### 2. Add GitHub Secrets

Go to this repo's **Settings** > **Secrets and variables** > **Actions** and add:

| Secret | Description |
|--------|-------------|
| `TEAMS_WEBHOOK_URL` | The webhook URL from step 1 |
| `ORG_READ_TOKEN` | A GitHub PAT with `repo` and `read:org` scopes |

#### Creating the ORG_READ_TOKEN

1. Go to GitHub **Settings** > **Developer settings** > **Personal access tokens** > **Fine-grained tokens**
2. Click **Generate new token**
3. Set:
   - **Token name**: `ata-team-automation`
   - **Expiration**: 1 year (or your preference)
   - **Resource owner**: `ATA-Digital`
   - **Repository access**: All repositories
   - **Permissions**:
     - Repository permissions:
       - Contents: Read-only
       - Pull requests: Read-only
       - Metadata: Read-only
4. Click **Generate token** and copy it

### 3. Update Team Members (Optional)

To modify the list of team members, edit the `TEAM_MEMBERS` environment variable in `.github/workflows/daily-team-report.yml`:

```yaml
env:
  TEAM_MEMBERS: |
    github-username:Display Name
    another-user:Another Name
```

## Manual Trigger

To run the report manually:

1. Go to **Actions** tab
2. Select **Daily Team Activity Report**
3. Click **Run workflow**
4. Select the branch and click **Run workflow**

## Troubleshooting

### No data showing for a team member

- Verify their GitHub username matches exactly (case-sensitive)
- Ensure they have commits/PRs in repos within the ATA-Digital organization

### Webhook not posting

- Verify the `TEAMS_WEBHOOK_URL` secret is set correctly
- Check the Actions run logs for error messages
- Ensure the webhook hasn't been deleted in Teams

### Rate limiting

The GitHub API has rate limits. If you have many repos or team members, you may need to:
- Use a GitHub App token instead of a PAT (higher rate limits)
- Adjust the workflow to run less frequently
