# CyberArk Ansible Deployment - Engineering & Testing Guide

## Overview

This project automates the deployment of CyberArk Privileged Access Security (PAS) components using Ansible orchestration, Git version control, and official CyberArk Marketplace templates. The deployment includes CPM (Central Policy Manager), PSM (Privileged Session Manager), and PVWA (Password Vault Web Access). This guide will help you understand the architecture, make changes, and test deployments effectively.

## Architecture

### Components

**Ansible** - Infrastructure automation engine that executes playbooks to configure and deploy CyberArk PAS components

**Git** - Version control system tracking all configuration changes and playbook versions

**CyberArk PAS Orchestrator** - Coordinates the deployment and configuration of CyberArk PAS components, managing dependencies and deployment sequencing

**CyberArk Marketplace Templates** - Official pre-built Ansible roles for CPM, PSM, and PVWA deployment and configuration

**PAS Components Being Deployed:**
- **CPM (Central Policy Manager)** - Automates password management and rotation for privileged accounts
- **PSM (Privileged Session Manager)** - Provides secure isolation and monitoring for privileged sessions
- **PVWA (Password Vault Web Access)** - Web-based interface for accessing the CyberArk Vault

**Target Environments** - Servers where PAS components will be installed (Windows/Linux hosts)

### Workflow

1. Engineers commit changes to Git repository (configuration updates, version changes)
2. Ansible pulls latest playbooks and CyberArk templates from Git
3. PAS Orchestrator coordinates the deployment sequence:
   - Validates prerequisites and connectivity
   - Determines component deployment order (typically PVWA → CPM → PSM)
   - Manages inter-component dependencies
4. Ansible executes tasks for each PAS component using marketplace templates
5. Components are configured and integrated with the CyberArk Vault
6. Deployment results are validated, logged, and reported

### PAS Orchestrator Role

The PAS Orchestrator is the coordination layer that ensures CyberArk components are deployed in the correct order with proper configuration. It handles:

**Deployment Sequencing** - Ensures PVWA is deployed before CPM and PSM, as they depend on PVWA for vault communication

**Dependency Management** - Validates that prerequisite components are healthy before proceeding with dependent components

**Configuration Consistency** - Ensures all components have compatible configurations and can communicate with each other and the Vault

**Health Checks** - Performs validation checks between component deployments to verify successful installation and connectivity

**Rollback Coordination** - Can orchestrate rollback procedures if a component deployment fails

**State Management** - Tracks deployment state across multiple components to support partial deployments and recovery

## Repository Structure

```
project-root/
├── defaults/               # Default variables (lowest precedence)
│   └── main.yml           # Default variable definitions for PAS components
├── files/                  # Static files to be copied to targets
│   ├── licenses/          # CyberArk license files
│   ├── certificates/      # SSL/TLS certificates
│   └── configs/           # Component-specific configuration files
├── handlers/               # Handler definitions for service restarts, etc.
│   └── main.yml           # Handlers for CPM, PSM, PVWA services
├── meta/                   # Role metadata and dependencies
│   └── main.yml           # PAS component dependencies and order
├── tasks/                  # Main task definitions
│   ├── main.yml           # Primary orchestration tasks
│   ├── pvwa.yml           # PVWA deployment tasks
│   ├── cpm.yml            # CPM deployment tasks
│   └── psm.yml            # PSM deployment tasks
├── vars/                   # Role variables (higher precedence than defaults)
│   ├── main.yml           # Common PAS variables
│   ├── vault_config.yml   # Vault connection settings
│   └── component_versions.yml  # Component version definitions
├── inventory/              # Environment inventories (dev, staging, prod)
│   ├── dev/
│   ├── staging/
│   └── prod/
├── playbooks/              # Main playbooks that call roles/tasks
│   ├── deploy_pas.yml     # Full PAS stack deployment
│   ├── deploy_pvwa.yml    # PVWA only
│   ├── deploy_cpm.yml     # CPM only
│   └── deploy_psm.yml     # PSM only
└── README.md               # Project documentation
```

## Prerequisites

Before working with this project, ensure you have:

- Ansible installed (check version with `ansible --version`) - version compatible with CyberArk templates
- Git configured with repository access
- SSH/WinRM access to target servers depending on OS
- Access to CyberArk Vault with appropriate permissions
- CyberArk PAS installation media and licenses
- SSL/TLS certificates for PVWA
- Network connectivity between components and the Vault
- Administrator credentials for target servers
- Understanding of CyberArk PAS architecture and component roles

## Engineering the Deployment

### Making Changes

**Modifying Tasks**

