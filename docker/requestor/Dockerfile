FROM alpine
ARG YA_INSTALLER_CORE=v0.12.0
RUN apk add curl bash
RUN mkdir -p /root/.local/bin
ENV PATH=/root/.local/bin:$PATH
VOLUME /data
ENV YAGNA_DATADIR=/data
RUN curl -sSf https://join.golem.network/as-requestor | BATCH_MODE=yes GOLEM_ACCEPT_TOS=yes bash -x -

ENTRYPOINT yagna service run

