FROM tensorchord/vchord-scratch:pg18-v1.1.1@sha256:bdea43bed2a414e21bbf71767bf6f0739747ac480b267b51772dc214ac28dcb3 AS vchord
FROM postgres:18-bookworm@sha256:9479eac93922431e8a512b016d7362ae264f4ba139f840891b51f02931e450db

# renovate: suite=bookworm-pgdg depName=postgresql-18-cron
ARG POSTGRESQL_18_CRON_VERSION=1.6.7-3.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-hll
ARG POSTGRESQL_18_HLL_VERSION=2.21-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-hypopg
ARG POSTGRESQL_18_HYPOPG_VERSION=1.4.3-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-partman
ARG POSTGRESQL_18_PARTMAN_VERSION=5.4.3-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pgaudit
ARG POSTGRESQL_18_PGAUDIT_VERSION=18.0-3.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pg-stat-kcache
ARG POSTGRESQL_18_PG_STAT_KCACHE_VERSION=2.3.2-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pg-wait-sampling
ARG POSTGRESQL_18_PG_WAIT_SAMPLING_VERSION=1.1.9-2.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pglogical
ARG POSTGRESQL_18_PGLOGICAL_VERSION=2.4.7-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pgrouting
ARG POSTGRESQL_18_PGROUTING_VERSION=4.0.1-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pgrouting-scripts
ARG POSTGRESQL_18_PGROUTING_SCRIPTS_VERSION=4.0.1-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-pgvector
ARG POSTGRESQL_18_PGVECTOR_VERSION=0.8.4-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-postgis-3
ARG POSTGRESQL_18_POSTGIS_3_VERSION=3.6.4+dfsg-2.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-postgis-3-scripts
ARG POSTGRESQL_18_POSTGIS_3_SCRIPTS_VERSION=3.6.4+dfsg-2.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-repack
ARG POSTGRESQL_18_REPACK_VERSION=1.5.3-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-timescaledb
ARG POSTGRESQL_18_TIMESCALEDB_VERSION=2.28.2+dfsg-1.pgdg12+1
# renovate: suite=bookworm-pgdg depName=postgresql-18-wal2json
ARG POSTGRESQL_18_WAL2JSON_VERSION=2.6-3.pgdg12+1

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      postgresql-18-cron="${POSTGRESQL_18_CRON_VERSION}" \
      postgresql-18-hll="${POSTGRESQL_18_HLL_VERSION}" \
      postgresql-18-hypopg="${POSTGRESQL_18_HYPOPG_VERSION}" \
      postgresql-18-partman="${POSTGRESQL_18_PARTMAN_VERSION}" \
      postgresql-18-pgaudit="${POSTGRESQL_18_PGAUDIT_VERSION}" \
      postgresql-18-pg-stat-kcache="${POSTGRESQL_18_PG_STAT_KCACHE_VERSION}" \
      postgresql-18-pg-wait-sampling="${POSTGRESQL_18_PG_WAIT_SAMPLING_VERSION}" \
      postgresql-18-pglogical="${POSTGRESQL_18_PGLOGICAL_VERSION}" \
      postgresql-18-pgrouting="${POSTGRESQL_18_PGROUTING_VERSION}" \
      postgresql-18-pgrouting-scripts="${POSTGRESQL_18_PGROUTING_SCRIPTS_VERSION}" \
      postgresql-18-pgvector="${POSTGRESQL_18_PGVECTOR_VERSION}" \
      postgresql-18-postgis-3="${POSTGRESQL_18_POSTGIS_3_VERSION}" \
      postgresql-18-postgis-3-scripts="${POSTGRESQL_18_POSTGIS_3_SCRIPTS_VERSION}" \
      postgresql-18-repack="${POSTGRESQL_18_REPACK_VERSION}" \
      postgresql-18-timescaledb="${POSTGRESQL_18_TIMESCALEDB_VERSION}" \
      postgresql-18-wal2json="${POSTGRESQL_18_WAL2JSON_VERSION}"; \
    rm -rf /var/lib/apt/lists/*

COPY --from=vchord / /
