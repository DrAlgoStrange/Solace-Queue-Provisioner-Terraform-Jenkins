# Solace Queue Provisioner — Terraform + Jenkins

Automate **creation**, **update**, and **deletion** of Solace message queues
from a GitHub repository using Terraform and a Jenkins pipeline.

All YAML parsing is done in **native Groovy** — no Python, no extra scripts.

---

## Repository Structure

```
your-repo/
├── Jenkinsfile                   ← Pipeline (all logic lives here)
├── PlatformConfig.yaml           ← Solace host, VPN, Jenkins credential ID
├── MessageQueue.yaml             ← Regular queue names
├── DeadMessageQueue.yaml         ← Dead-message queue names
├── MessageQueueConfig.yaml       ← Settings for all regular queues
├── DeadMessageQueueConfig.yaml   ← Settings for all DMQs
├── .gitignore
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

---

## Pipeline Actions

| Action | What it does |
|---|---|
| `plan` | Terraform dry-run. Shows what will change. Makes zero changes to Solace. |
| `apply` | Creates / updates all queues listed in both YAML files. Idempotent — safe to re-run. |
| `destroy` | Deletes **all** Terraform-managed queues (full state wipe). Use with caution. |
| `delete-queues` | Calls Solace SEMPv2 REST API to delete **only** the queues listed in `MessageQueue.yaml` and `DeadMessageQueue.yaml`. Targeted — does not touch any other queues. |

> **Always run `plan` first** before `apply` or `destroy`.

---

## Prerequisites

### Jenkins Agent

| Tool | Minimum | Install |
|---|---|---|
| **Terraform** | 1.3.0 | https://developer.hashicorp.com/terraform/downloads |
| **Git** | any | OS package manager |

### Jenkins Plugins

Install from **Manage Jenkins → Plugins → Available**:

| Plugin | Used for |
|---|---|
| **Pipeline: Declarative** | Runs the `pipeline { }` block |
| **Pipeline Utility Steps** | `readYaml`, `readJSON`, `writeJSON` |
| **Git** | Repository checkout |
| **Credentials Binding** | `usernamePassword(...)` binding |
| **HTTP Request** | SEMPv2 API calls for `delete-queues` |
| **Workspace Cleanup** | `cleanWs()` |

---

## Step-by-Step Setup

### Step 1 — Push this project to GitHub

1. Create a GitHub repository (public or private).
2. Copy all files into the repo root, keeping the `terraform/` subfolder.
3. Commit and push to `main`.

---

### Step 2 — Add Credentials to Jenkins

Go to **Jenkins → Manage Jenkins → Credentials → System →
Global credentials → Add Credentials**.

#### Solace credentials (required)

| Field | Value |
|---|---|
| Kind | **Username with Password** |
| Username | Your Solace admin username |
| Password | Your Solace admin password |
| ID | `SOLACE_CREDENTIALS` |
| Description | Solace admin credentials |

> The ID `SOLACE_CREDENTIALS` must match the value of
> `solace_credentials_id` in `PlatformConfig.yaml`.

#### GitHub credentials (private repos only)

| Field | Value |
|---|---|
| Kind | Username with Password |
| Username | Your GitHub username |
| Password | Your GitHub Personal Access Token |
| ID | `GITHUB_CREDS` |

---

### Step 3 — Edit PlatformConfig.yaml

```yaml
solace:
  semp_url:              "https://<YOUR_HOST>:943"
  message_vpn:           "<YOUR_VPN_NAME>"
  solace_credentials_id: "SOLACE_CREDENTIALS"
```

Find your SEMP URL in:
**Solace Cloud → your service → Manage → SEMP - REST API → Secured SEMP URL**

---

### Step 4 — Define Queue Names

**MessageQueue.yaml**
```yaml
queues:
  - "q/PurchaseOrder/Create"
  - "q/OrderConfirmation/POST/Update"
  - "q/Inventory/Reserve"
```

**DeadMessageQueue.yaml**
```yaml
queues:
  - "dmq/PurchaseOrder/Create"
  - "dmq/OrderConfirmation/POST/Update"
