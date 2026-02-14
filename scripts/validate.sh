#!/usr/bin/env bash

# This script validates the Argo CD custom resources and the kustomize overlays using kubeconform.
# This script is meant to be run locally and in CI before the changes
# are merged on the main branch that's synced by Argo CD.

set -o errexit

echo "INFO - Downloading Argo CD OpenAPI schemas"
mkdir -p /tmp/argocd-crd-schemas/master-standalone-strict
curl -sL https://github.com/argoproj/argo-cd/releases/latest/download/install.yaml | \
  grep -A 10000 "kind: CustomResourceDefinition" | \
  yq -e 'select(.kind == "CustomResourceDefinition")' - > /tmp/argocd-crd-schemas/master-standalone-strict/argocd-crds.yaml || true

# Also download Kubernetes and Argo CD Application schemas
if [ ! -f /tmp/argocd-crd-schemas/master-standalone-strict/application.yaml ]; then
  curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/crds/application-crd.yaml -o /tmp/argocd-crd-schemas/master-standalone-strict/application.yaml || true
fi

find . -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating $file"
    yq e 'true' "$file" > /dev/null
done

kubeconform_config=("-strict" "-ignore-missing-schemas" "-schema-location" "default" "-schema-location" "/tmp/argocd-crd-schemas" "-verbose")

echo "INFO - Validating clusters"
find ./clusters -maxdepth 2 -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    kubeconform "${kubeconform_config[@]}" "${file}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
done

# mirror kustomize-controller build options
kustomize_flags=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

echo "INFO - Validating kustomize overlays"
find . -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating kustomization ${file/%$kustomize_config}"
    kustomize build "${file/%$kustomize_config}" "${kustomize_flags[@]}" | \
      kubeconform "${kubeconform_config[@]}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
done