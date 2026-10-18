FROM docker.io/library/golang:1.26.9-bookworm@sha256:d9c68c2c51161e12fd77e4c6320687c9cd86e1af1e3ad6e6cd63ff970641453c AS build

ENV GOTOOLCHAIN=local GOMAXPROCS=2 CGO_ENABLED=0
WORKDIR /src
RUN curl -fsSL https://codeload.github.com/kubernetes/kube-state-metrics/tar.gz/f9f0a178a486dd1cc339ecebf40f27c6d5a48364 -o /tmp/source.tar.gz
RUN echo '5e33fb9879ed088a0f93f6d1aad6a91dfb82de976c46efabb821989b27d90b12  /tmp/source.tar.gz' | sha256sum -c -
RUN tar -xzf /tmp/source.tar.gz --strip-components=1 -C /src
COPY go.mod.patched /src/go.mod
COPY go.sum /src/go.sum
RUN go mod download
RUN go mod verify
RUN go test -mod=readonly -p=2 ./pkg/customresourcestate ./pkg/customresource
RUN go build -mod=readonly -p=2 -trimpath -buildvcs=false -ldflags='-s -w -X github.com/prometheus/common/version.Version=v2.17.0-piac49 -X github.com/prometheus/common/version.Revision=f9f0a178a486dd1cc339ecebf40f27c6d5a48364 -X github.com/prometheus/common/version.BuildUser=platform-iac -X github.com/prometheus/common/version.BuildDate=2026-10-15' -o /out/kube-state-metrics .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=build /out/kube-state-metrics /kube-state-metrics
COPY --from=build /src/LICENSE /usr/share/doc/kube-state-metrics/LICENSE
USER 65534:65534
ENTRYPOINT ["/kube-state-metrics", "--port=8080", "--telemetry-port=8081"]
EXPOSE 8080 8081
