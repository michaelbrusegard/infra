ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# The upstream health check runs unqualified `adb shell`. This image exposes
# both emulator-5556 and the forwarded 127.0.0.1:5555 endpoint, so that check
# reports "more than one device" even after a successful boot. Kubernetes uses
# explicit-serial startup/readiness/liveness probes from the StatefulSet.
HEALTHCHECK NONE

ARG ANDROID_EMULATOR_VERSION
ARG ANDROID_EMULATOR_SHA256
ARG ANDROID_SYSTEM_IMAGE_VERSION
ARG ANDROID_SYSTEM_IMAGE_SHA256
ARG ANDROID_PLATFORM_TOOLS_VERSION
ARG ANDROID_PLATFORM_TOOLS_SHA256
ARG AURORA_STORE_VERSION
ARG AURORA_STORE_SHA256

COPY platform-tools/ /opt/hermes/platform-tools/
COPY AuroraStore.apk /opt/hermes/apks/AuroraStore.apk

RUN set -eux; \
    rm -rf /android/sdk/platform-tools; \
    mv /opt/hermes/platform-tools /android/sdk/platform-tools; \
    test -x /android/sdk/platform-tools/adb; \
    mv /opt/hermes/apks/AuroraStore.apk "/opt/hermes/apks/AuroraStore-${AURORA_STORE_VERSION}.apk"; \
    echo "${AURORA_STORE_SHA256}  /opt/hermes/apks/AuroraStore-${AURORA_STORE_VERSION}.apk" | sha256sum -c -; \
    chmod 0644 "/opt/hermes/apks/AuroraStore-${AURORA_STORE_VERSION}.apk"

LABEL org.opencontainers.image.title="Hermes Android emulator" \
      org.opencontainers.image.description="Android 17 Play Store emulator for Hermes Agent" \
      org.opencontainers.image.source="https://github.com/michaelbrusegard/infra" \
      com.google.android.emulator.version="${ANDROID_EMULATOR_VERSION}" \
      com.google.android.emulator.sha256="${ANDROID_EMULATOR_SHA256}" \
      com.hermes.android.system-image="${ANDROID_SYSTEM_IMAGE_VERSION}" \
      com.hermes.android.system-image.sha256="${ANDROID_SYSTEM_IMAGE_SHA256}" \
      com.hermes.android.platform-tools="${ANDROID_PLATFORM_TOOLS_VERSION}" \
      com.hermes.android.platform-tools.sha256="${ANDROID_PLATFORM_TOOLS_SHA256}" \
      com.hermes.aurora-store.version="${AURORA_STORE_VERSION}" \
      com.hermes.aurora-store.sha256="${AURORA_STORE_SHA256}"
