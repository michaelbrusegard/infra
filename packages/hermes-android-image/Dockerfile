FROM redroid/redroid:15.0.0_64only-latest@sha256:b51bde9cef80f7bd7581148192f2b2f4d41f23c6344cfe88eceeb8ddd67490ee AS android-base

FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db AS tools
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates e2fsprogs erofs-utils fdisk openjdk-17-jdk-headless patch python3 unzip util-linux zip && \
    rm -rf /var/lib/apt/lists/*
ADD --checksum=sha256:840b23e827f96e64aea4c89a1194aac3dc5f6bad37edb231c5c795d890330e8d \
    https://dl.google.com/android/repository/platform-37.0_r02.zip /inputs/platform.zip
ADD --checksum=sha256:01af179347cbcd9c208b7f8171f7b21f6dd1d2f85bcd15e88caa51d5d7b86060 \
    https://dl.google.com/android/repository/build-tools_r37_linux.zip /inputs/build-tools.zip
RUN mkdir -p /sdk && unzip -q /inputs/build-tools.zip -d /sdk && mv /sdk/android-* /sdk/build-tools

FROM tools AS companion
ARG HERMES_ACCESSIBILITY_VERSION=1.0.0
ARG HERMES_ACCESSIBILITY_VERSION_CODE=1
ARG HERMES_ACCESSIBILITY_SIGNING_CERT_SHA256=384c4099c4ab6261fb5046f8f4b65723067d55e5bbbf97c895804d40e50a3f4f
ADD --checksum=sha256:91d728fe501694798975078002f8fa9aa7dd23b4591015401b63b7d06ac528e9 \
    https://android.googlesource.com/platform/build/+/045a3d6a3e359633a14853a5a5e1e4f2a11cbdae/target/product/security/testkey.pk8?format=TEXT \
    /inputs/testkey.pk8.b64
ADD --checksum=sha256:be3a20553271524b7f0dd5cb41c3c2fa2caa41fc5e18fa3f3806d497dd820ed3 \
    https://android.googlesource.com/platform/build/+/045a3d6a3e359633a14853a5a5e1e4f2a11cbdae/target/product/security/testkey.x509.pem?format=TEXT \
    /inputs/testkey.x509.pem.b64
COPY hermes-android-companion /src
# A build without the signing secrets, as a pull request's is, signs the
# companion with the public AOSP test key instead.
RUN --mount=type=secret,id=signing-key --mount=type=secret,id=signing-cert \
    base64 -d /inputs/testkey.pk8.b64 >/inputs/testkey.pk8 && \
    base64 -d /inputs/testkey.x509.pem.b64 >/inputs/testkey.x509.pem && \
    if [ -s /run/secrets/signing-key ]; then \
      cp /run/secrets/signing-key /inputs/testkey.pk8 && \
      cp /run/secrets/signing-cert /inputs/testkey.x509.pem && \
      python3 -c 'import base64, hashlib, sys; body = "".join(line for line in open(sys.argv[1]).read().splitlines() if "-----" not in line); sys.exit(hashlib.sha256(base64.b64decode(body)).hexdigest() != sys.argv[2])' \
        /inputs/testkey.x509.pem "$HERMES_ACCESSIBILITY_SIGNING_CERT_SHA256"; \
    fi && \
    bash /src/build.sh /inputs/platform.zip /inputs/build-tools.zip /inputs/testkey.pk8 /inputs/testkey.x509.pem \
      "$HERMES_ACCESSIBILITY_VERSION_CODE" "$HERMES_ACCESSIBILITY_VERSION" \
      "/output/HermesAccessibility-$HERMES_ACCESSIBILITY_VERSION.apk" && \
    unzip -q /inputs/platform.zip -d /sdk/platform && \
    mkdir -p /work/classes /work/dex && \
    javac --release 11 -classpath /sdk/platform/android-*/android.jar -d /work/classes \
      /src/clipboard/com/hermes/agent/clipboard/Main.java && \
    /sdk/build-tools/d8 --lib /sdk/platform/android-*/android.jar --min-api 30 --output /work/dex \
      /work/classes/com/hermes/agent/clipboard/Main.class && \
    zip -q -X -j /output/hermes-clipboard.jar /work/dex/classes.dex

FROM tools AS google
ADD --checksum=sha256:c67b9ba0ff5bc0eb6d046871bfa228af14d4d47b02f0cdae94f048e511b7566e \
    https://dl.google.com/android/repository/sys-img/google_apis/x86_64-35_r09.zip /inputs/google-apis.zip
ADD --checksum=sha256:1fb5e5fd1c4b1b54bfe5558f6f361d6c10e13786acff630153e0542df356dfe6 \
    https://dl.google.com/android/repository/sys-img/google_apis_playstore/x86_64-35_r09.zip /inputs/google-play.zip
ADD --checksum=sha256:600d1cab2fc7de5127fb287f4e2791718db54efb1102d0f365db0d3ec1ccf62e \
    https://raw.githubusercontent.com/unix3dgforce/lpunpack/c59b8f3b069c5a8aa438a049fa4a091177172434/lpunpack.py \
    /inputs/lpunpack.py
