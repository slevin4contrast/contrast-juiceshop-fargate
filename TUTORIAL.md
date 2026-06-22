# Instrumenting OWASP Juice Shop with Contrast on AWS Fargate

This guide walks through adding the Contrast Node.js agent to [OWASP Juice Shop](https://github.com/juice-shop/juice-shop) and deploying the instrumented app to AWS Fargate (ECS) with Terraform. The agent token is stored in AWS Secrets Manager and injected at runtime, which is Contrast's recommended pattern for cloud deployments.

The companion files in this folder are ready to adapt:

- `Dockerfile.contrast` — Juice Shop's distroless Dockerfile with the agent added
- `terraform/` — ECR, ECS/Fargate, ALB, IAM, and Secrets Manager wiring

> A note on accuracy: Contrast's product behavior and the Juice Shop build can change. The steps below were checked against the current Contrast docs, but verify against the live documentation linked throughout before sharing externally.

---

## What you'll end up with

A Juice Shop container running on Fargate behind an Application Load Balancer, with the Contrast agent preloaded. As you browse the app, the agent reports libraries, routes, and findings to your Contrast organization.

---

## Prerequisites

Before starting, confirm Juice Shop's stack is supported and gather what you need.

Juice Shop is a Node.js app (Express, Sequelize, SQLite/MarsDB). All of this is supported, and Contrast explicitly calls out SQLite and MarsDB as supported specifically to enable Juice Shop. Check the current matrix at [Supported technologies for Node.js](https://docs.contrastsecurity.com/en/node-js-supported-technologies.html) and [System requirements for the Node.js agent](https://docs.contrastsecurity.com/en/node-js-system-requirements.html).

You will need:

- A Contrast account with access to your organization's agent keys
- Docker, the AWS CLI (authenticated), and Terraform >= 1.5 installed locally
- An existing VPC with public subnets (for the load balancer) and subnets for the tasks
- A local checkout of Juice Shop: `git clone https://github.com/juice-shop/juice-shop.git`

One sizing note worth flagging up front: the agent increases CPU and memory use. Contrast recommends **doubling** the memory you would give the app without the agent when running Assess. The Terraform defaults here use 1 vCPU / 2 GB, which is a reasonable starting point for a demo.

---

## Step 1 — Get your Contrast agent token

The agent token is the modern, single-value credential. It is a base64 string that bundles the URL, API key, service key, and user name, so you only manage one secret. It is supported on Node.js agent 5.15.0 and later.

In Contrast, go to **Organization settings > Agent keys**, select a key name, and copy the **agent token**. Full steps with screenshots: [Find the agent keys](https://docs.contrastsecurity.com/en/find-the-agent-keys.html).

Keep this value out of source control. You'll hand it to Terraform via an environment variable in Step 5, and it lands in AWS Secrets Manager rather than in the image or task definition.

---

## Step 2 — Add the agent to the image

Juice Shop ships a multi-stage Dockerfile whose final image is **distroless** (`gcr.io/distroless/nodejs24-debian13`). Distroless images have no shell and no npm, so two things follow:

1. Install the agent in the **build stage**, where npm exists, so it gets copied into the final image.
2. Preload the agent with the `NODE_OPTIONS` environment variable rather than editing the `CMD`, since there's no shell to run an npm script. This is exactly the approach in Contrast's [distroless containers](https://docs.contrastsecurity.com/en/distroless-containers.html) guide, which uses Juice Shop as its example.

The provided `Dockerfile.contrast` does both. The two additions versus upstream are:

```dockerfile
# in the build (installer) stage, after npm install:
RUN npm install @contrast/agent

# in the final distroless stage, before CMD:
ENV NODE_OPTIONS="--import @contrast/agent"
```

The `--import @contrast/agent` form is the current preload syntax for ES modules. (On older Docker examples you may see `-r @contrast/agent` or `node --import @contrast/agent app`; for a non-distroless image you would put that in the `CMD` instead.)

General container guidance: [Install the Node.js agent using a container](https://docs.contrastsecurity.com/en/install-node-js-agent-in-a-container.html). A worked Juice Shop lab is in the support article [Node.js agent with Docker](https://support.contrastsecurity.com/hc/en-us/articles/360054526851-Node-js-agent-with-Docker).

> Optional, for faster cold starts: the agent rewrites code at startup, which adds time. The [agent rewriter CLI](https://docs.contrastsecurity.com/en/node-js-agent-rewriter-cli.html) pre-compiles the app in the build stage so tasks start faster. Worth adding once the basic deployment works.

> Avoid Alpine on ARM: Contrast does not support Alpine-based images on Apple M1/M2 (ARM64); use slim or distroless. Juice Shop's distroless image is fine. If you switch to a slim base, note the known [SSL issue with slim images](https://support.contrastsecurity.com/hc/en-us/articles/360060954571).

---

## Step 3 — Provision AWS and push the image

The Terraform in `terraform/` creates the ECR repository first, so the workflow is: init, create the repo, push the image, then apply the rest.

```bash
cd terraform
terraform init

# Create just the ECR repo so we have somewhere to push.
terraform apply -target=aws_ecr_repository.juice_shop \
  -var="vpc_id=vpc-xxxx" \
  -var='public_subnet_ids=["subnet-aaaa","subnet-bbbb"]' \
  -var='private_subnet_ids=["subnet-cccc","subnet-dddd"]'
```

Note the `ecr_repository_url` output, then build and push from your Juice Shop checkout. Copy `Dockerfile.contrast` into the root of that checkout first (the build context must be the Juice Shop source).

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/juice-shop-contrast"

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Build for the platform Fargate runs (linux/amd64 unless you use Graviton/ARM tasks).
docker build --platform linux/amd64 -f Dockerfile.contrast -t "$REPO:latest" .
docker push "$REPO:latest"
```

---

## Step 4 — Review the Terraform

A quick tour of what each file does:

- `versions.tf` — provider and version pinning
- `variables.tf` — all inputs, including Contrast settings and Fargate sizing
- `ecr.tf` — the container registry
- `secrets.tf` — stores the agent token in Secrets Manager
- `iam.tf` — task execution role (pull image, read the secret, write logs) and a task role
- `network.tf` — ALB, target group, listener, and security groups
- `ecs.tf` — cluster, CloudWatch log group, task definition, and service
- `outputs.tf` — the app URL, ECR URL, and log group

The important part is how the token reaches the container. The task definition does **not** put the token in plain text. It references the Secrets Manager ARN under `secrets`, and ECS injects it as the `CONTRAST__API__TOKEN` environment variable when the task starts:

```hcl
secrets = [
  {
    name      = "CONTRAST__API__TOKEN"
    valueFrom = aws_secretsmanager_secret.contrast_token.arn
  }
]
```

Application metadata that isn't sensitive is set as ordinary environment variables, following Contrast's recommended split of credentials in a secrets manager and app config in env vars: `CONTRAST__APPLICATION__NAME`, `CONTRAST__SERVER__NAME` (a stable name so churning tasks don't create many server records), and `CONTRAST__SERVER__ENVIRONMENT`. The full list of variables is in [Configure the Node.js agent](https://docs.contrastsecurity.com/en/node-js-configuration.html).

---

## Step 5 — Deploy

Provide the token via an environment variable so it never touches a file, then apply everything.

```bash
export TF_VAR_contrast_api_token="<paste your agent token>"

terraform apply \
  -var="vpc_id=vpc-xxxx" \
  -var='public_subnet_ids=["subnet-aaaa","subnet-bbbb"]' \
  -var='private_subnet_ids=["subnet-cccc","subnet-dddd"]'
```

Or copy `terraform.tfvars.example` to `terraform.tfvars`, fill in the network IDs, and keep the token in the environment variable. When it finishes, Terraform prints `juice_shop_url`.

> Outbound network access: the agent must reach the Contrast platform over HTTPS. If your tasks run in private subnets, make sure there's a NAT gateway. For a quick demo in public subnets, set `assign_public_ip = true`.

---

## Step 6 — Verify instrumentation

Two checks confirm it's working.

First, watch the container logs. Open the CloudWatch log group from the `log_group` output (or `aws logs tail /ecs/juice-shop-contrast --follow`). On startup you should see lines like:

```
Starting @contrast/agent v5.x.x
info: Detected Node.js version v... (OK)
info: Detected OS linux (OK)
info: Server listening on port 3000
```

Second, open `juice_shop_url` in a browser and click around the app. Within a minute or two the application appears in your Contrast organization, and as you exercise routes the agent reports libraries, route coverage, and vulnerabilities.

If the agent starts but can't connect, check the token value and the task's outbound HTTPS path. Useful references: [Node.js startup troubleshooting](https://support.contrastsecurity.com/hc/en-us/articles/9877427810068-Node-js-Startup-Troubleshooting) and [Connectivity issues with the Node agent](https://support.contrastsecurity.com/hc/en-us/articles/360025098992).

---

## Reference links

Contrast documentation:

- [Supported technologies for Node.js](https://docs.contrastsecurity.com/en/node-js-supported-technologies.html)
- [System requirements for the Node.js agent](https://docs.contrastsecurity.com/en/node-js-system-requirements.html)
- [Install the Node.js agent using a container](https://docs.contrastsecurity.com/en/install-node-js-agent-in-a-container.html)
- [Distroless containers](https://docs.contrastsecurity.com/en/distroless-containers.html)
- [Configure the Node.js agent](https://docs.contrastsecurity.com/en/node-js-configuration.html)
- [Find the agent keys](https://docs.contrastsecurity.com/en/find-the-agent-keys.html)
- [Reduce container startup time (agent rewriter CLI)](https://docs.contrastsecurity.com/en/node-js-agent-rewriter-cli.html)

Contrast support portal:

- [Deployment category](https://support.contrastsecurity.com/hc/en-us/categories/360004089371-Deployment)
- [AWS Fargate and Contrast agents](https://support.contrastsecurity.com/hc/en-us/articles/360056537312-AWS-Fargate-and-Contrast-agents)
- [Node.js agent with Docker](https://support.contrastsecurity.com/hc/en-us/articles/360054526851-Node-js-agent-with-Docker)
- [Node.js sample onboarding project (Juice Shop)](https://github.com/Contrast-Security-OSS/contrastsecurity-node-docker-onboarding-guide-sample-project)

AWS documentation:

- [Deploying Docker containers on Amazon ECS / Fargate](https://docs.aws.amazon.com/AmazonECS/latest/userguide/docker-basics.html)
- [Passing secrets to a container (Secrets Manager + ECS)](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data-secrets.html)
