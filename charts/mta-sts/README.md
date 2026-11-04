# mta-sts

![Version: 0.1.0](https://img.shields.io/badge/version-0.1.0-informational?logo=helm)
![AppVersion: nginx 1.30.6](https://img.shields.io/badge/nginx-1.30.6-009639?logo=nginx&logoColor=white)
![RFC 8461](https://img.shields.io/badge/RFC-8461-lightgrey)
![RFC 8460](https://img.shields.io/badge/RFC-8460-lightgrey)

Serves [MTA-STS](https://www.rfc-editor.org/rfc/rfc8461) policies for one or many domains from a hardened nginx, and publishes the matching DNS records through [external-dns](https://github.com/kubernetes-sigs/external-dns) or prints them for you.

Maintained by [DMARC Examiner](https://dmarc-examiner.com).

## Features

- **Multi-domain.** One release serves `mta-sts.<domain>` for every domain you list, each with its own policy.
- **Automatic policy id.** The `id` of the `_mta-sts` record is derived from the policy content. Change the policy and the id changes; leave it and the id stays the same.
- **DNS as code.** Optional `DNSEndpoint` with the `_mta-sts` and `_smtp._tls` (TLS-RPT) TXT records.
- **TLS out of the box.** Ingress annotations for cert-manager `ClusterIssuer` or `Issuer`.
- **Hardened.** Non-root, read-only root filesystem, all capabilities dropped, no service account token, seccomp `RuntimeDefault`.
- **Validated.** `values.schema.json` rejects invalid modes, `max_age` out of range, malformed MX hosts and TLS-RPT URIs before anything reaches the cluster.
- **Self-testing.** `helm test` fetches every policy through the Service and checks that unknown hosts get a 404.

## Prerequisites

- Kubernetes 1.25+ and Helm 3.8+.
- An Ingress controller reachable from the internet on port 443.
- A publicly trusted certificate for every `mta-sts.<domain>`. cert-manager with Let's Encrypt works.
- `mta-sts.<domain>` must resolve to your Ingress. A wildcard record is not enough if the Ingress has no rule for that host; this chart creates the rule.
- Optional: external-dns with the `crd` source enabled, to manage the TXT records.

## Install

```bash
helm install mta-sts oci://ghcr.io/dmarc-examiner/charts/mta-sts \
  --namespace mta-sts --create-namespace -f values.yaml
```

### Single domain on Google Workspace

```yaml
domains:
  - name: example.com

policy:
  mode: testing
  mx:
    - aspmx.l.google.com
    - "*.aspmx.l.google.com"

tlsRpt:
  rua:
    - mailto:tls-reports@{domain}

ingress:
  className: nginx
  certManager:
    clusterIssuer: letsencrypt
```

### Several domains with different policies

```yaml
domains:
  - name: example.com
  - name: example.org
    mode: enforce
    mx:
      - mx1.example.org
      - mx2.example.org
  - name: legacy.example.net
    mode: none

policy:
  mode: testing
  mx:
    - mx.example.com

tlsRpt:
  rua:
    - mailto:tls-reports@{domain}
```

### DNS records through external-dns

```yaml
externalDns:
  enabled: true
  labels:
    dns: public
```

The chart creates one `DNSEndpoint` with these records per domain:

| Name | Type | Value |
|---|---|---|
| `_mta-sts.example.com` | TXT | `v=STSv1; id=<20 hex chars>` |
| `_smtp._tls.example.com` | TXT | `v=TLSRPTv1; rua=mailto:tls-reports@example.com` |

external-dns needs `--source=crd` and, if you set labels, a matching `--label-filter`. The `A`/`CNAME` record for `mta-sts.<domain>` comes from the Ingress source as usual.

Without external-dns, `helm install` and `helm upgrade` print the exact records to create in the release notes.

## Policy id

RFC 8461 requires a new `id` every time the policy changes, or senders keep the cached copy until `max_age` expires. This chart sets:

```
id = first 20 hex characters of sha256(policy file)
```

The id is stable across upgrades that do not touch the policy, and changes on its own when they do. With external-dns, the TXT record follows. Without it, copy the new value from the release notes.

## Rollout and withdrawal

| Step | Values | Why |
|---|---|---|
| Start | `mode: testing` + `tlsRpt.rua` | Senders report failures but still deliver. |
| Enforce | `mode: enforce` after 1-2 weeks of clean reports | Senders refuse insecure or unverified delivery. |
| Change MX | Add the new hosts to `mx` before switching DNS | Senders cache the old list for `maxAge` seconds. |
| Withdraw | `mode: none`, keep it served for `maxAge`, then uninstall | Removing the policy outright leaves senders enforcing a cached copy. |

## Values

| Key | Type | Default | Description |
|---|---|---|---|
| `domains` | list | `[]` | Domains to serve. Each item takes `name` and can override `mode`, `maxAge`, `mx` and `tlsRptRua`. Required. |
| `policy.mode` | string | `testing` | `testing`, `enforce` or `none`. |
| `policy.maxAge` | int | `604800` | Seconds that senders cache the policy. Maximum `31557600`. |
| `policy.mx` | list | `[]` | Allowed MX hosts. Wildcards like `*.example.com` match one label. Required unless `mode: none`. |
| `tlsRpt.rua` | list | `[]` | TLS-RPT destinations, `mailto:` or `https://`. `{domain}` is replaced by each domain. |
| `ingress.enabled` | bool | `true` | Create the Ingress. |
| `ingress.className` | string | `""` | IngressClass name. Empty uses the cluster default. |
| `ingress.annotations` | object | `{}` | Extra Ingress annotations. |
| `ingress.certManager.clusterIssuer` | string | `""` | Adds `cert-manager.io/cluster-issuer`. |
| `ingress.certManager.issuer` | string | `""` | Adds `cert-manager.io/issuer`. |
| `ingress.tls.enabled` | bool | `true` | Terminate TLS on the Ingress. |
| `ingress.tls.secretName` | string | `""` | TLS Secret. Defaults to `<fullname>-tls`. |
| `externalDns.enabled` | bool | `false` | Create a `DNSEndpoint` with the TXT records. |
| `externalDns.recordTTL` | int | `300` | TTL of the TXT records. |
| `externalDns.labels` | object | `{}` | Extra labels for external-dns `--label-filter`. |
| `replicaCount` | int | `2` | nginx replicas. |
| `image.repository` | string | `docker.io/nginxinc/nginx-unprivileged` | Image repository. |
| `image.tag` | string | `1.30.6-alpine` | Image tag. |
| `image.digest` | string | `""` | Pins the image by digest. Takes precedence over `tag`. |
| `image.pullPolicy` | string | `IfNotPresent` | Image pull policy. |
| `imagePullSecrets` | list | `[]` | Pull secrets. |
| `service.type` | string | `ClusterIP` | Service type. |
| `service.port` | int | `80` | Service port. |
| `podAnnotations` | object | `{}` | Extra pod annotations. |
| `podLabels` | object | `{}` | Extra pod labels. |
| `podSecurityContext` | object | non-root `101`, seccomp `RuntimeDefault` | Pod security context. |
| `securityContext` | object | read-only, no privilege escalation, drop `ALL` | Container security context. |
| `resources` | object | `10m` / `16Mi` requests, `64Mi` limit | Container resources. |
| `podDisruptionBudget.enabled` | bool | `true` | Create a PDB when `replicaCount > 1`. |
| `podDisruptionBudget.minAvailable` | int | `1` | PDB `minAvailable`. |
| `nodeSelector` | object | `{}` | Node selector. |
| `tolerations` | list | `[]` | Tolerations. |
| `affinity` | object | `{}` | Affinity rules. |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints. |
| `priorityClassName` | string | `""` | Priority class. |
| `tests.image.repository` | string | `docker.io/curlimages/curl` | Image for `helm test`. |
| `tests.image.tag` | string | `8.23.0` | Tag for `helm test`. |

## Verify

```bash
helm test mta-sts -n mta-sts
curl -s https://mta-sts.example.com/.well-known/mta-sts.txt
dig +short TXT _mta-sts.example.com
```

The free [email compliance checker](https://dmarc-examiner.com/tools/email-compliance) validates the TXT record, the policy file and its certificate in one go.
