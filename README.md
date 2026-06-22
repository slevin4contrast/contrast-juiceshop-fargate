# Contrast + OWASP Juice Shop on AWS Fargate

Deploy [OWASP Juice Shop](https://github.com/juice-shop/juice-shop) to AWS Fargate, instrumented with the [Contrast Security](https://www.contrastsecurity.com/) Node.js agent, using Terraform. The Contrast agent token is stored in AWS Secrets Manager and injected at runtime, so no credentials live in the image, the task definition, or source control.

This is an example/demo project. Juice Shop is an intentionally insecure application, so deploy it only in a throwaway, non-production AWS account and lock down inbound access.

## What's here

```
.
├── TUTORIAL.md                  # Step-by-step walkthrough (start here)
├── Dockerfile.contrast          # Juice Shop's distroless image + Contrast agent
└── terraform/
    ├── versions.tf              # Provider + version pinning
    ├── variables.tf             # Inputs: Contrast settings, networking, sizing
    ├── ecr.tf                   # Container registry
    ├── secrets.tf               # Contrast token in Secrets Manager
    ├── iam.tf                   # Task execution + task roles
    ├── network.tf               # ALB, target group, listener, security groups
    ├── ecs.tf                   # Cluster, log group, task definition, service
    ├── outputs.tf               # App URL, ECR URL, log group
    └── terraform.tfvars.example # Copy to terraform.tfvars and fill in
```

## How it works

Juice Shop ships a **distroless** container image (no shell, no npm). The agent is therefore installed in the Docker build stage and preloaded at runtime via `NODE_OPTIONS="--import @contrast/agent"`, following Contrast's [distroless containers](https://docs.contrastsecurity.com/en/distroless-containers.html) guidance. On Fargate, the ECS task definition references the agent token by its Secrets Manager ARN and injects it as the `CONTRAST__API__TOKEN` environment variable when the task starts.

The defaults are tuned for an **ADR (Application Detection and Response)** evaluation: Protect and observe mode are on, and the server environment is set, which is what ADR requires. See the "Agent capabilities" section of [TUTORIAL.md](./TUTORIAL.md) to adjust.

## Quickstart

You need Docker, the AWS CLI (authenticated), Terraform >= 1.5, an existing VPC with subnets, and a Contrast agent token.

```bash
# 1. Get an agent token from Contrast: Organization settings > Agent keys
export TF_VAR_contrast_api_token="<paste your agent token>"

# 2. Create the ECR repo first
cd terraform
terraform init
terraform apply -target=aws_ecr_repository.juice_shop \
  -var="vpc_id=vpc-xxxx" \
  -var='public_subnet_ids=["subnet-aaaa","subnet-bbbb"]' \
  -var='private_subnet_ids=["subnet-cccc","subnet-dddd"]'

# 3. Build the instrumented image from a Juice Shop checkout and push it.
#    Copy Dockerfile.contrast into the root of your juice-shop clone first.
#    (full commands in TUTORIAL.md)

# 4. Apply the rest
terraform apply \
  -var="vpc_id=vpc-xxxx" \
  -var='public_subnet_ids=["subnet-aaaa","subnet-bbbb"]' \
  -var='private_subnet_ids=["subnet-cccc","subnet-dddd"]'
```

Terraform prints `juice_shop_url`. Open it, browse the app, and the instrumented application appears in your Contrast organization. The full walkthrough, including verification and troubleshooting, is in **[TUTORIAL.md](./TUTORIAL.md)**.

## Security notes

- The Contrast token is sensitive. Pass it via `TF_VAR_contrast_api_token` rather than a committed file. `terraform.tfvars` and `*.tfvars` are gitignored.
- Fargate task memory defaults to 2 GB because Contrast recommends doubling memory when running Assess.
- Tasks need outbound HTTPS to reach the Contrast platform. Use a NAT gateway for private subnets, or set `assign_public_ip = true` for a quick public-subnet demo.

## References

- [Contrast Node.js agent in a container](https://docs.contrastsecurity.com/en/install-node-js-agent-in-a-container.html)
- [Distroless containers](https://docs.contrastsecurity.com/en/distroless-containers.html)
- [Find the agent keys](https://docs.contrastsecurity.com/en/find-the-agent-keys.html)
- [AWS Fargate and Contrast agents](https://support.contrastsecurity.com/hc/en-us/articles/360056537312-AWS-Fargate-and-Contrast-agents)
- [Contrast Deployment support category](https://support.contrastsecurity.com/hc/en-us/categories/360004089371-Deployment)

## Disclaimer

Not an official Contrast Security project. Contrast product behavior and the Juice Shop build change over time; verify against the current [Contrast documentation](https://docs.contrastsecurity.com/) before relying on these steps. OWASP Juice Shop is a trademark of the OWASP Foundation; this repo is for security testing and education only.

## License

[MIT](./LICENSE)
