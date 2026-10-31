# VRMC Documentation

| Document | Purpose |
|---|---|
| [`../AGENT.md`](../AGENT.md) | Operating manual: architecture, hardness register, spikes, milestones, agent rules |
| [`../VERIFY.md`](../VERIFY.md) | Acceptance criteria, test suites, evidence log, sign-off |
| [`mvp/MVP_SCOPE.md`](mvp/MVP_SCOPE.md) | MVP scope decisions, in/out boundaries, priorities |
| [`mvp/SPIKES.md`](mvp/SPIKES.md) | S1–S6 spike procedures, pass criteria, artifacts, fallbacks |
| [`mvp/ACCEPTANCE.md`](mvp/ACCEPTANCE.md) | How acceptance is measured and evidenced |
| [`adr/`](adr/) | Architecture decision records |
| [`../README.md`](../README.md) | Project overview and quick start |
| [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) | Licenses and components |

Rules of the documentation set:

- `AGENT.md` is the process/architecture authority; `VERIFY.md` is the acceptance authority.
- The feature register of record is `AGENT.md` §4.3. `mvp/MVP_SCOPE.md` records scope decisions and
  must not duplicate the register.
- Spike procedures live in `mvp/SPIKES.md`; status lives in `VERIFY.md` and is summarized in
  `AGENT.md` §4.5/§6. When a spike status changes, apply `AGENT.md` §4.7.
