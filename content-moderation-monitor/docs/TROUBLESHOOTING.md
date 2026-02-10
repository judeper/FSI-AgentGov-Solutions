# Troubleshooting

> **Status:** Stub — Troubleshooting guide will be expanded as the solution matures.

## Common Issues

### Cannot enumerate environments

**Symptom:** "Access denied" or empty environment list.

**Resolution:**
1. Verify you have Power Platform Admin or Global Admin role
2. Run `Add-PowerAppsAccount` to authenticate
3. Confirm network access to `api.bap.microsoft.com`

### Bot table query fails

**Symptom:** "Failed to query bots" warning for specific environments.

**Resolution:**
1. Verify the target environment has Dataverse provisioned
2. Confirm your identity has read access to the `bot` table
3. Check `Connect-EnvironmentDataverse.ps1` token acquisition

### Unknown moderation level

**Symptom:** Agents report `Unknown` moderation level.

**Resolution:**
- The bot's `configuration` JSON blob may not contain content moderation settings
- Check if `botcomponent` records contain moderation configuration
- Some bot types (classic PVA) may not expose moderation via the Dataverse API
