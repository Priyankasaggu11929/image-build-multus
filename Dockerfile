#!UseOBSRepositories

#!BuildTag: rancher/image-build-etcd:v4.2.0
#!BuildTag: rancher/image-build-etcd:latest
#!BuildName: image-build-etcd

ARG GO_IMAGE=rancher/image-build-base:latest

FROM ${GO_IMAGE} AS base-builder

RUN set -euo pipefail; \
    zypper -n install --no-recommends \
    # file \
    gcc
    # git \
    # clang7 \
    # llvm7 \
    # lld \  
    musl-gcc \
    musl-libc-static \
    patch \
    make; \
    zypper -n clean; \
    rm -rf {/target,}/var/log/{alternatives.log,lastlog,tallylog,zypper.log,zypp/history,YaST2}


# Build the multus project
FROM base-builder AS multus-builder
ARG TAG=v4.2.0
ARG SRC=github.com/k8snetworkplumbingwg/multus-cni
ARG PKG=github.com/k8snetworkplumbingwg/multus-cni
ENV C_INCLUDE_PATH="/usr/x86_64-linux-musl/include/:/usr/include/"
ENV CC="musl-gcc"

COPY multus-cni ${GOPATH}/src/${PKG}

WORKDIR $GOPATH/src/${PKG}

RUN ./hack/build-go.sh

FROM ${GO_IMAGE} AS strip_binary
#strip needs to run on TARGETPLATFORM, not BUILDPLATFORM
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/thin_entrypoint /thin_entrypoint
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/multus /multus
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/kubeconfig_generator /kubeconfig_generator
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/cert-approver /cert-approver
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/install_multus /install_multus
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/multus-daemon /multus-daemon
COPY --from=multus-builder /go/src/github.com/k8snetworkplumbingwg/multus-cni/bin/multus-shim /multus-shim
RUN strip /thin_entrypoint /multus /kubeconfig_generator /cert-approver /install_multus /multus-daemon /multus-shim

# Create the multus image
FROM scratch AS multus-thin
COPY --from=strip_binary  /multus /usr/src/multus-cni/bin/multus
COPY --from=multus-builder  /go/src/github.com/k8snetworkplumbingwg/multus-cni/LICENSE /usr/src/multus-cni/LICENSE
COPY --from=strip_binary    /thin_entrypoint /
COPY --from=strip_binary    /kubeconfig_generator /
COPY --from=strip_binary    /cert-approver /
COPY --from=strip_binary    /install_multus /
ENTRYPOINT ["/thin_entrypoint"]

# Create the thick plugin image
FROM scratch AS multus-thick
COPY --from=multus-builder  /go/src/github.com/k8snetworkplumbingwg/multus-cni/LICENSE /usr/src/multus-cni/LICENSE
COPY --from=strip_binary  /multus-daemon /usr/src/multus-cni/bin/multus-daemon
COPY --from=strip_binary  /multus-shim /usr/src/multus-cni/bin/multus-shim
COPY --from=strip_binary    /install_multus /
ENTRYPOINT [ "/usr/src/multus-cni/bin/multus-daemon" ]