1. Check out the latest version: `git pull origin main`
2. Create a feature branch: `git checkout -b feature/your-change`
3. Edit tasks in `tasks/main.yml` or component-specific task files (`pvwa.yml`, `cpm.yml`, `psm.yml`)
4. Update variables in `vars/main.yml` (high precedence) or `defaults/main.yml` (low precedence)
5. If changing component versions, update `vars/component_versions.yml`
6. Test locally (see Testing section)
7. Commit and push: `git add . && git commit -m "Description" && git push`

**Understanding the Directory Structure**

**defaults/** - Place variables here that users should be able to override easily (server hostnames, ports, installation paths). These have the lowest precedence and are meant to be changed per environment.

**files/** - Store static files here:
- CyberArk license files for each component
- SSL/TLS certificates for PVWA
- Pre-configured XML or INI files for component configuration
- Installation media (if not using package managers)

**handlers/** - Define handlers for PAS services:
- Restarting CyberArk services (PVWA, CPM, PSM)
- Reloading configurations after changes
- Triggering health checks after service restarts

**meta/** - Contains role metadata including:
- Dependencies between PAS components (PVWA before CPM/PSM)
- Supported platforms (Windows Server versions, Linux distributions)
- Minimum Ansible version required

**tasks/** - The core automation logic:
- `main.yml` - Orchestration and component deployment sequence
- `pvwa.yml` - PVWA installation and configuration
- `cpm.yml` - CPM installation and configuration
- `psm.yml` - PSM installation and configuration
- Can include pre-checks, post-validation, and rollback tasks

**vars/** - Variables here have higher precedence:
- Vault connection details
- Component versions and build numbers
- Internal configuration that shouldn't be overridden
- Hardened security settings

**CyberArk PAS Component Configuration**

When modifying PAS component configurations:

1. **PVWA Changes** - Edit `tasks/pvwa.yml`:
   - Web server configuration (IIS/Apache)
   - SSL/TLS certificate deployment
   - Vault connection parameters
   - User authentication settings

2. **CPM Changes** - Edit `tasks/cpm.yml`:
   - Platform configurations for password management
   - Password change schedules and policies
   - Target system connections
   - Plugin installations

3. **PSM Changes** - Edit `tasks/psm.yml`:
   - Connection component configurations
   - Recording settings
   - Allowed target systems
   - Session isolation parameters

**Example: Updating PVWA Configuration**

In `tasks/pvwa.yml`:
```yaml
- name: Configure PVWA vault connection
  win_template:
    src: vault.ini.j2
    dest: 'C:\CyberArk\Password Vault Web Access\vault.ini'
  notify: restart pvwa service

- name: Deploy SSL certificate
  win_copy:
    src: "{{ pvwa_certificate }}"
    dest: 'C:\CyberArk\Certificates\'
  notify: configure iis ssl
```

Define handler in `handlers/main.yml`:
```yaml
- name: restart pvwa service
  win_service:
    name: CyberArk Password Vault Web Access
    state: restarted

- name: configure iis ssl
  win_iis_webbinding:
    name: PasswordVault
    protocol: https
    port: 443
    certificate_hash: "{{ cert_thumbprint }}"
```

### Best Practices

- Always work in feature branches, never commit directly to main
- Use descriptive commit messages following conventional commits format
- Keep tasks idempotent (running multiple times produces same result)
- Put environment-specific variables in `defaults/`, internal PAS configs in `vars/`
- Use handlers for CyberArk service restarts rather than direct restart tasks
- Store licenses and certificates in `files/`, never commit them to Git unencrypted
- Define component dependencies clearly in `meta/main.yml` for proper deployment order
- Tag tasks by component for selective execution: `tags: ['pvwa', 'cpm', 'psm']`
- Implement check mode compatibility where possible: `check_mode: yes`
- Document any CyberArk version-specific requirements or compatibility notes
- Use `include_tasks` or `import_tasks` to break up large component task files
- Always validate Vault connectivity before component deployment
- Test component health checks after each deployment phase
- Follow CyberArk's recommended deployment sequence: PVWA → CPM → PSM

## Testing Strategy

### 1. Syntax Validation

Check task syntax before running:

```bash
ansible-playbook playbooks/site.yml --syntax-check
```

Or validate individual task files:

```bash
ansible-playbook tasks/main.yml --syntax-check
```

### 2. Dry Run (Check Mode)

Execute without making changes:

```bash
ansible-playbook playbooks/deploy_pas.yml --check --diff
```

The `--diff` flag shows what would change. Note that some CyberArk installation tasks may not support check mode.

### 3. Development Environment Testing

Always test in dev first:

```bash
# Full PAS stack
ansible-playbook playbooks/deploy_pas.yml -i inventory/dev

# Individual components
ansible-playbook playbooks/deploy_pvwa.yml -i inventory/dev
ansible-playbook playbooks/deploy_cpm.yml -i inventory/dev
ansible-playbook playbooks/deploy_psm.yml -i inventory/dev
```

### 4. Component-Specific Testing

Test individual PAS components:

```bash
# Test only PVWA deployment
ansible-playbook playbooks/deploy_pas.yml --tags "pvwa"

# Test only CPM deployment
ansible-playbook playbooks/deploy_pas.yml --tags "cpm"

# Test only PSM deployment
ansible-playbook playbooks/deploy_pas.yml --tags "psm"
```

### 5. Tag-Based Testing

Run specific sections:

```bash
# Deploy and configure only
ansible-playbook playbooks/deploy_pas.yml --tags "deploy,configure"

# Run validation checks only
ansible-playbook playbooks/deploy_pas.yml --tags "validation"
```

Skip certain sections:

```bash
# Skip service restarts during testing
ansible-playbook playbooks/deploy_pas.yml --skip-tags "restart"
```

### 6. Verbose Output

Debug issues with increased verbosity:

```bash
ansible-playbook playbooks/deploy_pas.yml -vvv
```

### 7. PAS Component Health Validation

After deployment, validate each component:

```bash
# Run health check playbook
ansible-playbook playbooks/validate_pas.yml -i inventory/dev

# Check individual component status
ansible pvwa_servers -m win_service -a "name='CyberArk Password Vault Web Access'" -i inventory/dev
ansible cpm_servers -m win_service -a "name='CyberArk Central Policy Manager Scanner'" -i inventory/dev
ansible psm_servers -m win_service -a "name='Cyber-Ark Privileged Session Manager'" -i inventory/dev
```

**Key Health Checks:**
- PVWA web interface accessibility (https://pvwa-server/PasswordVault)
- CPM service status and vault connectivity
- PSM service status and connection component availability
- Component registration in the Vault
- Log files for errors (`C:\CyberArk\...\Logs\`)

### 8. Integration Testing

After dev testing succeeds:

1. Deploy to staging environment
2. Validate PVWA login and vault access
3. Test CPM password management on test accounts
4. Test PSM connections through connection components
5. Verify component-to-vault communication
6. Check integration between components (CPM/PSM accessing via PVWA)
7. Review all component logs for errors or warnings

## Common Commands

```bash
# List all hosts in inventory
ansible-inventory --list -i inventory/dev

# Test connectivity to Windows hosts
ansible all -m win_ping -i inventory/dev

# Test connectivity to Linux hosts (if PSM on Linux)
ansible psm_servers -m ping -i inventory/dev

# Check CyberArk service status
ansible pvwa_servers -m win_service -a "name='CyberArk Password Vault Web Access'" -i inventory/prod

# View available tags
ansible-playbook playbooks/deploy_pas.yml --list-tags

# View tasks without executing
ansible-playbook playbooks/deploy_pas.yml --list-tasks

# Start at specific task
ansible-playbook playbooks/deploy_pas.yml --start-at-task="Configure PVWA vault connection"

# Run only against specific component servers
ansible-playbook playbooks/deploy_pas.yml --limit pvwa_servers

# Gather facts about target servers
ansible all -m setup -i inventory/dev > server_facts.json
```

## Troubleshooting

**Vault Connectivity Issues**

- Verify network connectivity from component servers to Vault: `Test-NetConnection -ComputerName vault-server -Port 1858`
- Check vault.ini configuration on PVWA/CPM/PSM servers
- Validate Vault user credentials have appropriate permissions
- Review firewall rules between components and Vault
- Check CyberArk Vault service status

**Component Installation Failures**

- Verify installation media is accessible and correct version
- Check license file validity and path in `files/licenses/`
- Ensure target server meets minimum requirements (OS version, RAM, disk space)
- Review installation logs in `C:\CyberArk\[Component]\Logs\`
- Verify no conflicting CyberArk components already installed

**PVWA Issues**

- Check IIS application pool status and identity
- Verify SSL certificate is valid and trusted
- Test PVWA URL accessibility: `https://pvwa-server/PasswordVault`
- Review PVWA logs: `C:\CyberArk\Password Vault Web Access\Logs\`
- Confirm vault.ini points to correct Vault server

**CPM Issues**

- Verify CPM user exists in Vault and has proper permissions
- Check platform configurations are loaded in Vault
- Review CPM Scanner service logs
- Ensure target systems are reachable from CPM server
- Validate plugins are installed for target system types

**PSM Issues**

- Verify PSM user exists in Vault with proper permissions
- Check connection components are configured correctly
- Test RDP/SSH access from PSM to target systems
- Review PSM service logs and recording status
- Ensure session isolation is working (PVWA routing through PSM)

**Playbook Execution Hangs**

- Check WinRM connectivity for Windows: `ansible target -m win_ping`
- Check SSH connectivity for Linux: `ansible target -m ping`
- Verify credentials in inventory have proper privileges
- Review firewall rules between Ansible control node and targets
- Check for prompts that need `--extra-vars` input

**Variable Not Found Errors**

- Confirm variable is defined in appropriate scope (defaults vs vars)
- Check precedence order: extra-vars > vars > defaults
- Verify inventory group membership for group-specific variables
- Review `vars/component_versions.yml` for version-specific variables

**Idempotency Issues**

- Review task logic for conditional statements
- Some CyberArk installation tasks may not be fully idempotent
- Use appropriate modules (avoid shell/command where possible)
- Test with `--check` mode to identify non-idempotent tasks

**Deployment Order Problems**

- Ensure PVWA is deployed before CPM and PSM
- Check `meta/main.yml` for correct dependency definitions
- Verify the orchestrator is respecting component dependencies
- Review task tags to ensure components deploy in sequence

## Deployment Workflow

### Standard Deployment Process

1. **Pre-Deployment**
   - Review changes in feature branch
   - Run syntax validation
   - Execute check mode against dev
   - Verify CyberArk installation media and licenses are available
   - Confirm SSL certificates are valid for PVWA
   - Get peer review/approval

2. **Development Deployment**
   - Deploy PVWA first: `ansible-playbook playbooks/deploy_pvwa.yml -i inventory/dev`
   - Validate PVWA is accessible and connected to Vault
   - Deploy CPM: `ansible-playbook playbooks/deploy_cpm.yml -i inventory/dev`
   - Validate CPM service and vault connectivity
   - Deploy PSM: `ansible-playbook playbooks/deploy_psm.yml -i inventory/dev`
   - Validate PSM service and connection components
   - Run comprehensive validation tests
   - Test end-to-end flows (password retrieval via PVWA, session through PSM)

3. **Staging Deployment**
   - Merge to staging branch
   - Follow same component deployment order (PVWA → CPM → PSM)
   - Execute full integration test suite
   - Test password management workflows through CPM
   - Test privileged session recording through PSM
   - Conduct user acceptance testing if applicable
   - Verify all components are logging correctly

4. **Production Deployment**
   - Schedule maintenance window
   - Create production release tag
   - Notify stakeholders of deployment window
   - Deploy components in order with proper change control
   - PVWA first, validate before proceeding
   - CPM second, validate before proceeding
   - PSM last, full validation
   - Monitor component logs and services
   - Validate all PAS functionality operational
   - Test critical password management and session workflows

5. **Post-Deployment**
   - Document any issues encountered
   - Verify all components registered properly in Vault
   - Update runbooks if procedures changed
   - Archive deployment logs for audit purposes
   - Schedule post-deployment review
   - Monitor component health for 24-48 hours

## Getting Help

- **Documentation**: Check the project README and CyberArk Marketplace template documentation
- **CyberArk Templates**: Refer to official CyberArk Ansible documentation at https://cyberark.github.io/
- **Ansible Docs**: https://docs.ansible.com for module references
- **CyberArk Support**: Access CyberArk support portal for PAS component issues
- **Team Channel**: [Your team's communication channel]
- **Runbooks**: [Location of operational runbooks]
- **CyberArk Logs**: Always check component logs in `C:\CyberArk\[Component]\Logs\` for detailed error information

## Next Steps

1. Clone the repository and review the existing playbooks and task files
2. Set up your development environment with Ansible and required access
3. Review CyberArk PAS architecture documentation
4. Familiarize yourself with PVWA, CPM, and PSM component roles
5. Run a test deployment against the dev environment (PVWA → CPM → PSM)
6. Shadow an experienced team member through a production deployment
7. Review component logs to understand normal vs error states

## Additional Resources

- **CyberArk PAS Documentation**: Official product documentation for each component
- **CyberArk Ansible Collection**: https://galaxy.ansible.com/cyberark - Official Ansible modules
- **Installation Guides**: Component-specific installation and configuration guides
- **Hardening Guides**: CyberArk security hardening best practices
- **Architecture Diagrams**: Review PAS reference architecture for your environment

---

*Document Version: 1.0*  
*Last Updated: [Current Date]*  
*Maintained by: [Team Name]*
