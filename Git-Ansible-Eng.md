# CyberArk Ansible Deployment - Engineering & Testing Guide

## Overview

This project automates infrastructure deployment using Ansible orchestration, Git version control, and CyberArk Marketplace templates for secrets management. This guide will help you understand the architecture, make changes, and test deployments effectively.

## Architecture

### Components

**Ansible** - Infrastructure automation engine that executes playbooks to configure and deploy resources

**Git** - Version control system tracking all configuration changes and playbook versions

**CyberArk Templates** - Pre-built Marketplace templates for secure credential retrieval and secrets management

**Target Environments** - Infrastructure being deployed (servers, cloud resources, applications)

### Workflow

1. Engineers commit changes to Git repository
2. Ansible pulls latest playbooks and templates from Git
3. CyberArk integration retrieves credentials securely during runtime
4. Ansible executes playbooks against target infrastructure
5. Deployment results are logged and reported

## Repository Structure

```
project-root/
├── playbooks/              # Ansible playbooks for deployment
├── roles/                  # Reusable Ansible roles
├── inventory/              # Environment inventories (dev, staging, prod)
├── group_vars/             # Variables organized by groups
├── host_vars/              # Host-specific variables
├── templates/              # Jinja2 templates for configuration files
├── cyberark/               # CyberArk integration configs
│   └── queries/            # Credential query definitions
├── tests/                  # Test playbooks and scripts
└── README.md               # Project documentation
```

## Prerequisites

Before working with this project, ensure you have:

- Ansible installed (check version with `ansible --version`)
- Git configured with repository access
- SSH access to target environments
- CyberArk credentials for your account
- Python 3.x with required modules
- Access to the CyberArk Marketplace templates documentation

## Engineering the Deployment

### Making Changes

**Modify Existing Playbooks**

1. Check out the latest version: `git pull origin main`
2. Create a feature branch: `git checkout -b feature/your-change`
3. Edit the relevant playbook in the `playbooks/` directory
4. Update variable files if needed in `group_vars/` or `host_vars/`
5. Test locally (see Testing section)
6. Commit and push: `git add . && git commit -m "Description" && git push`

**Adding New Roles**

1. Create role structure: `ansible-galaxy init roles/new-role`
2. Implement tasks in `roles/new-role/tasks/main.yml`
3. Define defaults in `roles/new-role/defaults/main.yml`
4. Add role to playbook with appropriate variables
5. Document the role in `roles/new-role/README.md`

**CyberArk Integration**

CyberArk credentials are retrieved using the marketplace template lookup plugins. To add a new credential retrieval:

1. Define the query in `cyberark/queries/`
2. Reference in playbook using the lookup plugin:
   ```yaml
   - name: Retrieve credential
     set_fact:
       db_password: "{{ lookup('cyberark', 'query_name') }}"
   ```
3. Ensure the CyberArk safe and account exist
4. Test credential retrieval before full deployment

### Best Practices

- Always work in feature branches, never commit directly to main
- Use descriptive commit messages following conventional commits format
- Keep playbooks idempotent (running multiple times produces same result)
- Use variables for environment-specific values
- Tag tasks for selective execution: `tags: ['config', 'deploy']`
- Implement check mode compatibility: `check_mode: yes`
- Document all custom modules or complex logic

## Testing Strategy

### 1. Syntax Validation

Check playbook syntax before running:

```bash
ansible-playbook playbooks/deploy.yml --syntax-check
```

### 2. Dry Run (Check Mode)

Execute without making changes:

```bash
ansible-playbook playbooks/deploy.yml --check --diff
```

The `--diff` flag shows what would change.

### 3. Development Environment Testing

Always test in dev first:

```bash
ansible-playbook playbooks/deploy.yml -i inventory/dev --limit dev-servers
```

### 4. Targeted Testing

Test specific hosts or groups:

```bash
# Single host
ansible-playbook playbooks/deploy.yml --limit hostname.example.com

# Specific group
ansible-playbook playbooks/deploy.yml --limit webservers
```

### 5. Tag-Based Testing

Run specific sections:

```bash
ansible-playbook playbooks/deploy.yml --tags "config,validation"
```

Skip certain sections:

```bash
ansible-playbook playbooks/deploy.yml --skip-tags "restart"
```

### 6. Verbose Output

Debug issues with increased verbosity:

```bash
ansible-playbook playbooks/deploy.yml -vvv
```

### 7. CyberArk Credential Testing

Test credential retrieval independently:

```bash
ansible-playbook tests/test_cyberark_credentials.yml
```

Create a test playbook that only retrieves and validates credentials without making changes.

### 8. Integration Testing

After dev testing succeeds:

1. Deploy to staging environment
2. Run smoke tests to verify basic functionality
3. Execute full integration test suite
4. Validate CyberArk credential rotation works
5. Check logs for errors or warnings

## Common Commands

```bash
# List all hosts in inventory
ansible-inventory --list -i inventory/dev

# Test connectivity
ansible all -m ping -i inventory/dev

# Run ad-hoc command
ansible webservers -m shell -a "uptime" -i inventory/prod

# View available tags
ansible-playbook playbooks/deploy.yml --list-tags

# View tasks without executing
ansible-playbook playbooks/deploy.yml --list-tasks

# Start at specific task
ansible-playbook playbooks/deploy.yml --start-at-task="Configure database"
```

## Troubleshooting

**CyberArk Authentication Fails**

- Verify your CyberArk credentials are current
- Check network connectivity to CyberArk vault
- Validate query syntax in query definitions
- Ensure safe permissions are correctly configured

**Playbook Execution Hangs**

- Check SSH connectivity: `ansible target -m ping`
- Verify sudo/privilege escalation settings
- Review firewall rules between control node and targets
- Check for prompts that need `--extra-vars` input

**Variable Not Found Errors**

- Confirm variable is defined in appropriate scope
- Check precedence order: extra-vars > host_vars > group_vars > defaults
- Verify inventory group membership for group_vars

**Idempotency Issues**

- Review task logic for conditional statements
- Use appropriate modules (avoid shell/command where possible)
- Test with `--check` mode to identify non-idempotent tasks

## Deployment Workflow

### Standard Deployment Process

1. **Pre-Deployment**
   - Review changes in feature branch
   - Run syntax validation
   - Execute check mode against dev
   - Get peer review/approval

2. **Development Deployment**
   - Deploy to dev environment
   - Run validation tests
   - Verify CyberArk integration

3. **Staging Deployment**
   - Merge to staging branch
   - Deploy to staging environment
   - Execute full test suite
   - Conduct user acceptance testing if applicable

4. **Production Deployment**
   - Schedule maintenance window if needed
   - Create production release tag
   - Deploy to production with appropriate change control
   - Monitor logs and metrics
   - Validate all services operational

5. **Post-Deployment**
   - Document any issues encountered
   - Update runbooks if procedures changed
   - Archive logs for audit purposes

## Getting Help

- **Documentation**: Check the project README and role-specific docs
- **CyberArk Templates**: Refer to Marketplace documentation for template specifics
- **Ansible Docs**: https://docs.ansible.com for module references
- **Team Channel**: [Your team's communication channel]
- **Runbooks**: [Location of operational runbooks]

## Next Steps

1. Clone the repository and review the existing playbooks
2. Set up your development environment with required tools
3. Run a test deployment against the dev environment
4. Review recent commits to understand change patterns
5. Shadow an experienced team member through a deployment

---

*Document Version: 1.0*  
*Last Updated: [Current Date]*  
*Maintained by: [Team Name]*
