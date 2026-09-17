# Retired Stalwart ingress

The shared `stalwart-edge` now owns public SMTP. Manafish mailboxes and JMAP
remain in `manafishrov-stalwart`. This bundle retains only the legacy namespace;
Flux removes its workload, Services, routes, policy and backup scheduler.

The drained server's `data-stalwart-0` PVC is retained for rollback. Historical
Restic backups remain untouched. Neither is an active mailbox backend. Old
manifests remain as migration references, not active Kustomize resources;
`reconciler.yaml` is also consumed by the retirement regression tests.
