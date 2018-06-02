FROM debian:jessie

RUN apt-get update && \
    apt-get install -y wget mysql-client libdbd-mysql-perl libconfig-tiny-perl liblog-dispatch-perl libparallel-forkmanager-perl wget ssh && \
    wget "https://github.com/sysown/proxysql/releases/download/1.3.0f/proxysql_1.3.0f-debian8_amd64.deb" -O /opt/proxysql.deb && \
    wget "https://github.com/yoshinorim/mha4mysql-node/releases/download/v0.58/mha4mysql-node_0.58-0_all.deb" -O /opt/node.deb && \
    wget "https://github.com/yoshinorim/mha4mysql-manager/releases/download/v0.58/mha4mysql-manager_0.58-0_all.deb" -O /opt/manager.deb && \
    dpkg -i /opt/node.deb && \
    dpkg -i /opt/manager.deb && \
    dpkg -i /opt/proxysql.deb && \
    rm -f /opt/node.deb /opt/manager.deb /opt/proxysql.deb && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 6033 22

ADD ./proxysql_done.cfg /var/lib/proxysql/proxysql.cfg
ADD ./mha_manager_done.cfg /etc/mha_manager.cfg

RUN service ssh start

ENTRYPOINT ["proxysql", "--initial", "--foreground", "--config", "/var/lib/proxysql/proxysql.cfg"]
