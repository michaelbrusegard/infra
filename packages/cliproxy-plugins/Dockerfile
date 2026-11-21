# Build on the same Debian release as eceasy/cli-proxy-api, so the shared
# libraries link against the glibc they are loaded into.
FROM golang:1.27-bookworm@sha256:4fa7c968ba93f1635670522dbb01a2c78150443e1385746924566079f36570ea AS build
WORKDIR /src
COPY . .
# Each directory with a main package is one plugin, named after it.
RUN test -z "$(gofmt -l .)" \
  && go vet ./... \
  && go test ./... \
  && for plugin in clickhouse-archive soonest-reset; do \
    CGO_ENABLED=1 go build -trimpath -buildvcs=false -buildmode=c-shared \
      -o "/out/$plugin.so" "./$plugin" || exit 1; \
  done \
  && CGO_ENABLED=0 go build -trimpath -buildvcs=false \
    -o /out/normalizer/normalize-conversations ./normalize-conversations \
  && cp normalize-conversations/normalize.sh normalize-conversations/*.sql /out/normalizer/

# CLIProxyAPI's init container copies the plugins into its plugin directory,
# and the LLM normalizer's copies /normalizer next to clickhouse-client.
FROM busybox:1.38.0@sha256:f97baa533a26513c453a362be331a43eb60214302f449c16571b23cea141dce4
COPY --from=build /out/*.so /plugin/
COPY --from=build /out/normalizer /normalizer/
