# Deploying multi-tenant MWS via ArgoCD

This is the GitOps wiring to switch from the classic single-instance TiddlyWiki to
the hardened, multi-tenant, SSO Multi-Wiki Server (`wiki.mode: mws`).

## Prerequisites
1. **Image** — merge the MWS fork's `image-publish` workflow; it pushes
   `ghcr.io/<owner>/tiddlywiki-mws:latest` (and `:sha-<short>`). Pin to a `:sha-*`
   for production.
2. **Secrets** — create the two sealed secrets below in the target namespace.
3. **Object storage** — an S3-compatible bucket for Litestream backups.

## 1. ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tiddlywiki-mws            # a NEW app for side-by-side cutover
spec:
  destination:
    namespace: tiddlywiki-mws
    server: https://kubernetes.default.svc
  source:
    repoURL: https://mibmal.github.io/TiddlyWiki5   # gh-pages Helm repo
    chart: tiddlywiki
    targetRevision: ">=0.1.8"      # a version that ships mws mode + litestream
    helm:
      valuesObject:
        wiki: { mode: mws, dataPath: /data, initOnEmpty: false }
        image: { repository: ghcr.io/mibmal/tiddlywiki-mws, tag: "latest" }
        replicaCount: 1            # SQLite single-writer — never scale
        strategy: { type: Recreate }
        persistence: { enabled: true, size: 10Gi }
        extraEnv:
          - { name: MWS_DATA_DIR, value: /data }
          - { name: MWS_SSO_ENABLED, value: "true" }
          - { name: MWS_SSO_EMAIL_HEADER, value: x-auth-request-email }
        oauth2Proxy:
          enabled: true
          provider: oidc
          oidcIssuerUrl: "https://<your-idp>/"
          existingSecret: "mws-oauth2"
        litestream:
          enabled: true
          existingSecret: "mws-litestream"
          replica: { type: s3, bucket: "<your-bucket>", path: "mws" }
        gitSync: { enabled: false }
        snapshot: { enabled: false }
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

## 2. Secrets (SealedSecret)

Create the plaintext Secrets, seal them with `kubeseal`, and commit the sealed
output to your Argo repo. Do **not** commit the plaintext.

**oauth2-proxy** (`mws-oauth2`):
```sh
kubectl create secret generic mws-oauth2 -n tiddlywiki-mws \
  --from-literal=client-id=YOUR_ID \
  --from-literal=client-secret=YOUR_SECRET \
  --from-literal=cookie-secret=$(openssl rand -base64 32) \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > mws-oauth2.sealed.yaml
```

**Litestream** (`mws-litestream`) — S3-compatible credentials:
```sh
kubectl create secret generic mws-litestream -n tiddlywiki-mws \
  --from-literal=access-key-id=YOUR_KEY \
  --from-literal=secret-access-key=YOUR_SECRET \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > mws-litestream.sealed.yaml
```

## 3. Cutover (don't flip in place)
SQLite means no in-place migration from the classic flat-file wiki:
1. Deploy this as a **new** Application on a new host (`mws.<domain>`).
2. Validate SSO login → each user gets their own wiki; test sharing/teams.
3. Migrate existing content into a bag if needed.
4. Switch ingress/DNS to the new app; retire the classic one.

## Notes
- **Backup/restore:** Litestream streams the SQLite DB to object storage and, on a
  fresh pod, restores it automatically (init container) before the server starts.
- **Single-writer:** keep `replicaCount: 1` + `strategy: Recreate`. Do not enable
  the HPA for mws mode.
- **oauth2-proxy** must forward `X-Auth-Request-Email` (`--set-xauthrequest=true`,
  set by the chart) — that header is what MWS auto-provisions each user from.
