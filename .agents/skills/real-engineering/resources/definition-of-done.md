# Definition of Done — Real Engineering

A feature is not done just because the interface looks correct or the code compiles.

## Required checks
- [ ] Acceptance criteria are met or gaps are explicitly listed.
- [ ] Real source-of-truth integration is implemented where required.
- [ ] No mock/stub/fake data is used in production paths.
- [ ] Writes persist and are verified with a trusted read-back where relevant.
- [ ] Server-side/database-side authorization and validation are present.
- [ ] Loading, empty, stale, offline, and failure states are truthful where relevant.
- [ ] Tests cover normal behavior and important failure paths.
- [ ] Relevant lint/type/unit/integration/e2e/build checks were actually run.
- [ ] Existing features affected by the change were regression-checked.
- [ ] Security, resource use, and cost risks were considered.
- [ ] Documentation/configuration/migration instructions were updated.
- [ ] Deployment status is accurately stated.
- [ ] Blocked or unverified checks are listed.
- [ ] Final report contains evidence and no unsupported success claims.

## Status vocabulary
- **Implemented:** code/configuration exists.
- **Locally verified:** behavior/check was observed in local environment.
- **Integration verified:** real service boundary was exercised in a controlled environment.
- **Production verified:** the deployed production path was actually checked.
- **Blocked:** could not verify due to a named missing dependency, permission, credential, or environment.
- **Not implemented:** the requested behavior is not present.

Never use these statuses interchangeably.
