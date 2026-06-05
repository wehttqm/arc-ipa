# Atlantis Workflow Guide

This guide covers how to use Atlantis for managing Terraform infrastructure through GitHub Pull Requests.

## Table of Contents

- [Overview](#overview)
- [Daily Workflow](#daily-workflow)
- [Making Infrastructure Changes](#making-infrastructure-changes)
- [Atlantis Commands](#atlantis-commands)
- [Advanced Workflows](#advanced-workflows)
- [Troubleshooting](#troubleshooting)

## Overview

Atlantis automates Terraform workflows through GitHub Pull Requests. When you open a PR with infrastructure changes, Atlantis automatically:

1. Detects which Terraform projects are affected
2. Runs `terraform plan` for each project
3. Posts plan results as PR comments
4. Allows you to apply changes via PR comments

### Architecture

```
GitHub PR → Atlantis Gateway → Atlantis Instance → AWS Resources
```

- **GitHub App**: Sends webhooks for PR events
- **Atlantis Gateway**: Routes webhooks to correct Atlantis instance
- **Atlantis**: Runs Terraform commands and posts results
- **AWS**: Target infrastructure

## Daily Workflow

### 1. Making Changes

Create a branch and make your infrastructure changes:

```bash
# Create feature branch
git checkout -b feature/add-new-vpc

# Make changes to Terraform files
vim vpc/terraform/main.tf
vim vpc/terraform/workspaces/pf-sandbox-usw2.tfvars.json

# Commit changes
git add .
git commit -m "Add new VPC configuration"
git push origin feature/add-new-vpc
```

### 2. Open Pull Request

1. Go to GitHub and create a PR from your branch to `main`
2. Atlantis automatically detects changes and runs plans
3. Wait for plan results in PR comments

### 3. Review Plan Output

Atlantis posts a comment with plan results:

```
Ran Plan for 2 projects:

1. project: vpc-pf-sandbox-usw2 dir: vpc/terraform workspace: pf-sandbox-usw2
   ✅ Plan: 3 to add, 1 to change, 0 to destroy

2. project: eks-pf-sandbox-usw2 dir: eks/terraform workspace: pf-sandbox-usw2
   ✅ Plan: 0 to add, 0 to change, 0 to destroy
```

Click "Show Output" to see detailed plan.

### 4. Apply Changes

Once plan looks good and PR is approved:

```
atlantis apply
```

Atlantis will:

- Run `terraform apply` for all planned projects
- Post apply results in PR comments
- Mark projects as applied

### 5. Merge PR

After successful apply:

1. Verify changes in AWS console
2. Merge the PR
3. Delete the feature branch

## Making Infrastructure Changes

### Adding a New Component

To add a new Terraform component (e.g., RDS):

```bash
# Create directory structure
mkdir -p rds/terraform/workspaces

# Create Terraform files
cat > rds/terraform/main.tf <<EOF
# RDS configuration
resource "aws_db_instance" "main" {
  # ...
}
EOF

# Create workspace config
cat > rds/terraform/workspaces/pf-sandbox-usw2.tfvars.json <<EOF
{
  "region": "us-west-2",
  "env": "pf-sandbox"
}
EOF

# Commit and push
git add rds/
git commit -m "Add RDS component"
git push
```

Atlantis will automatically detect the new component on your next PR.

### Modifying Existing Infrastructure

```bash
# Edit Terraform files
vim eks/terraform/main.tf

# Or edit workspace variables
vim eks/terraform/workspaces/pf-sandbox-usw2.tfvars.json

# Commit and push
git add eks/
git commit -m "Update EKS node group size"
git push
```

### Adding a New Workspace

To deploy to a new environment:

```bash
# Create new workspace config
cp vpc/terraform/workspaces/pf-sandbox-usw2.tfvars.json \
   vpc/terraform/workspaces/omni-prod-use1.tfvars.json

# Update values for new environment
vim vpc/terraform/workspaces/omni-prod-use1.tfvars.json

# Enable in Atlantis config
vim atlantis/conf/enabled_contexts.json
# Add "omni-prod-use1" to the list

# Commit and push
git add .
git commit -m "Add production workspace"
git push
```

## Atlantis Commands

All commands are posted as PR comments. Atlantis responds to these commands:

### Basic Commands

| Command                     | Description                   | Example                                 |
| --------------------------- | ----------------------------- | --------------------------------------- |
| `atlantis plan`             | Run plan for all projects     | `atlantis plan`                         |
| `atlantis plan -p PROJECT`  | Run plan for specific project | `atlantis plan -p vpc-pf-sandbox-usw2`  |
| `atlantis apply`            | Apply all planned projects    | `atlantis apply`                        |
| `atlantis apply -p PROJECT` | Apply specific project        | `atlantis apply -p vpc-pf-sandbox-usw2` |
| `atlantis unlock`           | Unlock all projects           | `atlantis unlock`                       |

### Advanced Commands

```bash
# Re-run plan after making changes
atlantis plan

# Plan specific project only
atlantis plan -p eks-pf-sandbox-usw2

# Apply with auto-merge (if configured)
atlantis apply --auto-merge

# Force unlock (use with caution)
atlantis unlock

# Get help
atlantis help
```

### Command Flags

- `-p, --project`: Target specific project
- `-d, --dir`: Target specific directory
- `-w, --workspace`: Target specific workspace
- `--verbose`: Show detailed output

## Advanced Workflows

### Working with Multiple Projects

When your PR affects multiple projects:

```bash
# Plan all projects
atlantis plan

# Review each plan output

# Apply specific project first
atlantis apply -p vpc-pf-sandbox-usw2

# Then apply dependent project
atlantis apply -p eks-pf-sandbox-usw2
```

### Handling Plan Failures

If a plan fails:

1. **Review the error** in Atlantis comment
2. **Fix the issue** in your branch
3. **Push the fix**:
   ```bash
   git add .
   git commit -m "Fix terraform syntax error"
   git push
   ```
4. Atlantis automatically re-runs plan

### Manual Plan Trigger

If Atlantis doesn't auto-plan:

```bash
# Trigger plan manually
atlantis plan

# Or for specific project
atlantis plan -p vpc-pf-sandbox-usw2
```

### Unlocking Projects

If a project is locked (e.g., due to failed apply):

```bash
# Unlock all projects in PR
atlantis unlock

# Or unlock via Atlantis UI
# Visit: https://atlantis-pf-sandbox.infra-dev.arcteryx.io
```

### Policy Checks

If your organization uses policy checks:

1. Atlantis runs policies after plan
2. Review policy violations in PR comment
3. Fix violations or request approval from policy approvers
4. Policy approvers can approve with:
   ```bash
   atlantis approve_policies
   ```

## Troubleshooting

### Atlantis Not Responding

**Symptoms**: No comment from Atlantis after opening PR

**Solutions**:

1. Check webhook delivery in GitHub App settings
2. Verify Atlantis Gateway is running:
   ```bash
   kubectl get pods -n atlantis-gw
   ```
3. Check Atlantis pod logs:
   ```bash
   kubectl logs -n atlantis -l app.kubernetes.io/name=atlantis
   ```
4. Manually trigger plan:
   ```bash
   atlantis plan
   ```

### Plan Shows Unexpected Changes

**Symptoms**: Plan shows changes you didn't make

**Solutions**:

1. Check if someone else modified the infrastructure manually
2. Review Terraform state:
   ```bash
   # In your local environment
   cd component/terraform
   terraform workspace select pf-sandbox-usw2
   terraform state list
   ```
3. Consider importing existing resources:
   ```bash
   terraform import aws_vpc.main vpc-12345678
   ```

### Apply Fails

**Symptoms**: Apply command fails with error

**Solutions**:

1. Review error message in Atlantis comment
2. Common issues:
   - **Permissions**: Check IAM role has required permissions
   - **Dependencies**: Ensure dependent resources exist
   - **Conflicts**: Check for resource name conflicts
3. Fix issue and re-run:
   ```bash
   atlantis plan
   atlantis apply
   ```

### Project Locked

**Symptoms**: "This project is currently locked" error

**Solutions**:

1. Check who locked it in Atlantis UI
2. If it's your PR, unlock it:
   ```bash
   atlantis unlock
   ```
3. If locked by another PR, wait for that PR to complete or contact the owner

### State Lock Errors

**Symptoms**: "Error acquiring state lock"

**Solutions**:

1. Wait a few minutes (lock may be held by another operation)
2. Check DynamoDB for stale locks:
   ```bash
   aws dynamodb scan --table-name terraform-state-lock
   ```
3. Manually remove stale lock (use with caution):
   ```bash
   aws dynamodb delete-item \
     --table-name terraform-state-lock \
     --key '{"LockID": {"S": "arcteryx-pf-sandbox/vpc/terraform.tfstate-md5"}}'
   ```

### Configuration Not Loading

**Symptoms**: Atlantis doesn't detect your projects

**Solutions**:

1. Check `atlantis.yaml` is generated correctly:
   ```bash
   # View generated config in PR
   cat atlantis.yaml
   ```
2. Verify workspace is enabled:
   ```bash
   cat atlantis/conf/enabled_contexts.json
   ```
3. Check component isn't skipped:
   ```bash
   cat atlantis/conf/skip_components.json
   ```
4. Verify file structure matches expected pattern:
   ```
   component/terraform/workspaces/workspace.tfvars.json
   ```

### Private Module Access Fails

**Symptoms**: Terraform init fails with "could not download module" for private GitHub repos

**Solutions**:

1. Verify GitHub App credentials are configured in Atlantis:
   - `ATLANTIS_GH_APP_ID` - GitHub App ID
   - `ATLANTIS_GH_APP_KEY` - GitHub App private key
   - `ATLANTIS_GH_APP_INSTALLATION_ID` - Installation ID
2. Check the GitHub App has access to the private repository
3. Verify the pre-workflow hook is configured in `repos.yaml` (uses GitHub App token authentication)
4. Check Atlantis pod logs for git authentication errors:
   ```bash
   kubectl logs -n atlantis -l app.kubernetes.io/name=atlantis | grep -i "git\|auth\|token"
   ```
5. Verify the GitHub App has "Repository contents: Read" permission

### GitHub App Authentication Issues

**Symptoms**: "Authentication failed" errors

**Solutions**:

1. Verify GitHub App is installed on repository
2. Check GitHub App credentials in AWS Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id arcteryx/pf/atlantis/github-app-private-key
   ```
3. Verify installation ID matches in config:
   ```bash
   # Check Atlantis Gateway config
   kubectl get configmap -n atlantis-gw
   ```

## Best Practices

### 1. Small, Focused PRs

- Make one logical change per PR
- Easier to review and troubleshoot
- Faster plan/apply cycles

### 2. Review Plans Carefully

- Always review plan output before applying
- Check for unexpected changes
- Verify resource counts match expectations

### 3. Test in Sandbox First

- Test changes in `pf-sandbox` workspace first
- Verify everything works before promoting to production
- Use separate PRs for each environment

### 4. Use Descriptive Commit Messages

```bash
# Good
git commit -m "Add RDS instance for user database"

# Bad
git commit -m "Update main.tf"
```

### 5. Keep Workspaces Isolated

- Don't mix changes for different workspaces in one PR
- Use separate branches for different environments
- Easier to track and rollback changes

### 6. Document Complex Changes

Add comments in PR description:

```markdown
## Changes

- Add new VPC with 3 subnets
- Configure VPC peering to production

## Testing

- Verified connectivity from sandbox EKS cluster
- Tested DNS resolution

## Rollback Plan

- Delete VPC peering connection
- Remove VPC (no resources deployed yet)
```

## Quick Reference

### Common Workflows

```bash
# Standard workflow
1. Create branch
2. Make changes
3. Push and open PR
4. Review plan
5. Comment: atlantis apply
6. Merge PR

# Multi-project workflow
1. Open PR with changes
2. Comment: atlantis plan
3. Review all plans
4. Comment: atlantis apply -p project1
5. Comment: atlantis apply -p project2
6. Merge PR

# Fix and retry
1. Plan fails
2. Fix code
3. Push changes
4. Atlantis auto-plans
5. Comment: atlantis apply
```

### Useful Links

- Atlantis UI: https://atlantis-pf-sandbox.infra-dev.arcteryx.io
- Atlantis Docs: https://www.runatlantis.io/docs/
- GitHub App Settings: https://github.com/settings/apps/YOUR_APP

## Getting Help

1. **Check Atlantis logs**:

   ```bash
   kubectl logs -n atlantis -l app.kubernetes.io/name=atlantis --tail=100
   ```

2. **Check Gateway logs**:

   ```bash
   kubectl logs -n atlantis-gw -l app=atlantis-gw --tail=100
   ```

3. **Review webhook deliveries** in GitHub App settings

4. **Contact platform team** via Slack or create an issue
