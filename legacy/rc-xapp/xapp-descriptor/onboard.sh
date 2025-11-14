export NODE_PORT=$(kubectl get --namespace ricinfra -o jsonpath="{.spec.ports[0].nodePort}" services r4-chartmuseum-chartmuseum)
export NODE_IP=$(kubectl get nodes --namespace ricinfra -o jsonpath="{.items[0].status.addresses[0].address}")
export CHART_REPO_URL=http://$NODE_IP:$NODE_PORT/charts
dms_cli uninstall rc ricxapp
dms_cli onboard config.json schema.json
dms_cli install rc 1.0.0 ricxapp
