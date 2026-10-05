#!/usr/bin/env bash
set -euo pipefail

# Check the rendered policy, including overrides applied by parent overlays.
kustomize build gitops/espresso/infrastructure/configs |
  yq -o=json -I=0 'select(.kind == "Terraform") | {"name": .metadata.name, "approval": .spec.approvePlan}' |
  jq --slurp --exit-status '
    . as $policies |
    if (["manafishrov-dns", "manafishrov-stalwart", "manafishrov-rustfs", "mattermost"]
        - map(.name) | length == 0) and
       all($policies[]; .approval == "auto")
    then "OpenTofu approval policy passed"
    else error("Unexpected OpenTofu approval policy: \($policies)")
    end
  '
