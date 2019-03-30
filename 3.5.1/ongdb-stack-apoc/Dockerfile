FROM graphfoundation/ongdb:3.5.1

ENV APOC_SHA256=03fb1dbc5e6c1e05b7ca382a215c07955e8bafe1123a09c5633bead368c4894e \
    APOC_JAR=apoc-3.5.0.2-all.jar \
    NEO4J_PLUGINS=/plugins
ARG APOC_URI=https://cdn.graphfoundation.org/apoc/dist/org/neo4j/procedure/apoc/3.5.0.2/apoc-3.5.0.2-all.jar

RUN apk add --no-cache --quiet \
    bash \
    curl \
    tini \
    su-exec \
    && curl --fail --silent --show-error --location --remote-name ${APOC_URI} \
    && echo "${APOC_SHA256}  ${APOC_JAR}" | sha256sum -csw - \
    && mv ${APOC_JAR} "${NEO4J_PLUGINS}" \
    && chown -R neo4j:neo4j "${NEO4J_PLUGINS}" \
    && chmod -R 777 "${NEO4J_PLUGINS}" \
    && apk del curl

