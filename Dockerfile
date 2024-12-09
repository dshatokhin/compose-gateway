FROM mcr.microsoft.com/azurelinux/base/core:3.0

ARG PKL_VERSION="0.27.1"
ARG PKL_ARCH="amd64"

RUN tdnf install -y \
    ca-certificates \
    docker-cli \
    diffutils \
    bind-utils \
    && tdnf clean all \
    && rm -rf /var/cache/tdnf

RUN curl -L https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-${PKL_ARCH} -o /usr/local/bin/pkl && \
    chmod +x /usr/local/bin/pkl && \
    /usr/local/bin/pkl --version

WORKDIR /controller

COPY --from=mikefarah/yq:latest /usr/bin/yq /usr/local/bin/yq

COPY ./controller/ /controller

ENTRYPOINT ["/controller/main.sh"]
