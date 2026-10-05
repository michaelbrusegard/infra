#!/usr/bin/env bash
set -euo pipefail

# Check the rendered policy, including overrides applied by parent overlays.
kustomize build gitops/espresso/infrastructure/configs |
  yq -o=json -I=0 'select(.kind == "Terraform") | {"name": .metadata.name, "approval": .spec.approvePlan}' |
  jq --slurp --exit-status '
    map(. + {
      expected: (if .name == "manafishrov-rustfs" or .name == "mattermost"
        then "" else "auto" end)
    }) as $policies |
    if any($policies[]; .name == "manafishrov-dns") and
       any($policies[]; .name == "manafishrov-stalwart") and
       all($policies[]; .approval == .expected)
    then "OpenTofu approval policy passed"
    else error("Unexpected OpenTofu approval policy: \($policies)")
    end
  '
