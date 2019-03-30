FROM graphfoundation/ongdb:3.5.3

ENV APOC_SHA256=03fb1dbc5e6c1e05b7ca382a215c07955e8bafe1123a09c5633bead368c4894e \
    APOC_JAR=apoc-3.5.0.2-all.jar \
    ALGO_SHA256=03fb1dbc5e6c1e05b7ca382a215c07955e8bafe1123a09c5633bead368c4894e \
    ALGO_JAR=apoc-3.5.0.2-all.jar \
    GRAPHQL_SHA256=03fb1dbc5e6c1e05b7ca382a215c07955e8bafe1123a09c5633bead368c4894e \
    GRAPHQL_JAR=apoc-3.5.0.2-all.jar \
    NEO4J_PLUGINS=/plugins
ARG APOC_URI=https://cdn.graphfoundation.org/apoc/dist/org/neo4j/procedure/apoc/3.5.0.2/apoc-3.5.0.2-all.jar
ARG ALGO_URI=https://cdn.graphfoundation.org/apoc/dist/org/neo4j/procedure/apoc/3.5.0.2/apoc-3.5.0.2-all.jar
ARG GRAPHQL_URI=https://cdn.graphfoundation.org/apoc/dist/org/neo4j/procedure/apoc/3.5.0.2/apoc-3.5.0.2-all.jar

RUN apk add --no-cache --quiet \
    bash \
    curl \
    tini \
    su-exec \
    && curl --fail --silent --show-error --location --remote-name ${APOC_URI} \
    && echo "${APOC_SHA256}  ${APOC_JAR}" | sha256sum -csw - \
    && mv ${APOC_JAR} "${NEO4J_PLUGINS}" \
    && curl --fail --silent --show-error --location --remote-name ${ALGO_URI} \
    && echo "${ALGO_SHA256}  ${ALGO_JAR}" | sha256sum -csw - \
    && mv ${ALGO_JAR} "${NEO4J_PLUGINS}" \
    && curl --fail --silent --show-error --location --remote-name ${GRAPHQL_URI} \
    && echo "${GRAPHQL_SHA256}  ${GRAPHQL_JAR}" | sha256sum -csw - \
    && mv ${GRAPHQL_JAR} "${NEO4J_PLUGINS}" \
    && chown -R neo4j:neo4j "${NEO4J_PLUGINS}" \
    && chmod -R 777 "${NEO4J_PLUGINS}" \
    && apk del curl