COPY hermes-android-image/google_overlay.py /build/
RUN python3 /build/google_overlay.py /inputs /output/rootfs /sdk/build-tools/apksigner && chmod -R a+rX /output

FROM tools AS gralloc
ADD --checksum=sha256:4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf \
    https://dl.google.com/android/repository/android-ndk-r29-linux.zip /inputs/ndk.zip
ADD --checksum=sha256:caf1ed96b5f1f4f68511c4d4f8792c41ac2b2aabddefb170210aaaeb76804f4a \
    https://raw.githubusercontent.com/remote-android/vendor_redroid/1686c1825c146891d06004e35e7c362b58d3f1bc/gralloc/framebuffer.cpp /sources/
ADD --checksum=sha256:d63ec71bc4f2b9ad34ea33515a2e56ddb2898b07b4e28d46f883c3ac5d431795 \
    https://raw.githubusercontent.com/remote-android/vendor_redroid/1686c1825c146891d06004e35e7c362b58d3f1bc/gralloc/gr.h /sources/
ADD --checksum=sha256:5260125b1a4c427bd2e51b4fe0ae91f7a8cb7837d44d840ab298443a91cdf586 \
    https://raw.githubusercontent.com/remote-android/vendor_redroid/1686c1825c146891d06004e35e7c362b58d3f1bc/gralloc/gralloc.cpp /sources/
ADD --checksum=sha256:41072abce5bbd23438e3f779b6e59e1aa2fc9bd215e971cb6e44e4aab33cca7c \
    https://raw.githubusercontent.com/remote-android/vendor_redroid/1686c1825c146891d06004e35e7c362b58d3f1bc/gralloc/gralloc_priv.h /sources/
ADD --checksum=sha256:c58d6d2cd094edab6dce4c03c7278df33c94566e349b351ea6457b19c55b847e \
    https://raw.githubusercontent.com/remote-android/vendor_redroid/1686c1825c146891d06004e35e7c362b58d3f1bc/gralloc/mapper.cpp /sources/
# Gitiles stamps every archive with the request time, so these are pinned by
# commit instead of by checksum.
ADD https://android.googlesource.com/platform/hardware/libhardware/+archive/e01b6f769022e40d0923dee176e8dc7cd1d52984/include_all.tar.gz \
    /headers/libhardware/
ADD https://android.googlesource.com/platform/system/core/+archive/00c7fec1bb09f3284aad6a6f96d2f63dfc3650ad/libcutils/include.tar.gz \
    /headers/libcutils/
ADD https://android.googlesource.com/platform/system/core/+archive/00c7fec1bb09f3284aad6a6f96d2f63dfc3650ad/libsystem/include.tar.gz \
    /headers/libsystem/
ADD https://android.googlesource.com/platform/system/logging/+archive/598139dc91b21518d67c408eaea2644226490971/liblog/include.tar.gz \
    /headers/liblog/
COPY --from=android-base /system/lib64/ /android/system/lib64/
COPY hermes-android-image/gralloc /build/gralloc
RUN unzip -q /inputs/ndk.zip -d /ndk && \
    for name in libhardware libcutils libsystem liblog; do \
      tar -xzf /headers/$name/*.tar.gz -C /headers/$name; \
    done && \
    bash /build/gralloc/build.sh /sources /headers /ndk/android-ndk-r29 /android \
      /output/rootfs/vendor/lib64/hw/gralloc.redroid.so

FROM tools AS rootfs
COPY --from=android-base / /rootfs/
COPY --from=google /output/rootfs/ /rootfs/
COPY --from=gralloc /output/rootfs/ /rootfs/
COPY hermes-android-image/device_profile.py /build/
COPY --chmod=0644 hermes-android-image/container.rc /rootfs/system/etc/init/container.rc
RUN python3 /build/device_profile.py /rootfs && rm /rootfs/system/xbin/su

FROM ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    adb ca-certificates crun iproute2 iptables socat tini && \
    rm -rf /var/lib/apt/lists/*
COPY --from=rootfs /rootfs/ /opt/android-image/rootfs/
COPY --from=companion /output/ /opt/android-image/apks/
ADD --checksum=sha256:8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad --chmod=0644 \
    https://apt.izzysoft.de/fdroid/repo/com.aurora.store_76.apk \
    /opt/android-image/apks/AuroraStore-4.8.4.apk
ADD --checksum=sha256:71c752dab6c948c0e1ea06916f2ffd484bbc7c57a48af0ee05a718aca3adab8b --chmod=0644 \
    https://github.com/bk138/droidVNC-NG/releases/download/v2.22.3/droidvnc-ng-2.22.3.apk \
    /opt/android-image/apks/droidvnc-ng.apk
COPY --chmod=0755 hermes-android-image/run-android.sh /usr/local/bin/run-android
RUN sed -n 's/^ro\.build\.version\.release=//p' /opt/android-image/rootfs/system/build.prop \
    >/opt/android-image/release
LABEL org.opencontainers.image.title="Hermes Android" \
      org.opencontainers.image.source="https://github.com/michaelbrusegard/infra"
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/run-android"]
