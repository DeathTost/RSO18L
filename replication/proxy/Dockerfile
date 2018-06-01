FROM debian:jessie

RUN apt-get update && \
    apt-get install -y wget && \
    apt-get install -y mysql-client && \
    wget https://github.com/sysown/proxysql/releases/download/1.3.0f/proxysql_1.3.0f-debian8_amd64.deb -O /opt/proxysql_1.3.0f-debian8_amd64.deb && \
    dpkg -i /opt/proxysql_1.3.0f-debian8_amd64.deb && \
    rm -f /opt/proxysql_1.3.0f-debian8_amd64.deb && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 6033

ADD ./proxysql_done.cfg /var/lib/proxysql/proxysql.cfg

ENTRYPOINT ["proxysql", "--initial", "--foreground", "--config", "/var/lib/proxysql/proxysql.cfg"]

#FROM ubuntu:16.04
#
#ADD ./install_proxy.sh /tmp/install_proxy.sh
#RUN /bin/bash /tmp/install_proxy.sh
#
#EXPOSE 6032 6033
#
#CMD ["/usr/bin/systemctl", "start", "proxysql"]
