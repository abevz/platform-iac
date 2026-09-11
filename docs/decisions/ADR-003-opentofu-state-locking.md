# ADR-003: OpenTofu state locking and backend

## Status

Proposed — 2026-09-11

This ADR is written **before** the experiment that decides it has been run.
The decision below is therefore expressed as a rule keyed to a probe result
(see *Context → The open question*). When the probe has run, record the
outcome in this section, keep the branch that was taken, and move the status
to Accepted.

Writing the rule first is deliberate: it fixes what evidence decides the
outcome before the outcome is known.

## Context

`platform-iac` stores OpenTofu state for the Proxmox components in a
self-hosted, S3-compatible object store. Eleven of the thirteen component
directories under `infra/dev/` carry a `backend.tf`; `ebpf-lab` and
`mailserver` use local state. Two of the eleven — `minio` and `nginx-proxy` —
are additionally forced onto local state at runtime by
`tools/iac-wrapper.sh`, because they bootstrap the object store and the
reverse proxy that the backend itself depends on.

Every `backend.tf` is the same five settings, and `bucket`, `key` and
`endpoint` are injected at init time by the wrapper:

```hcl
terraform {
  backend "s3" {
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
```

Three facts make this a decision rather than a chore:

**There is no state locking at all today.** No `backend.tf` sets
`use_lockfile`, and none sets `dynamodb_table`. Concurrent runs are prevented
only by the fact that one operator runs them one at a time.

**The object store is no longer MinIO.** It was migrated to RustFS
`1.0.0-beta.8` on 2026-06-24 (recorded in ADR-001 *Status*, detailed in
`docs/runbook-rustfs-minio-replacement.md`). The container is still named
`minio-server` and the secrets are still called `MINIO_*` for compatibility,
which makes the change easy to overlook. The pinned version is a pre-1.0
beta.

**Locking on the S3 backend depends on a feature the store may not have.**
OpenTofu's `use_lockfile` implements locking through S3 conditional writes —
a `PutObject` carrying `If-None-Match: *`, which must fail with
`412 Precondition Failed` when the lock object already exists. Nothing in
this repository asserts that RustFS honours that precondition. The RustFS
project has an open issue for `If-None-Match` support on *GET*; conditional
*writes* are unconfirmed. The RustFS migration runbook validated only state
reads and raw throughput.

OpenTofu version is not a constraint: the toolchain is 1.12.1 and
`use_lockfile` requires ≥ 1.10. Only `infra/dev/k8s-lab-01` declares a
`required_version` (`>= 1.11.0`); most components declare none, and
`.tflint.hcl` disables the rule that would flag it.

A stale operational document compounds the problem.
`docs/iac-wrapper.md` documents recovery from a stuck lock via a DynamoDB
error (`ConditionalCheckFailedException`, "wait 15 minutes") for a backend
that has never had DynamoDB. Anyone who hits a real lock will follow a
procedure that cannot apply.

### Why this is being decided now

The next planned work extracts the duplicated Proxmox VM block into a shared
module and migrates components onto it. Each migration rewrites resource
addresses inside state via `moved` blocks — eleven state-mutating operations.
That is precisely the work during which protection against a concurrent or
half-finished write matters most, and during which the ability to restore a
previous state version is the difference between a mistake and a loss.

Deciding locking *after* that work would be deciding it too late.

### The failure mode that drives the decision

The bad outcome is not "locking does not work". It is **locking that appears
to work**. If the store accepts the conditional `PutObject` and returns `200`
instead of `412`, OpenTofu will report that it holds a lock while no mutual
exclusion exists. That is strictly worse than today's honest absence of
locking, because it converts a known limitation into a false guarantee.

### The open question

Does RustFS `1.0.0-beta.8` honour `If-None-Match` on `PutObject`?

This is answered by experiment, not by documentation:

1. A direct probe — write an object twice against a throwaway key, the second
   time with `If-None-Match: *`, and check for `412`.
2. A decisive end-to-end probe — a scratch state key with
   `use_lockfile = true`, and two concurrent `tofu plan` runs. Exactly one
   must wait for the lock.

The second probe is authoritative; the first is only a fast pre-check.

## Decision

Adopt a decision rule rather than a fixed backend, and settle locking
**before** any state-address refactor begins.

**If the probe returns `412`** — keep RustFS and enable native locking:

- set `use_lockfile = true` in every S3 `backend.tf`;
- replace the deprecated `force_path_style` with `use_path_style` in the same
  change;
- re-run the concurrency probe against a real component's state to confirm
  the lock is genuine.

**If the probe returns `200`, or the result is ambiguous** — do not enable
`use_lockfile`, and migrate state to **GitLab-managed state** on the existing
self-hosted GitLab instance:

- switch `backend "s3"` to `backend "http"`, with `address`, `lock_address`,
  `unlock_address`, `username`, `password`, `lock_method = POST`,
  `unlock_method = DELETE` and `retry_wait_min`;
- keep one state per component, named `dev-<component>`, mirroring the
  current `infra/<env>/<component>.tfstate` key;
- migrate with `tofu init -migrate-state`, one component at a time, each
  preceded by `tofu state pull` to a backup file;
- store the GitLab token in SOPS alongside the existing object-store
  credentials;
- update `tools/iac-wrapper.sh`, which assembles the backend configuration in
  six places.

**In both branches, unconditionally:**

- verify that object versioning is enabled on the state bucket before any
  migration, and enable it if not — while locking is absent or unproven,
  versioning is the only recovery mechanism that exists;
