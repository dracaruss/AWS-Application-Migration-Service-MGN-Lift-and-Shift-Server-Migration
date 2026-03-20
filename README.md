# AWS Application Migration Service (MGN) — Full Migration Walkthrough

## Migrating an osTicket Web Application to AWS Using Lift-and-Shift

This project documents a complete server migration using **AWS Application Migration Service (MGN)**, including real troubleshooting of authentication failures, networking misconfigurations, and launch template issues encountered during the process.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1: Setting Up the Target AWS Environment](#step-1-setting-up-the-target-aws-environment)
- [Step 2: Configuring AWS MGN](#step-2-configuring-aws-mgn)
- [Step 3: Installing the Replication Agent](#step-3-installing-the-replication-agent)
- [Step 4: Troubleshooting — Data Replication Stalled](#step-4-troubleshooting--data-replication-stalled)
- [Step 5: Fixing the Replication Settings](#step-5-fixing-the-replication-settings)
- [Step 6: Successful Replication](#step-6-successful-replication)
- [Step 7: Configuring the EC2 Launch Template](#step-7-configuring-the-ec2-launch-template)
- [Step 8: Test Launch](#step-8-test-launch)
- [Step 9: Validating the Migrated Application](#step-9-validating-the-migrated-application)
- [Step 10: Cutover and Teardown](#step-10-cutover-and-teardown)
- [Key Lessons Learned](#key-lessons-learned)
- [Technologies Used](#technologies-used)

---

## Project Overview

**Objective:** Migrate a live Ubuntu server running osTicket (a web-based support ticket system) from its original environment to AWS using a block-level lift-and-shift approach with AWS Application Migration Service (MGN).

**What is AWS MGN?**
AWS Application Migration Service (abbreviated MGN — inherited from its predecessor, CloudEndure Migration) automates lift-and-shift migrations to AWS. It performs continuous block-level replication of source servers, then orchestrates the launch of fully migrated EC2 instances in your target AWS environment.

**Why Lift-and-Shift?**
Lift-and-shift preserves the entire source environment — OS configuration, installed packages, user accounts, application files, databases — without requiring re-architecture. The replication is block-level, meaning every bit on the source disk is copied to the target, resulting in an exact clone.

---

## Architecture

```
┌──────────────────┐         ┌─────────────────────────────────────────────┐
│   Source Server   │         │              AWS (us-east-1)                │
│                   │         │                                             │
│  ubuntu-webapp-poc│  TCP    │  ┌─────────────────┐   ┌────────────────┐  │
│  (osTicket)       │ ──443──►│  │ Replication Srv  │   │ Target Instance│  │
│                   │  1500   │  │ (t3.small)       │──►│ (c5.large)     │  │
│  Replication      │         │  │ Public Subnet    │   │ Public Subnet  │  │
│  Agent Installed  │         │  └─────────────────┘   └────────────────┘  │
│                   │         │                                             │
│                   │         │  VPC: migration-poc-vpc (10.20.0.0/16)     │
└──────────────────┘         └─────────────────────────────────────────────┘
```

### Three Servers Involved in MGN Migration

| Server | Purpose | Lifecycle |
|--------|---------|-----------|
| **Source Server** | The original server being migrated. Runs the replication agent that sends data to AWS. | Decommissioned after cutover. |
| **Replication Server** | A temporary instance MGN creates in your AWS account. Receives replicated data and writes it to staging EBS volumes. | Automatically terminated after migration. |
| **Target Server** | The final migrated EC2 instance launched from the replicated data using your EC2 Launch Template. | Your new production server. |

---

## Prerequisites

- AWS account with MGN initialized in the target region
- Source server accessible via SSH
- IAM credentials with MGN permissions for the replication agent
- A VPC with **public and private subnets** configured
- Terraform (optional, for infrastructure provisioning)

---

## Step 1: Setting Up the Target AWS Environment

The target environment was provisioned using Terraform within a VPC named `migration-poc-vpc` in `us-east-1`:

- **VPC CIDR:** `10.20.0.0/16`
- **Public Subnets:** Configured with route tables pointing `0.0.0.0/0` to an Internet Gateway (IGW)
- **Private Subnets:** Configured with route tables pointing to a NAT Gateway (or no internet route)

> **Critical:** Understanding the difference between public and private subnets is essential for this migration. A **public subnet** has a route to an Internet Gateway, allowing instances with public IPs to communicate with the internet. A **private subnet** lacks this route — even if an instance has a public IP assigned, traffic has nowhere to go.

---

## Step 2: Configuring AWS MGN

### Replication Template

In the MGN console under **Settings → Replication template**, the default replication settings were configured:

- **Staging area subnet:** Public subnet (`subnet-0cbf0a339d7547bd2`)
- **Replication server instance type:** `t3.small`
- **EBS encryption:** Default
- **Create public IPv4 address:** Yes

> **Important:** The replication template only applies to **newly added source servers**. Changing the template does not retroactively update servers that are already registered with MGN. Each source server has its own independent copy of replication settings that must be edited individually.

### EC2 Launch Template

The launch template defines the configuration for the final target instance:

- **Instance type:** `c5.large`
- **Subnet:** Public subnet
- **Security groups:** Custom SG with SSH (22), HTTP (80), HTTPS (443)
- **Public IP:** Yes

---

## Step 3: Installing the Replication Agent

The AWS Replication Agent was downloaded and installed on the source server (`ubuntu-webapp-poc`). The agent:

1. Registers the source server with MGN
2. Begins continuous block-level replication of all attached disks
3. Sends data to the replication server over TCP port 1500
4. Communicates with the MGN service over HTTPS (port 443)

---

## Step 4: Troubleshooting — Data Replication Stalled

### The Error

After installing the agent, the MGN console showed:

```
Data replication stalled
Failed to authenticate with service.
```

The replication initiation steps showed:
- ✅ Create security groups
- ✅ Launch Replication Server
- ✅ Boot Replication Server
- ❌ Authenticate with service

### CloudTrail Investigation

#### Initial Analysis

CloudTrail events around the failure timestamp (02:14 UTC-5 / 07:14 UTC) showed the MGN service successfully:

1. Created a security group (`sg-00baadea8727a62c0`)
2. Added ingress and egress rules (SSH, DNS, HTTPS, TCP 1500)
3. Launched the replication server (`RunInstances`)
4. Created KMS grants for EBS encryption
5. Shared snapshot volumes

A `Client.InvalidPermission.Duplicate` error appeared for an `AuthorizeSecurityGroupEgress` call, but this was **benign** — MGN idempotently ensures rules exist and throws this harmless error when they're already present.

#### Finding the Root Cause

Scrolling forward in CloudTrail revealed the critical sequence:

| Time (UTC-5) | Event | Significance |
|------|-------|-------------|
| 02:19:59 | `SendAgentLogsForMgn` | Replication server is alive and communicating |
| 02:20:52 | `SendAgentLogsForMgn` | Still sending logs |
| 02:23:51 | `SendAgentMetricsForMgn` | Still sending metrics |
| 02:25:17 | **`TerminateInstances`** | **MGN kills the replication server** |
| 02:25:48 | `RetireGrant` | KMS cleanup |

The `TerminateInstances` event was invoked by `mgn.amazonaws.com` using the `AWSServiceRoleForApplicationMigrationService`. **MGN itself was terminating the replication server** after it failed internal health checks.

### Root Cause: Private Subnet Misconfiguration

The source server's replication settings pointed to subnet `subnet-0d90c01c600aa1c1a`, named **`migration-poc-private-b`**:

- **Auto-assign public IPv4:** No
- **Route table:** `migration-poc-private-rt` (no Internet Gateway route)

Meanwhile, the replication data routing was configured as:
- **Create public IPv4 address:** Yes
- **Use private IPv4 for data replication:** No

**The problem:** MGN assigned a public IP to the replication server, but the server sat in a private subnet with no route to an Internet Gateway. The public IP was useless — like having a mailbox with no road connecting it to the postal system. The replication server could not reach `mgn.us-east-1.amazonaws.com` to authenticate, so MGN terminated it and retried in a loop.

### Why the Template Didn't Help

The replication template had already been updated with the correct public subnet. However, because `ubuntu-webapp-poc` was already registered in MGN, it retained its original (incorrect) replication settings. Even reinstalling the agent didn't help — MGN recognized the server by its fingerprint and kept the existing configuration.

To apply template settings to an existing server, you must either:
- Edit the source server's individual replication settings, OR
- Delete the source server from MGN entirely, then reinstall the agent so it registers as new

---

## Step 5: Fixing the Replication Settings

### The Fix

1. Navigated to the source server in MGN → **Edit Replication Settings**
2. Changed **Staging area subnet** from `migration-poc-private-b` to the public subnet
3. Kept **Create public IPv4 address** selected (appropriate for a public subnet)
4. Saved the changes

MGN automatically retried replication with the corrected settings.

---

## Step 6: Successful Replication

After fixing the subnet, MGN dashboard showed:

| Metric | Status |
|--------|--------|
| Alerts | Healthy (1 server, 100%) |
| Data Replication Status | Healthy (1 server, 100%) |
| Migration Lifecycle | Ready for testing (1 server, 100%) |

---

## Step 7: Configuring the EC2 Launch Template

### Initial Problem

The EC2 Launch Template had blank values for critical fields:

- **Subnet:** - (empty)
- **Security groups:** - (empty)
- **Public IP:** No

Without a subnet, AWS had no target location for the instance. The conversion server (`m5.large`) would spin up, convert the replicated disks, attempt to launch the target instance, fail silently, and terminate — leaving no test instance.

### The Fix

1. In MGN, clicked **Modify** on the EC2 Launch Template
2. Set **Subnet** to the public subnet (`subnet-0cbf0a339d7547bd2`)
3. Set **Security groups** to a custom SG with SSH (22), HTTP (80), and HTTPS (443) inbound rules
4. Set **Public IP** to Yes
5. Saved — this created a **new template version**

### Setting the Default Template Version

MGN only uses the **default version** of a launch template. After modifying:

1. Navigated to **EC2 → Launch Templates**
2. Selected the template → **Actions → Set default version**
3. Set the latest version as default

---

## Step 8: Test Launch

1. In MGN: **Test and Cutover → Launch test instances**
2. MGN launched a **Conversion Server** (`m5.large`) to convert replicated disks into a bootable format
3. The conversion server launched the **target test instance** (`c5.large`) and self-terminated
4. Verified the test instance was running in EC2 with a public IP

### SSH Validation

```bash
ssh superuss@<public-ip>
```

Password-based SSH worked immediately — the source server's `/etc/ssh/sshd_config` (with `PasswordAuthentication yes`) and user accounts were replicated bit-for-bit. No key pair or reconfiguration was needed.

---

## Step 9: Validating the Migrated Application

### osTicket Verification

After ensuring the security group had HTTP (port 80) open inbound:

```
http://<public-ip>/
```

The osTicket application loaded successfully, confirming:
- Apache/Nginx web server was running
- PHP application layer was intact
- Database (MySQL/MariaDB) was functional
- All configuration files were preserved from the source

---

## Step 10: Cutover and Teardown

### Cutover

1. **Test and Cutover → Mark as "ready for cutover"** — terminated the test instance
2. **Test and Cutover → Launch cutover instances** — launched the final production instance
3. **Finalize cutover** — marked the migration as complete

### Teardown

After finalizing cutover, the following resources were cleaned up:

- **Replication server** (t3.small) — should auto-terminate; verify in EC2
- **Staging EBS volumes** — check for orphaned volumes in EC2
- **MGN-created security groups** — delete if no longer needed
- **KMS grants** — retired automatically
- **Snapshots** — check and delete MGN-created snapshots
- **Source server** — decommission when ready

> **Note:** If infrastructure was provisioned with Terraform, ensure the migrated production instance is **not** managed by Terraform state before running `terraform destroy`. Use `terraform state rm` to remove it from state if needed, or the destroy will delete your newly migrated app.

---

## Key Lessons Learned

### 1. Public IP ≠ Public Subnet
Assigning a public IP to an instance doesn't give it internet access. The subnet's route table must have a route to an Internet Gateway (`0.0.0.0/0 → igw-xxxxx`). Without this route, the public IP is unreachable.

### 2. MGN Replication Templates Don't Update Existing Servers
The replication template is a blueprint for new servers only. Once a source server is registered, it has its own independent settings. Always verify per-server replication settings, not just the template.

### 3. MGN Recognizes Servers by Fingerprint
Reinstalling the replication agent doesn't create a "new" server in MGN. The service recognizes the same source server and retains its existing configuration. To truly start fresh, delete the server from MGN first.

### 4. Launch Template Versioning Matters
MGN uses the **default version** of the EC2 Launch Template. Modifying a template creates a new version, but you must explicitly set it as the default or MGN will continue using the old one.

### 5. CloudTrail is Essential for Debugging MGN
The MGN console error ("Failed to authenticate with service") was misleading. CloudTrail revealed the actual sequence: the replication server launched, communicated briefly, then was terminated by MGN itself due to failed health checks caused by the networking issue.

### 6. Security Groups Don't Need a Relaunch
AWS security group changes take effect immediately. No instance restart or relaunch is required.

### 7. Block-Level Replication Preserves Everything
Users, passwords, SSH configuration, web server settings, application files, and databases are all replicated exactly. A successful lift-and-shift should require zero reconfiguration on the target.

---

## Technologies Used

- **AWS Application Migration Service (MGN)**
- **AWS EC2** (Launch Templates, Security Groups, Instances)
- **AWS VPC** (Subnets, Route Tables, Internet Gateway)
- **AWS CloudTrail** (Event investigation and debugging)
- **AWS KMS** (EBS encryption)
- **Terraform** (Infrastructure provisioning)
- **osTicket** (Migrated web application)
- **Ubuntu Linux** (Source and target OS)
