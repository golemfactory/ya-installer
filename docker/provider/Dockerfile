FROM alpine
ARG YA_INSTALLER_CORE=v0.12.0
ARG YA_INSTALLER_WASI=v0.2.2
#ARG YA_INSTALLER_VM=pre-rel-v0.3.4-rc2
ARG YA_INSTALLER_VM=v0.3.0
RUN apk add curl bash tar
RUN mkdir -p /root/.local/bin
ENV PATH=/root/.local/bin:$PATH
RUN echo $PATH
RUN curl -sSf https://join.golem.network/as-provider | BATCH_MODE=yes GOLEM_ACCEPT_TOS=yes bash -x -
ENV YA_RT_MEM=1.0
ENV YA_RT_CORES=2
ENV YA_RT_STORAGE=20
ENV YA_PAYMENT_NETWORK_GROUP=testnet
