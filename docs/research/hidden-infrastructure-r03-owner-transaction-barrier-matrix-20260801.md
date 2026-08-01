# R03 owner transaction barrier matrix

Task: `cmd_karo_hotfix_hidden_infra_r03_owner_transaction_20260801_normal`  
Contract fingerprint input: task `ac_version=e417e507` + this matrix + focused fixture.

## Authority decision

Every operational YAML side effect is executed by `durable_state guarded-yaml-set` while holding the same per-subject lock used by `begin`/`mutate`. Inside that lock it revalidates subject, fence, phase, payload hash, and owner pointer before invoking `yaml_field_set.sh`. A lease is advisory for recovery only; TTL expiry never authorizes an old process to write. Thus an old finisher stopped after an earlier assertion can resume, but its next conditional mutation observes the new fence and exits 4 before touching YAML.

## Complete matrix

| row | side effect | stop point immediately before | concurrent writer | side-effect fence | stale caller bytes | real startup | fingerprint regenerated |
|---:|---|---|---|---|---|---|---|
| 1 | target prepared file publish | after intended | begin generation+1 | intended fence in publisher/reconciler | unchanged or idempotent prepared artifact | yes | yes |
| 2 | owner pointer ledger to prepared | after target publish | begin generation+1 | `mutate(expected_fence, prepared)` | state CAS rejects | yes | yes |
| 3 | source `status=transferred` | after prepared assertion / TTL | begin generation+1 | guarded-yaml-set(prepared, pointer) | source+target bytes unchanged | yes | yes |
| 4 | source `owner_transaction_status=tombstoned` | after source status | begin generation+1 | guarded-yaml-set(prepared, pointer) | second field rejected; first is convergent | yes | yes |
| 5 | target `status=assigned` | after tombstone | begin generation+1 | guarded-yaml-set(prepared, pointer) | target remains non-executable | yes | yes |
| 6 | target `owner_transaction_status=active` | after activation status | begin generation+1 | guarded-yaml-set(prepared, pointer) | metadata write rejected; owner count remains <=1 | yes | yes |
| 7 | durable phase `published` | after target activation | begin generation+1 | `mutate(expected_fence, published)` | state CAS rejects | yes | yes |
| 8 | durable phase `terminal` | after published | begin generation+1 | reconcile lock+fence | stale generation cannot terminalize current | yes | yes |

Focused test enumerates rows 1-8, plus the required adversarial schedule: old finisher passes assertion, stops, TTL expires, writer 2 begins, old finisher resumes. Required results are old rc=4, source/target pre/post SHA-256 identical, `lost_update=0/N`, `false_success=0/N`, and final executable owner count `<=1` after actual `ninja_monitor.sh` startup reconciliation.
