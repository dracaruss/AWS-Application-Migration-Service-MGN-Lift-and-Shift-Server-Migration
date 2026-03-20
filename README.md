# AWS Application Migration Service (MGN) Lift and Shift Full Migration Walkthrough

## Migrating an osTicket Web Application to AWS Using Lift-and-Shift
> [!IMPORTANT]
>This project documents a complete server migration using **AWS Application Migration Service (MGN)**, including real troubleshooting of authentication failures, networking misconfigurations, and launch template issues encountered during the process.

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
┌───────────────────┐         ┌─────────────────────────────────────────────┐
│   Source Server   │         │              AWS (us-east-1)                │
│                   │         │                                             │
│  ubuntu-webapp-poc│   TCP   │  ┌─────────────────┐   ┌────────────────┐   │
│  (osTicket)       │ ──443──►│  │ Replication Srv │   │ Target Instance│   │
│                   │  1500   │  │ (t3.small)      │──►│ (c5.large)     │   │
│  Replication      │         │  │ Public Subnet   │   │ Public Subnet  │   │
│  Agent Installed  │         │  └─────────────────┘   └────────────────┘   │
│                   │         │                                             │
│                   │         │  VPC: migration-poc-vpc (10.20.0.0/16)      │
└───────────────────┘         └─────────────────────────────────────────────┘
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
- Source server pre configured, and accessible via SSH
- IAM credentials with MGN permissions for the replication agent
- A VPC with **public and private subnets** configured
- Terraform

### Setup the osTicket server
This will act as the server to migrate to AWS. I set it up as a conventional LAMP setup: ```Linux Apache MySQL PHP```  
I used the newest Ubuntu VM image (which would become a future issue), and installed MySQL and PHP via apt.
<img width="1150" height="650" alt="i setup a osTIcket" src="https://github.com/user-attachments/assets/58225f35-7b3e-4fa6-bc44-c2b07fb9ef5c" />

##

Next I populated the osTicket with a bunch of tickets, and assigned some to different agents, and just overall made a bunch of info to populate the SQL database:
<img width="1140" height="717" alt="Created a bunch of tickets" src="https://github.com/user-attachments/assets/b37e4954-5cb2-4cd6-aaa1-bf076212e8b6" />

##

### Documenting the server config  
In a real enterprise migration, many times you really don't know what you have. Often companies with 200 servers often can't tell you which ones are actually in use, what talks to what, or what ports things run on. So the first step is discovery, aka figuring out what exists and documenting it.

*AWS Application Discovery Service is the tool that does this at scale. You have to install agents on all your servers and it watches for 2–4 weeks, recording CPU usage, memory, disk, and most importantly which servers are making network connections to which other servers on which ports. It builds a dependency map automatically.*

For my setup I manually checked and recorded the setup:  
<br>

***osTicket URL path - admin***  
> /osticket/upload/scp/

***Apache version (apache2 -v)***  
> Server version: Apache/2.4.58 (Ubuntu)
   
***PHP version (php -v)***  
> PHP 8.3.6 (cli) (built: Jan 27 2026 03:09:47) (NTS)
   
***MySQL version (mysql --version)***  
> mysql  Ver 8.0.45-0ubuntu0.24.04.1 for Linux on x86_64 ((Ubuntu))  

And after migration, when I'm ready for verifying the app works on AWS, I'll compare against this baseline - same PHP version? Same extensions? Same number of tickets in the database? Same behavior? The discovery doc is my "before" photo.

##

## Step 1: Setting Up the Target AWS Environment

The target environment was provisioned using Terraform within a VPC named `migration-poc-vpc` in `us-east-1`:

- **VPC CIDR:** `10.20.0.0/16`
- **Public Subnets:** Configured with route tables pointing `0.0.0.0/0` to an Internet Gateway (IGW)
- **Private Subnets:** Configured with route tables pointing to a NAT Gateway (or no internet route)

---

## Step 2: Configuring AWS MGN

### Replication Template

In the MGN console under **Settings → Replication template**, the default replication settings were configured:

- **Staging area subnet:** Public subnet (`subnet-0cbf0a339d7547bd2`)
- **Replication server instance type:** `t3.small`
- **EBS encryption:** Default
- **Create public IPv4 address:** Yes

### EC2 Launch Template

The launch template defines the configuration for the final target instance:

- **Instance type:** `c5.large`
- **Subnet:** Public subnet
- **Security groups:** Custom SG with SSH (22), HTTP (80), HTTPS (443)
- **Public IP:** Yes

---

## Step 3: Installing the Replication Agent

Create a role with access keys for the Ubuntu server to use on AWS:
<img width="1338" height="149" alt="create a role" src="https://github.com/user-attachments/assets/968736bd-0840-48d5-aa73-3dab16c0233b" />

##

