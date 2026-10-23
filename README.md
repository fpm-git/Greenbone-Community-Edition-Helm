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

`gpg-data` copies the Greenbone feed key into `/etc/openvas/gnupg` (`GNUPGHOME`) so ospd-openvas and openvasd can verify the Notus advisories. The scanner reaches openvasd on `http://127.0.0.1:81/notus` (`notus_url`). openvasd has no authentication, so it only listens on localhost (`openvasd.listening`) and is not part of the Service.

Extra `openvas.conf` settings can be added with `openvasConf`.

### Feed updates

Feed data is copied in by init containers when the pod starts. Set `feedUpdate.enabled: true` to add a CronJob that does a `rollout restart` of the deployment on `feedUpdate.schedule`. Running scans are interrupted, so pick a time when no scans run.

### gvm-tools

The idle `gvm-tools` debug container is disabled by default. Enable it with `gvmTools.enabled: true`.

### Resources

`ospdOpenvas.resources` sets ospd-openvas resources. Other containers can be set by container name under `resources`, e.g. `resources.gvmd`.

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
