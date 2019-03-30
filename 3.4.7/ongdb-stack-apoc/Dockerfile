FROM graphfoundation/ongdb:3.4.9

ENV APOC_SHA256=9a65175829600182cd4735335447f9842206225588ed274edcdecbbee13f50f9 \
    APOC_JAR=apoc-3.4.0.5-all.jar \
    NEO4J_PLUGINS=/plugins
ARG APOC_URI=https://cdn.graphfoundation.org/apoc/dist/org/neo4j/procedure/apoc/3.4.0.5/apoc-3.4.0.5-all.jar

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

