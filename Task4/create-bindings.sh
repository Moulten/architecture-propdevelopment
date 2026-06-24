#!/usr/bin/env bash
# Creates Kubernetes RoleBindings and ClusterRoleBindings for PropDevelopment.
# Binds users/groups to the roles created by create-roles.sh.
# Run as cluster-admin AFTER create-roles.sh.

set -euo pipefail

echo "PropDevelopment Kubernetes RBAC — Binding creation"
echo "==================================================="
echo ""

# ─── developers-sales → Role/developer-sales in namespace: sales ─────────────

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developers-sales-binding
  namespace: sales
subjects:
  - kind: Group
    name: developers-sales
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer-sales
  apiGroup: rbac.authorization.k8s.io
EOF
echo "RoleBinding 'developers-sales-binding' → Role/developer-sales in 'sales'"

# ─── developers-jku → Role/developer-jku in namespace: jku ──────────────────

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developers-jku-binding
  namespace: jku
subjects:
  - kind: Group
    name: developers-jku
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer-jku
  apiGroup: rbac.authorization.k8s.io
EOF
echo "RoleBinding 'developers-jku-binding' → Role/developer-jku in 'jku'"

# ─── data-engineers → Role/data-engineer in namespace: data ─────────────────

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: data-engineers-binding
  namespace: data
subjects:
  - kind: Group
    name: data-engineers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: data-engineer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "RoleBinding 'data-engineers-binding' → Role/data-engineer in 'data'"

# ─── ops-engineers → ClusterRole/ops-engineer in namespaces: sales, jku, data, infra ──

for ns in sales jku data infra; do
  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ops-engineers-binding
  namespace: ${ns}
subjects:
  - kind: Group
    name: ops-engineers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: ops-engineer
  apiGroup: rbac.authorization.k8s.io
EOF
  echo "RoleBinding 'ops-engineers-binding' → ClusterRole/ops-engineer in '${ns}'"
done

# ops in monitoring — read only (reuse security-auditor ClusterRole for monitoring ns)
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ops-engineers-monitoring-binding
  namespace: monitoring
subjects:
  - kind: Group
    name: ops-engineers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: security-auditor
  apiGroup: rbac.authorization.k8s.io
EOF
echo "RoleBinding 'ops-engineers-monitoring-binding' → ClusterRole/security-auditor in 'monitoring' (read-only)"

# ─── security-auditors → ClusterRole/security-auditor (cluster-wide) ─────────

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: security-auditors-binding
subjects:
  - kind: Group
    name: security-auditors
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: security-auditor
  apiGroup: rbac.authorization.k8s.io
EOF
echo "ClusterRoleBinding 'security-auditors-binding' → ClusterRole/security-auditor (cluster-wide)"

# ─── cluster-admins → ClusterRole/cluster-admin (built-in) ───────────────────

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: propdevelopment-cluster-admins-binding
subjects:
  - kind: Group
    name: cluster-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
echo "ClusterRoleBinding 'propdevelopment-cluster-admins-binding' → ClusterRole/cluster-admin (built-in)"

# ─── grafana-sa ServiceAccount → ClusterRole/monitoring-reader ───────────────

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: grafana-sa-binding
subjects:
  - kind: ServiceAccount
    name: grafana-sa
    namespace: monitoring
roleRef:
  kind: ClusterRole
  name: monitoring-reader
  apiGroup: rbac.authorization.k8s.io
EOF
echo "ClusterRoleBinding 'grafana-sa-binding' → ClusterRole/monitoring-reader (cluster-wide)"

# ─── Verify bindings ─────────────────────────────────────────────────────────

echo ""
echo "=== Verification ==="

echo ""
echo "RoleBindings in 'sales':"
kubectl get rolebindings -n sales

echo ""
echo "RoleBindings in 'jku':"
kubectl get rolebindings -n jku

echo ""
echo "RoleBindings in 'data':"
kubectl get rolebindings -n data

echo ""
echo "ClusterRoleBindings (PropDevelopment):"
kubectl get clusterrolebindings | grep -E "security-auditors|cluster-admins|grafana-sa"

echo ""
echo "All bindings created successfully."
echo ""
echo "To verify a specific user's access, use:"
echo "  kubectl auth can-i <verb> <resource> --as=<username> -n <namespace>"
echo "Example:"
echo "  kubectl auth can-i get secrets --as=dev-ivanov -n sales"
echo "  kubectl auth can-i delete pods --as=dev-ivanov -n sales"
