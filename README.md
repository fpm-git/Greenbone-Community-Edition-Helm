 # Helm chart for Greenbone Community Edition

 This chart was developed to get working as fast as possible, there are things that can be improved on.

 ## A few things to note

 ### Docker-compose
 This helm chart is based off of this docker-compose file: https://greenbone.github.io/docs/latest/22.4/container/index.html#docker-compose-file. At least originally. File at location has been updated. So from now on keeping a copy of the docker composed used for last update here to better track changes.

 ### PG-GVM

 Adding a PV to `/var/lib/postgresql` breaks the container. So I setup an init-container, which uses the configmap script at templates/init-configmap.yaml to initilize the db for the first time.
```
        - name: pg-init
          image: {{ .Values.psgvm.image.repository }}:{{ .Values.psgvm.image.tag }}
          command: ["/bin/sh", "-c", "/init-scripts/init-postgres.sh"]
          volumeMounts:
            - name: psql-storage
              mountPath: /mnt/postgresql
            - name: init-scripts
              mountPath: /init-scripts
```

### Security context

The Greenbone images start as root and drop privileges themselves (`gosu`), and postStart hooks `chown` the data dirs, so the pod runs as uid 0 (`podSecurityContext`). Hardening that is applied:

* `containerSecurityContext` on every container: `privileged: false`, `allowPrivilegeEscalation: false`, drops `NET_RAW`, pod-level seccomp `RuntimeDefault`.
* `ospd-openvas` keeps `NET_ADMIN`/`NET_RAW` (host discovery, port scans and NASL checks need raw sockets) and runs with seccomp `Unconfined` like upstream compose. Both are configurable via `ospdOpenvas.capabilities` / `ospdOpenvas.seccompProfile`.
* The `openvas` log container runs as `nobody` with a read-only root filesystem.
* The pod does not mount a service account token.

The old `securityContext` value was never used and has been removed. Do not set `fsGroup`: it recursively changes group permissions on the PostgreSQL data dir, which PostgreSQL refuses to start with.

### Notus (local security checks)

`gpg-data` copies the Greenbone feed key into `/etc/openvas/gnupg` (`GNUPGHOME`) so ospd-openvas and openvasd can verify the Notus advisories. The scanner reaches openvasd on `http://127.0.0.1:81` (`openvasd_server`; ospd-openvas needs this key rather than `notus_url` to skip its MQTT client). openvasd has no authentication, so it only listens on localhost (`openvasd.listening`) and is not part of the Service.

Extra `openvas.conf` settings can be added with `openvasConf`.

### Feed updates

Feed data is copied in by init containers when the pod starts. Set `feedUpdate.enabled: true` to add a CronJob that does a `rollout restart` of the deployment on `feedUpdate.schedule`. Running scans are interrupted, so pick a time when no scans run.

### gvm-tools

The idle `gvm-tools` debug container is disabled by default. Enable it with `gvmTools.enabled: true`.

### Resources

`ospdOpenvas.resources` sets ospd-openvas resources. Other containers can be set by container name under `resources`, e.g. `resources.gvmd`.

### Images

Application images (`images.gvmd`, `images.gsa`, `images.openvasScanner`, `images.gvmTools`, `psgvm.image`) default to `ghcr.io/greenbone`. `ospd.image`, `redis.image` and the feed data images (`feedImages`) come from `registry.community.greenbone.net`, the only place they are published. With the default `stable` tags and `imagePullPolicy: Always`, each pod restart picks up the latest Greenbone release. To control upgrades, pin a version tag such as `images.gvmd.tag: 26.42.0`. Pin `psgvm.image.tag`, because its PostgreSQL major must match the data directory.

### Start and shutdown order

With `nativeSidecars: true` (Kubernetes >= 1.29), pg-gvm and redis-server run as native sidecars. They start, and pass their startup probes, before gvmd and ospd-openvas, and Kubernetes stops them only after those have exited. Without this, PostgreSQL can stop underneath gvmd on a restart, and gvmd then marks running tasks as Interrupted. Set `nativeSidecars: false` on older clusters. `terminationGracePeriodSeconds` (default 120) bounds the whole shutdown.

The gvmd container preserves the upstream image entrypoint and initialization script. A `preStop` hook sends SIGTERM directly to the daemon identified by `/run/gvmd/gvmd.pid` and waits for it to exit before Kubernetes terminates the container. This avoids relying on the upstream shell wrapper to forward signals and keeps PostgreSQL available during gvmd cleanup. The hook shares the pod's termination grace period; running scans are still interrupted by a pod restart.

### Probes

`probes` holds probes by container name. By default there are startup probes for pg-gvm and redis-server and readiness probes for gvmd and gsa. There are deliberately no liveness probes, because a restart kills running scans.

The PostgreSQL startup probe checks the local Unix socket using `POSTGRES_USER` and `POSTGRES_DB` from the pg-gvm container environment (both default to `gvmd`, matching the image). It does not connect to external PostgreSQL clusters or require additional credentials. `pg_isready` checks server availability, not successful authentication or schema readiness.

### Redis

Redis runs in the pod, listens only on a unix socket in a dedicated emptyDir shared with ospd-openvas, and keeps no data on disk. Its config comes from the `<fullname>-redis` ConfigMap, with `redis.extraConfig` for extra directives. It runs as uid 999 with a read-only root filesystem and no capabilities. To use the official image, which gets Redis security fixes sooner, set:

```yaml
redis:
  image:
    repository: docker.io/library/redis
    tag: 8-trixie   # follows Redis 8.x; use 8.6-trixie for patch-only updates
```

An external Redis/Dragonfly is not supported. The scan knowledge base holds scan credentials, and Greenbone's TCP Redis support has no authentication.

### Upgrading to 1.2.0

pg-gvm and redis-server move from `containers` to `initContainers` (native sidecars). If Argo CD uses server-side diff or server-side apply, the comparison fails with `Duplicate value: "redis-server"` because the old entries are still owned by other field managers. For this one sync, set `argocd.argoproj.io/compare-options: ServerSideDiff=false` on the Application and sync without server-side apply, or delete the Deployment and sync (the PVCs are kept).

### Ingress

To have GSA working correctly, you can not have a proxy: https://forum.greenbone.net/t/stuck-on-login-loop-on-the-login-page/16687/4

So be sure to setup TLS with your own PKI, and then either have it internal only, or in a place like cloudflare DNS only.

### Pod structure

All containers run on one pod. I am sure it can be refacted somewhat, but that depends on the PV dependencies and if you want to start support RWX PVs

### PV setup

I have setup four pv's which get shared across the different containers in the pod. I had issues with one PV due to pathing issues.

For example, the following will not work
```
- name: gvmd
          image: registry.community.greenbone.net/community/gvmd:stable
          volumeMounts:
            - name: shared-storage
              mountPath: /var/lib/gvm
              subPath: gvmd-data
            - name: shared-storage
              mountPath: /var/lib/gvm/scap-data
              subPath: scap-data
            - name: shared-storage
              mountPath: /var/lib/gvm/cert-data
              subPath: cert-data
            - name: shared-storage
              mountPath: /var/lib/gvm/data-objects/gvmd
              subPath: data-objects
```
