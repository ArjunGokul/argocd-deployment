#!/bin/bash

set -e
set -x

export ArgoCDUrl=$1
export Password=$2
export ClearModule=$3
export GitRepo=$4
export Namespace=$5
#export username=$6
#export PAT=$7

retry() {
  local n=1
  local max=5
  local delay=5
  while true; do
    export HOME=/tmp
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo "Command failed. Attempt $n/$max:"
        sleep $delay;
      else
        echo "The command has failed after $n attempts."
        return 1
      fi
    }
  done
}

# Log in to ArgoCD
retry argocd login "$ArgoCDUrl" --username admin --password "$Password" --insecure
#retry argocd repo add "https://PrimeFocusTechnologies@dev.azure.com/PrimeFocusTechnologies/DEPLOYMENTS/_git/$GitRepo" --username "$username" --password "$PAT" --upsert

# Check if the module already exists in ArgoCD
ModuleExists=$(retry argocd app list | awk '{print $1}' | grep -iw "${ClearModule}" || true)
if [ -z "$ModuleExists" ]; then
  echo "$ClearModule doesn't exist, hence onboarding to ArgoCD"
  retry argocd app create "$ClearModule" \
    --repo "$GitRepo" \
    --path "./$ClearModule" \
    --dest-server "https://kubernetes.default.svc" \
    --dest-namespace "$Namespace" \
    --project "default" \
    --directory-recurse 
  
  if [ "$Namespace" == "usdcprod" ]; then
    retry argocd app set "$ClearModule" --sync-policy manual
  else
    retry argocd app set "$ClearModule" --sync-policy automated --sync-option RespectIgnoreDifferences=true --sync-option ApplyOutOfSyncOnly=true
  fi
else
  echo "$ClearModule exists, hence we will sync the latest changes"
  retry argocd app sync "$ClearModule" --force --async > /dev/null 2>&1
  retry argocd app set "$ClearModule" --sync-policy automated --sync-option ApplyOutOfSyncOnly=true
fi
