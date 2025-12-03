#!/bin/bash

# Configuration
REPO_DIR="$HOME/gitops-interview-mockup"
SSH_KEY="$HOME/.ssh/id_ed25519"
REPO_URL="ssh://git@github.com/taikun-cloud/gitops-interview-mockup.git"

# Ensure we are in the home directory
cd $HOME

# 1. Configure Git Identity (Fixes the error you saw)
cd $REPO_DIR
git config --global user.email "interview-bot@taikun.cloud"
git config --global user.name "Interview Bot"

# 2. Reset Repo to Clean Slate
echo ">>> Cleaning repository..."
git rm -rf .
git clean -fdX
git pull origin main

# 3. Create the File Structure
echo ">>> creating manifest structure..."
mkdir -p clusters/dev

# 4. Create the Dummy CRD
cat <<EOF > clusters/dev/crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: brokenwidgets.interview.taikun.cloud
spec:
  group: interview.taikun.cloud
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                message:
                  type: string
  scope: Namespaced
  names:
    plural: brokenwidgets
    singular: brokenwidget
    kind: BrokenWidget
    shortNames:
    - bw
EOF

# 5. Create the CR with a TRAP (Finalizer)
# The finalizer ensures this resource cannot be deleted easily
cat <<EOF > clusters/dev/cr.yaml
apiVersion: interview.taikun.cloud/v1
kind: BrokenWidget
metadata:
  name: stuck-resource
  namespace: default
  finalizers:
    - interview.taikun.cloud/trap # <--- This causes the stickiness
spec:
  message: "I am going to break your flux sync"
EOF

# 6. Generate Flux Manifests
# We use 'flux create' with export to generate YAMLs without needing a GitHub Token
echo ">>> Generating Flux manifests..."
flux create source git interview-git \
  --url=$REPO_URL \
  --branch=main \
  --private-key-file=$SSH_KEY \
  --interval=1m \
  --export > clusters/dev/flux-source.yaml

flux create kustomization interview-kustomization \
  --source=interview-git \
  --path="./clusters/dev" \
  --prune=true \
  --interval=1m \
  --export > clusters/dev/flux-kustomization.yaml

# 7. Push Initial State (Healthy)
echo ">>> Pushing initial healthy state..."
git add .
git commit -m "Initialize GitOps Structure with CRD and CR"
git push origin main

# 8. Apply Flux Manifests to Cluster to kickstart things
# We apply this manually once to bootstrap the connection
kubectl apply -f clusters/dev/flux-source.yaml
kubectl apply -f clusters/dev/flux-kustomization.yaml

echo ">>> Waiting for initial sync (30s)..."
sleep 30

# 9. THE BREAKING CHANGE
echo ">>> DEPLOYING THE BROKEN STATE..."
# We delete the CRD file. Flux will try to prune it.
# K8s will hang deleting the CRD because the CR exists.
git rm clusters/dev/crd.yaml
git commit -m "Remove CRD definition (Chaos)"
git push origin main

echo ">>> Triggering reconciliation..."
flux reconcile source git interview-git
flux reconcile kustomization interview-kustomization

echo ""
echo "========================================================"
echo "ENVIRONMENT READY FOR CANDIDATE"
echo "========================================================"
echo "Scenario: "
echo "1. A CRD and a Resource were deployed."
echo "2. Someone deleted the CRD file from Git."
echo "3. Flux is now failing because it cannot prune the CRD."
echo "   (The CRD is stuck in Terminating because the Resource has a finalizer)"
echo ""
echo "Candidate Goal: They need to find the stuck resource, patch the finalizer,"
echo "cleanup the stuck CRD, and get Flux green again."
echo "========================================================"
