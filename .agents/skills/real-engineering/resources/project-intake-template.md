# Project Intake and Acceptance Template

Use this template at the start of a new project or major feature. Fill known fields from the user's request and repository. Do not invent answers. Ask only for missing information that materially changes implementation.

## Project
- Name:
- Purpose / user problem:
- Intended users:
- Target platform(s):
- Delivery target (local, staging, production, store, etc.):
- Existing repository or new project:
- Current state and known limitations:

## Requirements
- Core user journeys:
- Required features:
- Explicitly excluded features:
- Data sources / source of truth:
- Meaning of “real-time” for this project:
- Persistence requirements:
- Integrations and external services:
- Authentication / roles / tenant boundaries:
- Performance / scale constraints:
- Accessibility / device constraints:

## Environment
- Existing stack and versions (verify):
- Hosting / deployment:
- Database / storage:
- Required environment variables (names only; never paste secrets):
- Available credentials / access:
- Budget or service-tier limits:

## Acceptance criteria
For each feature, specify:
- Given:
- When:
- Then:
- Failure/empty/offline behavior:
- Authorization expectation:
- Test/evidence required:

## Risks and approvals
- Destructive operations:
- Production impact:
- Cost impact:
- Privacy/security impact:
- Rollback/recovery plan:

## Decision log
| Date | Decision | Status (proposed/finalized) | Reason | Consequences |
|---|---|---|---|---|

## Delivery evidence
- Commands run:
- Results:
- Integration checks:
- End-to-end checks:
- Deployment verification:
- Known gaps / blocked checks:
