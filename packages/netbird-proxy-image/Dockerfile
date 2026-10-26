FROM docker.io/library/golang:1.26.10-alpine@sha256:27f2d3b83cfc5803c8078f8e730af0f7c431bf067afaec8f60a36fb763187cba AS build
WORKDIR /src
RUN apk add --no-cache patch
ADD --checksum=sha256:d28a439cf8dcd56214ad248eb2fe576bd4303567a32166c6696e33c1fdbee108 https://codeload.github.com/netbirdio/netbird/tar.gz/f47ace7d52a182d2ee75e6d821c26260e601c89e /tmp/netbird.tar.gz
RUN tar -xzf /tmp/netbird.tar.gz --strip-components=1
COPY images.patch /tmp/images.patch
RUN patch -p1 < /tmp/images.patch
ENV CGO_ENABLED=0
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    go test ./proxy/internal/llm ./proxy/internal/middleware/bodytap \
      ./proxy/internal/middleware/builtin/llm_request_parser \
      ./proxy/internal/middleware/builtin/llm_router \
      ./proxy/internal/middleware/builtin/llm_guardrail && \
    go test ./proxy/internal/proxy -run TestImagesHTTPForwarding -count=1 && \
    go build -trimpath -ldflags='-s -w -X main.Version=0.81.3-infra-images -X github.com/netbirdio/netbird/version.version=0.81.3-infra-images' \
      -o /out/netbird-proxy ./proxy/cmd/proxy

# Preserve upstream's CA certificates, UID, shell and filesystem layout.
FROM docker.io/netbirdio/reverse-proxy:0.81.3@sha256:5da714cd47a66a7c74ddbacc54a6a90d35c1959b77d1744a149b082e69659b45
COPY --from=build /out/netbird-proxy /go/bin/netbird-proxy
