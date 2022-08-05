FROM openjdk:8-jre-slim

ENV ONGDB_SHA256=e03a0921f6b1d5a3f5fafa688adf7c5734997499021cb06db4fb57cb74ab3e68 \
    ONGDB_TARBALL=ongdb-community-1.0.4-unix.tar.gz \
    ONGDB_EDITION=community \
    ONGDB_HOME="/var/lib/ongdb" \
    TINI_VERSION="v0.19.0" \
    TINI_SHA256="93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c"
ARG ONGDB_URI=https://cdn.graphfoundation.org/ongdb/dist/ongdb-community-1.0.4-unix.tar.gz

RUN addgroup --system ongdb && adduser --system --no-create-home --home "${ONGDB_HOME}" --ingroup ongdb ongdb

COPY ./local-package/* /tmp/

RUN apt update \
     && apt install -y curl wget gosu jq \
     && curl -L --fail --silent --show-error "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini" > /sbin/tini \
     && echo "${TINI_SHA256}  /sbin/tini" | sha256sum -c --strict --quiet \
     && chmod +x /sbin/tini \
     && curl --fail --silent --show-error --location --remote-name ${ONGDB_URI} \
     && echo "${ONGDB_SHA256}  ${ONGDB_TARBALL}" | sha256sum -c --strict --quiet \
     && tar --extract --file ${ONGDB_TARBALL} --directory /var/lib \
     && mv /var/lib/ongdb-* "${ONGDB_HOME}" \
     && rm ${ONGDB_TARBALL} \
     && mv "${ONGDB_HOME}"/data /data \
     && mv "${ONGDB_HOME}"/logs /logs \
     && chown -R ongdb:ongdb /data \
     && chmod -R 777 /data \
     && chown -R ongdb:ongdb /logs \
     && chmod -R 777 /logs \
     && chown -R ongdb:ongdb "${ONGDB_HOME}" \
     && chmod -R 777 "${ONGDB_HOME}" \
     && ln -s /data "${ONGDB_HOME}"/data \
     && ln -s /logs "${ONGDB_HOME}"/logs \
     && mv /tmp/ongdb-plugins.json /ongdb-plugins.json \
     && rm -rf /tmp/* \
     && rm -rf /var/lib/apt/lists/* \
     && apt-get -y purge --auto-remove curl

ENV PATH "${ONGDB_HOME}"/bin:$PATH

WORKDIR "${ONGDB_HOME}"

VOLUME /data /logs

COPY docker-entrypoint.sh /docker-entrypoint.sh

EXPOSE 7474 7473 7687

ENTRYPOINT ["/sbin/tini", "-g", "--", "/docker-entrypoint.sh"]
CMD ["ongdb"]