- correct the stuck-lock recovery procedure in `docs/iac-wrapper.md`;
- prove locking by a concurrency test rather than by configuration review;
- treat the backend change as its own change set — never combined with a
  `moved` refactor, because the two mutate state for unrelated reasons and a
  combined failure is hard to attribute.

`minio` and `nginx-proxy` are out of scope in both branches. They run on
local state by design, and the wrapper deletes `.terraform.lock.hcl` on every
run for them. Giving the bootstrap path a locked remote backend is a separate
problem: the backend cannot depend on the components that bring it up.

## Consequences

**Positive, either branch**

- State mutation during the module migration is protected, and a prior
  version is recoverable.
- The stale DynamoDB recovery procedure stops being a trap.
- The locking claim becomes something demonstrated rather than configured.

**Positive, GitLab branch specifically**

- Versioning, encryption in transit and at rest, and locking arrive together
  rather than as three separate pieces of work.
- The most critical data in the platform stops living in a pre-1.0 beta store.
- No new service: the instance already hosts the repository.

**Negative, `use_lockfile` branch**

- Locking correctness continues to rest on a beta implementation, and a
  future RustFS upgrade could regress it silently. Re-running the concurrency
  probe becomes part of upgrading the object store.

**Negative, GitLab branch**

- `tools/iac-wrapper.sh` changes in six places, and the backend configuration
  grows from five injected values to eight.
- Eleven state migrations, each a real state operation.
- The dependency moves rather than disappears: OpenTofu currently cannot run
  without the object store, and would then not run without GitLab. GitLab is
  a heavier service, though both are reached through the same reverse proxy,
  so the class of outage is unchanged.
- A GitLab token with `api` scope joins the Day-0 SOPS material and needs
  rotation.

**Neutral**

- Component `.tf` files change in either branch, so both require the same
  review and pre-commit discipline.
- Bootstrap components remain unlocked either way.

## Alternatives Considered

### A. Do nothing — rejected

Defensible while a single operator runs changes serially by hand, and it has
held so far. It stops being defensible immediately before eleven scripted
state migrations, and it leaves the misleading recovery documentation in
place. The wrapper also touches the backend three to four times per `apply`
(`init`, `apply`, `refresh`, `tofu output`, plus an independent
`tofu output -json` from `tools/add_pihole_dns.py`), so the window for a
partial write is wider than "one command at a time" suggests.

### B. External lock table alongside RustFS — rejected

The S3 backend's DynamoDB locking path is an AWS-specific mechanism and has
no equivalent here; emulating it would mean operating a lock service purely
to compensate for the object store. That is more moving parts than either
selected option, for the same guarantee.

### C. Migrate back to MinIO — rejected

MinIO does implement conditional writes, so this would work. But it reverses
a migration completed on 2026-06-24 for other reasons, pays a second
migration cost, and solves only locking — versioning and encryption would
still need separate attention. If RustFS is the wrong store for state, moving
state off it entirely is a better answer than moving the store back.

### D. Move state to managed AWS S3 — deferred

Native conditional writes, versioning, and no self-hosted dependency. It also
introduces a permanent cloud dependency and a recurring cost for a homelab
whose stated operating model includes being powered off at night, and it
splits the platform's trust boundary across a provider that hosts nothing
else here. Reasonable if the self-hosted options both fail; not first.

### E. Selected — conditional on the probe

`use_lockfile` on RustFS when the store proves it supports conditional
writes, because it is a one-line change per component and keeps the current
architecture. GitLab-managed state when it does not, because it resolves
locking, versioning and encryption in a single move onto infrastructure that
already exists, and removes state from a beta store.

The probe decides. Choosing either branch before running it would be a
preference presented as an engineering decision.

## Implementation Roadmap

1. **Probe.** Fast pre-check, then the two-concurrent-`plan` test on a
   throwaway state key. Record the raw result — it is the evidence this ADR
   rests on.
2. **Versioning.** Check `get-bucket-versioning` on the state bucket; enable
   if absent. Independent of the branch taken.
3. **Branch.** Either enable `use_lockfile` (plus `use_path_style`), or
   migrate state to GitLab one component at a time, each with a pulled backup
   and an empty `plan` as the acceptance check.
4. **Prove it.** Re-run the concurrency test against a real component.
5. **Documentation.** Replace the DynamoDB recovery section in
   `docs/iac-wrapper.md` with the procedure that matches the backend in use,
   including how to clear an orphaned lock. Note that a lock file left behind
   by a killed run has no expiry, unlike the DynamoDB leases the old text
   described.
6. **Only then** begin the shared-module extraction and the `moved`
   migrations.

A controlled failure drill belongs at step 4: kill a run mid-`apply`, observe
the orphaned lock, recover, and record the real procedure. If the probe showed
locking to be absent, the drill is the demonstration of two concurrent applies
diverging — which is the finding, not a failure of the exercise.

## Forward References

- [ADR-001](ADR-001-vault-based-secrets-architecture.md) — SOPS as the Day-0
  bootstrap store; the RustFS migration note in its Status section.
- [iac-wrapper](../iac-wrapper.md) — assembles the backend configuration, and
  carries the stuck-lock section this ADR requires be corrected.
- [RustFS/MinIO replacement runbook](../runbook-rustfs-minio-replacement.md) —
  what the migration validated, and what it did not.

## References

- OpenTofu S3 backend, `use_lockfile`: https://opentofu.org/docs/language/settings/backends/s3/
- Amazon S3 conditional writes: https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes/
- RustFS `If-None-Match` issue: https://github.com/rustfs/rustfs/issues/791
- GitLab-managed Terraform/OpenTofu state: https://docs.gitlab.com/user/infrastructure/iac/terraform_state/
- `glab opentofu`: https://docs.gitlab.com/cli/opentofu/
