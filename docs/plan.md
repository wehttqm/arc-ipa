# Project Plan: Infrastructure Provisioning Agent (AgentCore)

**Team:** Platform Foundation (PFND)
**Author:** Matthew Falcone
**Date:** May 29, 2026
**Status:** Draft — Pending review with AWS (Ari's team)

---

## 1. Project Overview

### What Are We Building?

An AI agent built on **AWS AgentCore** that enables Arc'teryx development teams to self-service provision standard cloud infrastructure through a conversational interface. Instead of filing a ticket and waiting for Platform Foundation to manually run Terraform, developers describe what they need and the agent provisions it — following all existing standards (tagging, naming, account boundaries, security).

### Why Now?

This project directly supports three 2026 Platform Foundation objectives:

| Objective | How This Project Helps |
|---|---|
| **KR2-1** — Self-service cloud infrastructure reaching 70% of users | This *is* the self-service mechanism |
| **KR4-3** — Pilot two GenAI platform features by end of Q3 | This is one of the two pilots |
| **KR5-1** — Explore automation and agentic efforts | Direct exploration of agentic platform engineering |

### Problem Statement

Today, when a dev team needs infrastructure (an S3 bucket, a Lambda, a new namespace, a database), they:
1. File a PFND Jira ticket
2. Wait for a Platform Foundation engineer to pick it up
3. The engineer runs Terraform manually or updates IaC repos
4. Back-and-forth on naming, tagging, account placement

This creates bottlenecks, slows teams down, and consumes Platform Foundation engineering time on repetitive work that follows well-defined patterns.

### What Success Looks Like

- A developer can request standard infrastructure and have it provisioned in **minutes, not days**
- All provisioned resources comply with Arc'teryx standards (tagging, naming, account structure) **by default**
- Platform Foundation engineers spend less time on routine provisioning and more time on complex/novel work
- The agent handles the top 3-5 most common infrastructure request types

---

## 2. User Stories

### Epic: Self-Service Infrastructure Provisioning Agent

#### Core User Stories (MVP)

**US-1: Request a standard S3 bucket**
> As a developer, I want to ask the agent to create an S3 bucket in my team's preprod account so that I don't have to file a ticket and wait for Platform Foundation.

Acceptance Criteria:
- Agent applies correct naming convention (e.g., `arcteryx-{team}-{env}-{purpose}`)
- Agent applies required tags (team, environment, cost-center, application)
- Agent provisions via existing Terraform module
- Agent returns the bucket ARN and confirms creation
- Provisioning is blocked for prod without an approval step

---

**US-2: Request a Kubernetes namespace**
> As a developer, I want to request a new Kubernetes namespace for my service so that I can deploy my application without waiting for the platform team.

Acceptance Criteria:
- Agent creates namespace with standard labels and resource quotas
- Agent applies network policies per existing standards
- Agent configures Datadog monitoring integration for the namespace
- Agent returns namespace name and confirms it's ready for deployment

---

**US-3: Provision a Lambda + API Gateway**
> As a developer, I want to ask the agent to set up a Lambda function with an API Gateway endpoint so that I can quickly stand up a new microservice.

Acceptance Criteria:
- Agent uses existing Terraform modules for Lambda and API Gateway
- Agent configures VPC links per account standard
- Agent sets up CloudWatch logging and Datadog integration
- Agent applies IAM role with least-privilege permissions
- Agent returns the API endpoint URL and Lambda ARN

---

**US-4: Validate requests against standards**
> As a Platform Foundation engineer, I want the agent to enforce our tagging, naming, and account standards so that no non-compliant resources are created.

Acceptance Criteria:
- Agent rejects requests missing required tags
- Agent auto-suggests correct naming based on conventions
- Agent refuses to provision in the wrong account (e.g., prod resources in a dev account)
- Agent logs all provisioning actions for audit

---

**US-5: Approval gate for production**
> As a Platform Foundation engineer, I want production provisioning requests to require my approval so that we maintain governance over the production environment.

Acceptance Criteria:
- Agent flags any prod request as requiring approval
- Agent notifies a PFND engineer (Slack or Jira) with the request details
- Agent only proceeds after explicit approval
- Preprod/dev requests proceed without approval

---

#### Stretch User Stories (Post-MVP)

**US-6: Onboard a service to Datadog**
> As a developer, I want the agent to register my new service in the Datadog service catalog and set up basic dashboards so that I have observability from day one.

---

**US-7: Request AWS account access**
> As a new developer, I want to ask the agent for access to my team's AWS account so that I can start working without navigating the SSO request process manually.

---

**US-8: Cost estimate before provisioning**
> As a developer, I want the agent to give me an estimated monthly cost before provisioning resources so that I can make informed decisions.

---

**US-9: Tear down temporary environments**
> As a developer, I want to ask the agent to destroy a temporary dev environment I no longer need so that we don't accumulate unused resources and costs.

---

## 3. Milestones & Timeline

> **Note:** Timeline assumes ~4 months of co-op term remaining. Milestones are scoped to be achievable with support from AWS (Ari's team) in working sessions.

### Milestone 0: Foundation (Weeks 1–2)
- [ ] Get AgentCore access and set up development environment
- [ ] Complete AgentCore tutorials/getting-started with Ari's team
- [ ] Deploy a "hello world" agent that responds to basic prompts
- [ ] Identify which existing Terraform modules to integrate first

**Deliverable:** Working AgentCore agent in a sandbox that can respond to messages.

### Milestone 1: Single Resource Provisioning (Weeks 3–5)
- [ ] Agent can provision an S3 bucket using existing Terraform module
- [ ] Agent enforces naming and tagging standards
- [ ] Agent targets the correct AWS account (preprod only)
- [ ] Basic error handling (what if Terraform fails?)

**Deliverable:** US-1 complete. Demo to team.

### Milestone 2: Expanded Resource Types (Weeks 6–9)
- [ ] Add Kubernetes namespace provisioning (US-2)
- [ ] Add Lambda + API Gateway provisioning (US-3)
- [ ] Standards validation logic is reusable across resource types (US-4)
- [ ] Agent handles multi-step conversations ("which account?" → "what tags?" → "confirm?")

**Deliverable:** US-1 through US-4 complete. Demo to stakeholders.

### Milestone 3: Governance & Production Readiness (Weeks 10–13)
- [ ] Production approval gate (US-5)
- [ ] Audit logging of all agent actions
- [ ] Integration with Slack or Jira for notifications
- [ ] Documentation and runbook for the agent itself
- [ ] Stretch: Datadog onboarding (US-6)

**Deliverable:** Agent ready for pilot with 1-2 dev teams.

### Milestone 4: Pilot & Iterate (Weeks 14–16)
- [ ] Pilot with one volunteer dev team
- [ ] Collect feedback, fix issues
- [ ] Measure: time-to-provision before vs. after
- [ ] Write up results and recommendations for scaling

**Deliverable:** Pilot results, recommendations for FY27 expansion.

## 4. Risks, Assumptions & Dependencies

### Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AgentCore is new/immature — may hit limitations | Medium | High | Ari's team provides working sessions; we scope MVP small |
| Agent provisions something incorrectly | Medium | High | Preprod-only for MVP; approval gate for prod; audit logging |
| Existing Terraform modules aren't agent-friendly (need refactoring) | Medium | Medium | Identify modules early in M0; keep scope to well-tested modules |
| Co-op timeline too short to reach M4 | Low | Medium | M1-M2 are valuable on their own; M3-M4 are stretch |
| Security concerns with agent having AWS access | Low | High | Least-privilege IAM role; preprod only; all actions logged |

### Assumptions

- Ari's team will provide working sessions (1-2 per sprint) to help with AgentCore setup and troubleshooting
- Existing Terraform modules for S3, Lambda, API Gateway are stable and reusable
- The team's Kubernetes namespace creation process can be codified
- Preprod AWS accounts are safe to experiment in
- Matthew has (or can get) access to the relevant GitHub repos and AWS accounts

### What We Need from AWS (Ari's Team)

1. **AgentCore access** — sandbox/dev environment to build in
2. **Working sessions** — ideally biweekly, to unblock and guide architecture decisions
3. **Reference examples** — any existing AgentCore agents doing infrastructure provisioning
4. **Documentation** — AgentCore SDK docs, best practices for tool integration
5. **Guidance on** — how to connect AgentCore to Terraform execution (Lambda? CodeBuild? Step Functions?)

### What We Need from Platform Foundation (Internal)

1. **Terraform module inventory** — which modules are stable and ready to be called by an agent?
2. **Standards documentation** — formalized tagging, naming, and account rules (some exists already)
3. **Preprod access** — IAM role for the agent with appropriate permissions
4. **Feedback** — which provisioning requests are most common / most painful today?
5. **Sponsor support** — Paul's backing for this as a KR4-3 pilot

---

## 5. Out of Scope (for now)

- Production provisioning without approval (always requires human-in-the-loop)
- Provisioning outside AWS (GCP, on-prem)
- Complex multi-service architectures (agent handles single resources or simple combos)
- Replacing the IDP initiative (this complements it — agent could live inside the IDP later)
- Cost optimization or remediation (separate agent opportunity)

---

## 6. How to Measure Success

| Metric | Baseline (Today) | Target |
|---|---|---|
| Time to provision standard infra | Days (ticket-based) | Minutes (agent-based) |
| % of provisioning requests handled without PFND engineer | 0% | 50%+ for supported resource types |
| Standards compliance of provisioned resources | Variable (human-dependent) | 100% (agent-enforced) |
| Developer satisfaction with provisioning process | TBD (survey) | Measurable improvement |

---

## Appendix: Relevant Confluence Pages

- [Areas of Responsibility](https://arcteryx.atlassian.net/wiki/spaces/PFND/pages/5193302028/Areas+of+Responsibility)
- [Platform Standard: IaC tool - Terraform](https://arcteryx.atlassian.net/wiki/spaces/PFND/pages/5344624879/Platform+Standard+IaC+tool+-+Terraform)
- [Business Case - Internal Developer Portal](https://arcteryx.atlassian.net/wiki/spaces/PFND/pages/5700845757/Business+Case+-+Internal+Developer+Portal+IDP)
- [2026 CFS Objectives](https://arcteryx.atlassian.net/wiki/spaces/PFND/pages/7087358002/2026+CFS+Objectives+for+Platform+Foundation)
- [Arcteryx AWS Account Standard](https://arcteryx.atlassian.net/wiki/spaces/PFND/pages/4745265197/Arcteryx+AWS+Account+Standard)
- [Arcteryx SSO User AWS Roles & Permission](https://arcteryx.atlassian.net/wiki/spaces/PFND/pages/7386136643/Arcteryx+SSO+User+AWS+Roles+Permission)
