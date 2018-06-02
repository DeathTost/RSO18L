FROM mysql:5.7

RUN apt-get update && \
    apt-get install -y libdbd-mysql-perl ssh wget && \
    wget "https://github.com/yoshinorim/mha4mysql-node/releases/download/v0.58/mha4mysql-node_0.58-0_all.deb" -O /opt/node.deb && \
    dpkg -i /opt/node.deb && \
    rm -f /opt/node.deb

EXPOSE 22

RUN service ssh start