```

Rules:
- Names can contain `/` (forward slash).
- The same name must **not** appear in both files.
- Names are case-sensitive.

---

### Step 5 — Tune Queue Settings (Optional)

Edit `MessageQueueConfig.yaml` and `DeadMessageQueueConfig.yaml`.
Leave any field as `""` to keep the Solace broker default.

| YAML Field | Solace UI Setting | Values |
|---|---|---|
| `ingress_enabled` | Incoming | `true` / `false` |
| `egress_enabled` | Outgoing | `true` / `false` |
| `access_type` | Access Type | `"exclusive"` / `"non-exclusive"` |
| `max_msg_spool_usage` | Messages Queued Quota (MB) | integer |
| `owner` | Owner | username string |
| `permission` | Non-Owner Permission | `"no-access"` `"read-only"` `"consume"` `"modify-topic"` `"delete"` |
| `max_bind_count` | Maximum Consumer Count | integer |
| `max_delivered_unacked_msgs_per_flow` | Max Delivered Unacked per Flow | integer |
| `dead_msg_queue` | DMQ Name | queue name string |
| `delivery_count_enabled` | Enable Client Delivery Count | `true` / `false` |
| `delivery_delay` | Delivery Delay (sec) | integer |
| `respect_msg_priority` | Respect Message Priority | `true` / `false` |
| `respect_ttl` | Respect TTL | `true` / `false` |
| `max_ttl` | Maximum TTL (sec) | integer |
| `redelivery_enabled` | Redelivery | `true` / `false` |
| `try_forever` | Try Forever | `true` / `false` |
| `max_redelivery_count` | Maximum Redelivery Count | integer |

---

### Step 6 — Create the Jenkins Job

1. **New Item** → name it `Solace-Queue-Provisioner` → **Pipeline** → OK
2. Under **Pipeline**:
   - Definition: `Pipeline script from SCM`
   - SCM: `Git`
   - Repository URL: `https://github.com/your-org/your-repo.git`
   - Credentials: `GITHUB_CREDS` (or leave blank for public)
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
3. **Save**
4. Click **Build Now** once — this discovers and registers the parameters.
   The first run will finish quickly (no parameters yet). That is expected.

---

### Step 7 — Run the Pipeline

Click **Build with Parameters** and fill in:

| Parameter | Value |
|---|---|
| `GITHUB_REPO_URL` | `https://github.com/your-org/your-repo.git` |
| `GITHUB_BRANCH` | `main` |
| `GITHUB_CREDENTIALS` | `GITHUB_CREDS` (or blank if public) |
| `TERRAFORM_ACTION` | Start with **`plan`** |

Click **Build**, open **Console Output**, review the plan,
then re-run with `apply` when ready.

---

## Using delete-queues

`delete-queues` calls the Solace SEMPv2 REST API directly — **no Terraform
state involved**. It reads the queue names from `MessageQueue.yaml` and
`DeadMessageQueue.yaml` and sends a `DELETE` request for each one.

- Queues that **do not exist** on the broker are silently skipped (not an error).
- Queues that **fail** to delete are reported in the log and the build is marked failed.
- The Operation Summary at the end shows deleted / skipped / failed counts.

To use it: select `TERRAFORM_ACTION = delete-queues` when triggering the build.

---

## Pipeline Stages

```
Stage 1   Validate Parameters     — required inputs are present
Stage 2   Checkout Repository     — clones GitHub repo
Stage 3   Validate Required Files — all YAML + TF files exist
Stage 4   Verify Terraform        — terraform on PATH (skipped for delete-queues)
Stage 5   Parse YAML Config       — Groovy reads & validates all 5 YAMLs,
                                    writes terraform.tfvars.json
Stage 6   Terraform Init          — downloads SolaceProducts provider (skipped for delete-queues)
Stage 7   Terraform Plan          — dry-run (skipped for delete-queues)
Stage 8   Terraform Apply/Destroy — runs only for apply or destroy
Stage 9   Delete Queues (SEMPv2)  — runs only for delete-queues
Stage 10  Collect Outputs         — logs Terraform output values (apply only)
Post      Operation Summary       — always printed, even on failure
          Cleanup                 — removes terraform.tfvars.json from disk
```

---

## Error Tracing

Every log line is tagged `[INFO]`, `[WARN]`, `[ERROR]`, or `[FATAL]`.
Search console output for `[ERROR]` or `[FATAL]` to jump to the root cause.

| Stage | Common errors |
|---|---|
| Validate Parameters | `GITHUB_REPO_URL` not provided |
| Checkout Repository | Wrong URL; wrong/missing GitHub credentials |
| Validate Required Files | YAML or `.tf` file missing from repo |
| Parse YAML Config | Blank `semp_url`, `message_vpn`, or `solace_credentials_id`; invalid `access_type` or `permission`; negative numeric; non-boolean in boolean field; same queue name in both YAML files |
| Terraform Init | No network to `registry.terraform.io` |
| Terraform Plan | Wrong SEMP URL; bad credentials; VPN not found |
| Terraform Apply | Quota exceeded; queue already exists outside TF state |
| Delete Queues | Wrong SEMP URL; bad credentials; queue has active consumers |

---

## Security Notes

- Credentials are bound via `usernamePassword(...)` — never written to files.
- `terraform.tfvars.json` is deleted from disk in `post { cleanup }`, even on failure.
- `terraform.tfvars.json` is in `.gitignore` — never committed to the repo.
- For team environments, configure a Terraform remote backend (S3, GCS, Terraform Cloud).