The AWS Replication Agent was downloaded and installed on the source server (`ubuntu-webapp-poc`).  
The agent:
1. Registers the source server with MGN
2. Begins continuous block-level replication of all attached disks
3. Sends data to the replication server over TCP port 1500
4. Communicates with the MGN service over HTTPS (port 443)
<img width="1436" height="310" alt="I SSH into" src="https://github.com/user-attachments/assets/f8375d51-707a-4912-8766-a4ff53af5573" />

Next I started the replication agent on the Ubuntu osTicket local server:
```
$ ./aws-replication-installer-init --region us-east-1 --aws-access-key-id KEY --aws-secret-access-key SECRET
```

##

## Step 4: Troubleshooting — Data Replication Stalled

### The 1st Error
The agent installation failed at this stage:
<img width="1664" height="428" alt="ok time to install" src="https://github.com/user-attachments/assets/d9503ad3-4072-4c93-837d-e82baa6c3c80" />

Apparently the Ubuntu image ran a kernel that was too new. So I had to downgrade the Linux kernel to one compatible with the MGN agent:
<img width="1152" height="170" alt="root ubuntu" src="https://github.com/user-attachments/assets/223b06ef-e95e-46e8-a577-de222078f950" />
This caused the agent install to go further and then break again :(

##

### The Next Error
<img width="1652" height="249" alt="ok next issue ugh" src="https://github.com/user-attachments/assets/31bfcd4b-f81d-49ff-b578-fc31b5ca2d66" />
When the MGN agent installs, it tries to call 169.254.169.254. This is the instance metadata service that exists on real cloud VMs (EC2, GCP, Azure). It's how a cloud instance finds out "what am I?". On an actual EC2 instance, this returns useful data. On a non-cloud VM like this Ubuntu server, it should return nothing or timeout.  

### Local Ubuntu logs
When I consulted the logs in the same folder as the installation agent, it showed that my network (likely VMware's NAT or my router??) intercepted that metadata request and returned an HTML captive portal page instead of a clean failure. This made the agent expect a cloud setup not a local on-prem server, which caused the error.  

I blocked the metadata service IP locally: 
```
$ iptables -A OUTPUT -d 169.254.169.254 -j REJECT
```
This forced the request to fail cleanly. The agent then skipped the metadata check, generated its own ID, and registered successfully.
<img width="1328" height="298" alt="ok good to go" src="https://github.com/user-attachments/assets/6f771c9d-6033-4d97-b6a4-ee93a71fae42" />

##

### The Nextest Error
After installing the agent and getting it working, the MGN console showed:

```
Data replication stalled
Failed to authenticate with service.
```

The replication initiation steps showed:
- ✅ Create security groups
- ✅ Launch Replication Server
- ✅ Boot Replication Server
- ❌ Authenticate with service
<img width="820" height="532" alt="a new error popped up" src="https://github.com/user-attachments/assets/1e47982d-8173-4df9-a2e7-a7630a632083" />

### CloudTrail Investigation

***Initial Analysis***

CloudTrail events around the failure timestamp (02:14 UTC-5 / 07:14 UTC) showed the MGN service successfully:

1. Created a security group (`sg-00baadea8727a62c0`)
2. Added ingress and egress rules (SSH, DNS, HTTPS, TCP 1500)
3. Launched the replication server (`RunInstances`)
4. Created KMS grants for EBS encryption
5. Shared snapshot volumes

<img width="1410" height="442" alt="I wasnt sure what caused" src="https://github.com/user-attachments/assets/f2ae6284-ac58-4958-aba6-241506b11ea7" />

A `Client.InvalidPermission.Duplicate` error appeared for an `AuthorizeSecurityGroupEgress` call, but this was **benign** — MGN idempotently ensures rules exist and throws this harmless error when they're already present.  

<br>

***Finding the Root Cause***

Scrolling forward in CloudTrail revealed the critical sequence:

| Time (UTC-5) | Event | Significance |
|------|-------|-------------|
| 02:19:59 | `SendAgentLogsForMgn` | Replication server is alive and communicating |
| 02:20:52 | `SendAgentLogsForMgn` | Still sending logs |
| 02:23:51 | `SendAgentMetricsForMgn` | Still sending metrics |
| 02:25:17 | **`TerminateInstances`** | **MGN kills the replication server** |
| 02:25:48 | `RetireGrant` | KMS cleanup |

The `TerminateInstances` event was invoked by `mgn.amazonaws.com` using the `AWSServiceRoleForApplicationMigrationService`. **MGN itself was terminating the replication server** after it failed internal health checks.  

<br>

***Root Cause: Private Subnet Misconfiguration***

The source server's replication settings pointed to subnet `subnet-0d90c01c600aa1c1a`, named **`migration-poc-private-b`**:  

- **Auto-assign public IPv4:** No
- **Route table:** `migration-poc-private-rt` (no Internet Gateway route)

Meanwhile, the replication data routing was configured as:
- **Create public IPv4 address:** Yes
- **Use private IPv4 for data replication:** No

**The problem:** MGN assigned a public IP to the replication server, but the server sat in a private subnet with no route to an Internet Gateway. The replication server could not reach `mgn.us-east-1.amazonaws.com` to authenticate, so MGN terminated it and retried in a loop.  

<br>

***Why the Template Didn't Help***

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
<img width="752" height="333" alt="i had to edit the" src="https://github.com/user-attachments/assets/6821889d-d655-4491-a784-c51f37a28014" />

MGN automatically retried replication with the corrected settings.

---

## Step 6: Successful Replication

After fixing the subnet, MGN dashboard showed:

| Metric | Status |
|--------|--------|
| Alerts | Healthy (1 server, 100%) |
| Data Replication Status | Healthy (1 server, 100%) |
| Migration Lifecycle | Ready for testing (1 server, 100%) |

<img width="1427" height="602" alt="ok finally it uploaded" src="https://github.com/user-attachments/assets/617a1664-8ed8-40ed-9660-efc92b39e7cc" />

## Step 7: Configuring the EC2 Launch Template

1. In MGN, I clicked **Modify** on the EC2 Launch Template
2. Set **Subnet** to the public subnet (`subnet-0cbf0a339d7547bd2`)
3. Set **Security groups** to a custom SG with SSH (22), HTTP (80), and HTTPS (443) inbound rules
4. Set **Public IP** to Yes
5. Saved - this created a **new template version**

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
<img width="1261" height="290" alt="after setting up the launch" src="https://github.com/user-attachments/assets/a4c71f73-fc46-4902-ba1d-afd93da64806" />

### SSH Validation

```bash
ssh superuss@<public-ip>
```

Password-based SSH worked immediately. This is because the source server's `/etc/ssh/sshd_config` (with `PasswordAuthentication yes`) and user accounts were replicated bit-for-bit. No key pair or reconfiguration was needed.
<img width="796" height="317" alt="i could ssh in and" src="https://github.com/user-attachments/assets/a2191f57-913a-4995-b714-6e871a05fa68" />

##

I also checked that apache2 and MySQL were also running:
<img width="947" height="108" alt="apache is running" src="https://github.com/user-attachments/assets/28916bbe-23b8-432b-89ec-56f7ddab3f42" />


## Step 9: Validating the Migrated Application

### osTicket Verification

After ensuring the security group had HTTP (port 80) open inbound, the osTicket application loaded successfully, confirming:
- Apache/Nginx web server was running
- PHP application layer was intact
- Database (MySQL/MariaDB) was functional
- All configuration files were preserved from the source

<img width="1026" height="606" alt="i was able to login and test" src="https://github.com/user-attachments/assets/4b1fe8f6-dd33-45f8-8d88-80f6eb28b6a7" />


## Step 10: Cutover and Teardown

### Cutover

1. **Test and Cutover → Mark as "ready for cutover"** — terminated the test instance
2. **Test and Cutover → Launch cutover instances** — launched the final production instance
<img width="1541" height="402" alt="ok everything is working" src="https://github.com/user-attachments/assets/433132f0-c048-4ceb-9734-bd09a6967433" />

3. **Finalize cutover** — marked the migration as complete
<img width="963" height="358" alt="once that was working i did the final cut over" src="https://github.com/user-attachments/assets/09eb7fb3-0649-4ac9-aeca-d9a34f66f869" />

##

I retrieved the public IP of the EC2 running the migrated server:
<img width="876" height="396" alt="and everything was up and running" src="https://github.com/user-attachments/assets/3c4c4d11-6cc4-470c-980a-ba26790c85b4" />

I could access the osTicket app from the new public AWS IP of the EC2:  
<img width="934" height="511" alt="and the website is up and running" src="https://github.com/user-attachments/assets/43c1c4b8-66c2-4af9-b2f6-f98088f57ec6" />


### Teardown

After finalizing cutover, the following resources were cleaned up:

- **Replication server** (t3.small) — should auto-terminate; verify in EC2
- **Staging EBS volumes** — check for orphaned volumes in EC2
- **MGN-created security groups** — delete if no longer needed
- **KMS grants** — retired automatically
- **Snapshots** — check and delete MGN-created snapshots
- **Source server** — decommission when ready

> [!NOTE]
> If infrastructure was provisioned with Terraform, ensure the migrated production instance is **not** managed by Terraform state before running `terraform destroy`. Use `terraform state rm` to remove it from state if needed, or the destroy will delete your newly migrated app.

---

## Block-Level Replication Preserves Everything
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

##

> [!CAUTION]
> ***Mission Accomplished.***
