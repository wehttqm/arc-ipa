# Dynamic Atlantis Configuration - Quick Summary

## What I've Set Up For You

✅ **Updated `gen-atlantis.py`** to use your custom `terraform-standard` workflow
✅ **Updated `repos.yaml`** with your comprehensive validation and security checks
✅ **Configured filtering** to only include `pf-sandbox-usw2` workspace
✅ **Added `atlantis.yaml` to `.gitignore`** (it will be auto-generated)
✅ **Created migration guide** with step-by-step instructions

## How It Works

```
PR Opened → Atlantis Webhook → gen-atlantis.py runs → atlantis.yaml generated → Plans execute
```

The script automatically:
1. Scans for all `*/terraform/workspaces/*.tfvars.json` files
2. Filters by workspace (only `pf-sandbox-usw2`)
3. Generates project definitions with your custom workflow
4. Creates `atlantis.yaml` at repository root

## What You Need To Do

### Step 1: Remove Static Config
```bash
rm atlantis.yaml
```

### Step 2: Test Locally (Optional)
```bash
export DIR=$(pwd)
python3 atlantis/terraform/files/gen-atlantis.py
cat atlantis.yaml  # View generated config
```

### Step 3: Commit Changes
```bash
git add .gitignore atlantis/terraform/files/ atlantis/conf/
git rm atlantis.yaml
git commit -m "Migrate to dynamic Atlantis configuration"
git push
```

### Step 4: Test with PR
Create a test PR and verify Atlantis detects all projects correctly.

## Generated Project Example

For each `.tfvars.json` file found, the script generates:

```yaml
- name: vpc-pf-sandbox-usw2
  dir: sandbox-local/vpc/terraform
  workspace: pf-sandbox-usw2
  terraform_version: v1.11.3
  workflow: terraform-standard
  autoplan:
    enabled: true
    when_modified:
      - '*.tf'
      - '*.tfvars'
      - '*.tfvars.json'
      - 'modules/**/*.tf'
      - 'workspaces/pf-sandbox-usw2.tfvars.json'
      - '*.yml'
      - '*.yaml'
```

## Your Custom Workflow Features

The `terraform-standard` workflow includes:

✅ **Pre-plan validation**
- Checks for unrestricted ingress rules (0.0.0.0/0)
- Detects hardcoded secrets
- Validates Terraform syntax

✅ **Plan execution**
- Workspace selection
- Format checking
- Terraform validation
- Plan with proper locking

✅ **Post-plan analysis**
- Warns about deletions
- Flags IAM changes
- Provides review checklist

✅ **Apply process**
- Pre-apply checks
- Safe apply execution
- Post-apply validation checklist

## Configuration Files

### `atlantis/conf/enabled_contexts.json`
```json
["pf-sandbox-usw2"]
```
Only processes workspaces containing "pf-sandbox-usw2"

### `atlantis/conf/skip_components.json`
```json
[]
```
No components are skipped (empty = include all)

## Adding New Projects

Just create the Terraform structure:

```bash
mkdir -p new-component/terraform/workspaces
vim new-component/terraform/main.tf
vim new-component/terraform/workspaces/pf-sandbox-usw2.tfvars.json
git add new-component/
git commit -m "Add new component"
```

Atlantis will automatically detect it on your next PR! 🎉

## File Structure Requirements

Projects MUST follow this pattern:
```
{component}/terraform/workspaces/{workspace}.tfvars.json
```

Examples that work:
- ✅ `vpc/terraform/workspaces/pf-sandbox-usw2.tfvars.json`
- ✅ `k8s/alloy/terraform/workspaces/pf-sandbox-usw2.tfvars.json`
- ✅ `deeply/nested/component/terraform/workspaces/pf-sandbox-usw2.tfvars.json`

Examples that DON'T work:
- ❌ `vpc/workspaces/pf-sandbox-usw2.tfvars.json` (missing /terraform/)
- ❌ `vpc/terraform/pf-sandbox-usw2.tfvars.json` (missing /workspaces/)

## Filtering Options

### Include Multiple Workspaces
```json
["pf-sandbox", "omni-prod", "ecomm-dev"]
```

### Include All Workspaces
```json
[]
```

### Skip Specific Components
```json
["test", "experimental", "deprecated"]
```

## Benefits

✅ **Zero Maintenance** - No manual atlantis.yaml updates
✅ **Auto-Discovery** - New projects detected automatically
✅ **Consistency** - All projects use same workflow
✅ **Scalability** - Handles unlimited projects
✅ **Flexibility** - Easy filtering via JSON configs

## Troubleshooting

### Project not detected?
```bash
# Check file structure
find . -name "*.tfvars.json" -path "*/terraform/workspaces/*"

# Test script locally
export DIR=$(pwd)
python3 atlantis/terraform/files/gen-atlantis.py
cat atlantis.yaml
```

### Wrong workspace included?
```bash
# Check filtering
cat atlantis/conf/enabled_contexts.json
```

### Script errors?
```bash
# Check Atlantis logs
kubectl logs -n atlantis -l app.kubernetes.io/name=atlantis --tail=100
```

## Documentation

- **[MIGRATION_TO_DYNAMIC.md](MIGRATION_TO_DYNAMIC.md)** - Detailed migration steps
- **[WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md)** - Daily usage guide
- **[README.md](README.md)** - Complete technical reference

## Ready to Go!

Your dynamic configuration is ready. Just:
1. Remove the static `atlantis.yaml`
2. Commit the changes
3. Test with a PR

That's it! 🚀
