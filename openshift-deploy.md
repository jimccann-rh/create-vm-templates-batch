# Deploying PowerCLI + Twingate CronJob on OpenShift 4.22

## 1. Build and Push the Container Image

```bash
# Build the image
podman build -f Dockerfile.powercli-twingate -t powercli-twingate:latest .

# Tag for your registry
podman tag powercli-twingate:latest quay.io/YOURORG/powercli-twingate:latest

# Login and push
podman login quay.io
podman push quay.io/YOURORG/powercli-twingate:latest
```

### Using the OpenShift Internal Registry

```bash
# Get the registry route
OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

# Login to the internal registry
podman login -u $(oc whoami) -p $(oc whoami -t) $OCP_REGISTRY

# Tag and push
podman tag powercli-twingate:latest $OCP_REGISTRY/powercli-twingate/powercli-twingate:latest
podman push $OCP_REGISTRY/powercli-twingate/powercli-twingate:latest
```

## 2. Create the OpenShift Project

```bash
oc new-project vsphere-infra-helpers
```

Or switch to it if it already exists:

```bash
oc project vsphere-infra-helpers
```

## 3. Create Secrets

Create the secret with your actual credentials:

```bash
oc create secret generic powercli-secrets \
  --from-literal=VCENTER_USER='aicheck@vsphere.local' \
  --from-literal=VCENTER_PASSWORD='your-password-here' \
  --from-literal=TWINGATE_SERVICE_KEY='{
  "version": "1",
  "network": "yournetwork.twingate.com",
  "service_account_id": "your-service-account-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\nyour-key-here\n-----END PRIVATE KEY-----",
  "key_id": "your-key-id",
  "expires_at": "2026-08-12T15:05:01+00:00",
  "login_path": "/api/v4/headless/login"
}'
```

## 4. Create ConfigMap

The defaults in `openshift-cronjob.yaml` match the current environment. To customise, either edit the YAML before applying or create manually:

```bash
oc create configmap powercli-config \
  --from-literal=VCENTER_SERVER='10.93.76.50' \
  --from-literal=VCENTER_DATACENTER='wldn-130-DC' \
  --from-literal=VCENTER_CLUSTER='wldn-130-cl01' \
  --from-literal=VCENTER_DATASTORE='wldn-130-cl01-vsan01' \
  --from-literal=VM_FOLDER='windows-golden-images' \
  --from-literal=CONTENT_LIBRARY='win-images' \
  --from-literal=NETWORK_NAME='VM Network' \
  --from-literal=TEMPLATES_CONFIG='templates.json'
```

## 5. Persistent Storage (PVC)

The `openshift-cronjob.yaml` includes a `PersistentVolumeClaim` (`powercli-templates-data`) that stores `templates.json` so `last_deployed_version` and `last_deployed_date` persist across CronJob runs.

- **First run**: The entrypoint automatically seeds `/data/templates.json` from the built-in config baked into the image.
- **Subsequent runs**: The persisted file is reused, so only changed template versions trigger deployments.

To inspect the persisted file:

```bash
# Start a debug pod with the PVC mounted
oc run pvc-debug --rm -it --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"debug","image":"fedora:latest","command":["bash"],"stdin":true,"tty":true,"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"powercli-templates-data"}}]}}' \
  -- bash

# Inside the debug pod:
cat /data/templates.json
```

To reset the persisted state (forces re-seed from built-in config on next run):

```bash
# Same debug pod approach, then:
rm /data/templates.json
```

## 6. Deploy the CronJob

If you created the secret and configmap manually in steps 3-4, apply only the CronJob and PVC:

```bash
# Extract just the CronJob from the YAML
oc apply -f openshift-cronjob.yaml
```

Or if you want to apply everything from the YAML (secret + configmap + cronjob):

```bash
# First edit openshift-cronjob.yaml to replace the placeholder values in the Secret
oc apply -f openshift-cronjob.yaml
```

Update the image reference in the CronJob to match your registry:

```bash
oc set image cronjob/powercli-twingate \
  powercli-twingate=quay.io/YOURORG/powercli-twingate:latest
```

## 7. Test with a Manual Job Run

```bash
# Trigger a one-off job from the cronjob
oc create job test-run --from=cronjob/powercli-twingate

# Watch the pod start
oc get pods -l job-name=test-run -w

# Follow the logs
oc logs -f job/test-run

# Check job status
oc get job test-run
```

## 8. View CronJob Status

```bash
# List cronjobs
oc get cronjobs

# Describe the cronjob
oc describe cronjob powercli-twingate

# View recent job history
oc get jobs -l app=powercli-twingate

# View logs from the most recent job
oc logs job/$(oc get jobs -l app=powercli-twingate --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
```

## 9. Change the Schedule

The default schedule is `0 6 * * *` (daily at 6:00 AM UTC). To change:

```bash
oc patch cronjob powercli-twingate -p '{"spec":{"schedule":"0 */6 * * *"}}'
```

Common schedules:
- `0 6 * * *` — daily at 6:00 AM UTC
- `0 */6 * * *` — every 6 hours
- `0 6 * * 1-5` — weekdays at 6:00 AM UTC
- `0 6 * * 1` — weekly on Monday at 6:00 AM UTC

## 10. Cleanup

```bash
# Delete the cronjob and all its jobs
oc delete cronjob powercli-twingate

# Delete secrets, configmap, and PVC
oc delete secret powercli-secrets
oc delete configmap powercli-config
oc delete pvc powercli-templates-data

# Or delete everything with the label
oc delete all,secret,configmap,pvc -l app=powercli-twingate
```

## Notes

- **No elevated privileges needed** — Twingate runs in userspace HTTP proxy mode, no `NET_ADMIN` or `/dev/net/tun` required
- **No secrets stored in the image** — all credentials are injected via environment variables from the OpenShift Secret
- **ConcurrencyPolicy: Forbid** — prevents overlapping runs if a job takes longer than the schedule interval
- **activeDeadlineSeconds: 1800** — jobs are killed after 30 minutes to prevent hanging
- **backoffLimit: 1** — retries once on failure then marks the job as failed
- **PVC (`powercli-templates-data`)** — persists `templates.json` across runs so `last_deployed_version` is tracked. First run auto-seeds from the built-in config
