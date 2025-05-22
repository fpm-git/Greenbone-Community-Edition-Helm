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

### `securityContext` and `podSecurityContext`

Just set to `0` to get things working asap. I was encountering PV permissions issues and just wanted to get rid of them.

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
