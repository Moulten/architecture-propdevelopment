#!/usr/bin/env bash
# Creates Kubernetes users (X.509 certificates) for PropDevelopment RBAC.
# Each user gets a CSR signed by the cluster CA.
# Run as cluster-admin.

set -euo pipefail

CLUSTER_NAME="propdevelopment"
EXPIRY_SECONDS=$((365 * 24 * 3600))  # 1 year

USERS=(
  "dev-ivanov"
  "dev-petrov"
  "dev-sidorov"
  "dev-kuznetsov"
  "ops-volkov"
  "data-morozov"
  "sec-lebedev"
  "admin-sokolov"
)

# Groups map: user → kubernetes group (used in RoleBinding subjects)
declare -A USER_GROUPS=(
  ["dev-ivanov"]="developers-sales"
  ["dev-petrov"]="developers-sales"
  ["dev-sidorov"]="developers-jku"
  ["dev-kuznetsov"]="developers-jku"
  ["ops-volkov"]="ops-engineers"
  ["data-morozov"]="data-engineers"
  ["sec-lebedev"]="security-auditors"
  ["admin-sokolov"]="cluster-admins"
)

mkdir -p certs

create_user() {
  local username="$1"
  local group="${USER_GROUPS[$username]}"
  local keyfile="certs/${username}.key"
  local csrfile="certs/${username}.csr"
  local certfile="certs/${username}.crt"
  local csr_k8s_name="${username}-csr"

  echo "==> Creating user: ${username} (group: ${group})"

  # Generate private key
  openssl genrsa -out "${keyfile}" 4096 2>/dev/null
  echo "    Private key: ${keyfile}"

  # Generate CSR with CN=username, O=group
  openssl req -new -key "${keyfile}" \
    -out "${csrfile}" \
    -subj "/CN=${username}/O=${group}" 2>/dev/null
  echo "    CSR: ${csrfile}"

  # Delete existing CSR if present
  kubectl delete certificatesigningrequest "${csr_k8s_name}" --ignore-not-found=true

  # Submit CSR to Kubernetes
  local csr_b64
  csr_b64=$(base64 -w 0 < "${csrfile}")

  kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${csr_k8s_name}
spec:
  request: ${csr_b64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: ${EXPIRY_SECONDS}
  usages:
    - client auth
EOF

  # Approve the CSR
  kubectl certificate approve "${csr_k8s_name}"
  echo "    CSR approved"

  # Wait for certificate to be issued
  local attempts=0
  while [[ $attempts -lt 10 ]]; do
    local cert
    cert=$(kubectl get csr "${csr_k8s_name}" -o jsonpath='{.status.certificate}' 2>/dev/null || true)
    if [[ -n "$cert" ]]; then
      echo "${cert}" | base64 -d > "${certfile}"
      echo "    Certificate saved: ${certfile}"
      break
    fi
    sleep 2
    attempts=$((attempts + 1))
  done

  if [[ ! -f "${certfile}" ]]; then
    echo "    ERROR: Certificate not issued for ${username}" >&2
    exit 1
  fi

  # Generate kubeconfig for the user
  local kubeconfig_file="certs/${username}.kubeconfig"
  local server
  server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  local ca_data
  ca_data=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

  kubectl config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${kubeconfig_file}" \
    --server="${server}" \
    --certificate-authority=<(echo "${ca_data}" | base64 -d) \
    --embed-certs=true

  kubectl config set-credentials "${username}" \
    --kubeconfig="${kubeconfig_file}" \
    --client-certificate="${certfile}" \
    --client-key="${keyfile}" \
    --embed-certs=true

  kubectl config set-context "${username}@${CLUSTER_NAME}" \
    --kubeconfig="${kubeconfig_file}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${username}"

  kubectl config use-context "${username}@${CLUSTER_NAME}" \
    --kubeconfig="${kubeconfig_file}"

  echo "    Kubeconfig: ${kubeconfig_file}"
  echo ""
}

# Create Prometheus/Grafana ServiceAccount separately (not X.509)
create_monitoring_serviceaccount() {
  echo "==> Creating ServiceAccount: grafana-sa (namespace: monitoring)"

  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

  kubectl create serviceaccount grafana-sa \
    --namespace monitoring \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "    ServiceAccount 'grafana-sa' created in namespace 'monitoring'"
  echo ""
}

echo "PropDevelopment Kubernetes RBAC — User creation"
echo "================================================"
echo ""

for user in "${USERS[@]}"; do
  create_user "$user"
done

create_monitoring_serviceaccount

echo "Done. Certificates and kubeconfigs saved to ./certs/"
echo "Distribute kubeconfig files to users via secure channel (not email)."
