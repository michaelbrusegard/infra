# Retired Stalwart edge archive

Postfix in `../smtp-edge` replaces the routing edge. No server, policy service,
readiness writer, management Service or edge Terraform stack remains here.
The implementation is available in Git history before the Postfix cutover.

Retained deliberately:

- `data-stalwart-edge-0`, bound to
  `pvc-eb11adef-5e42-40af-a01a-6f6059f6fc78`; namespace/PVC pruning disabled.
- Freddo repository `/stalwart/edge-pvc` and its historical snapshots.
- Final quiesced backup `7c590f8e` on 2026-09-18, after complete old-edge and
  backend queue inventories were empty and existing SMTP sessions had closed.
- A paused backup declaration and its encrypted repository credentials; no
  scheduled retention/pruning of the retired archive.

The older `/stalwart/pvc` archive is unchanged. Do not delete either archive or
this volume as part of routine deployment cleanup. Restoring a historical
queue requires accounting for mail already delivered since its snapshot.
