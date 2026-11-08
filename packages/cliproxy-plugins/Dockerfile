# Build on the same Debian release as eceasy/cli-proxy-api, so the shared
# libraries link against the glibc they are loaded into.
FROM golang:1.26-bookworm@sha256:5de7c99eb78ca5e515a4c340235d0955ec5964a5071c492c15503d7c267da473 AS build
WORKDIR /src
COPY . .
# Each directory with a main package is one plugin, named after it.
RUN test -z "$(gofmt -l .)" \
  && go vet ./... \
  && go test ./... \
  && for plugin in clickhouse-archive; do \
    CGO_ENABLED=1 go build -trimpath -buildvcs=false -buildmode=c-shared \
      -o "/out/$plugin.so" "./$plugin" || exit 1; \
  done

# CLIProxyAPI's init container copies the plugins into its plugin directory.
FROM busybox:1.38.0@sha256:f97baa533a26513c453a362be331a43eb60214302f449c16571b23cea141dce4
COPY --from=build /out/*.so /plugin/
