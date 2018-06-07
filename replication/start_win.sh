#!/bin/bash

NO_SLAVES=$1
STARTING_PORT=${2:-3306}
VM_ADDR='192.168.99.100'

main() {
    master_ip=$(common_setup 0 master)
    master_setup $STARTING_PORT
    for i in $(seq $NO_SLAVES)
    do
        slave_ip=$(common_setup $i slave)
	slave_setup $((i + STARTING_PORT)) $master_ip
    done
    setup_proxy
}

common_setup() {
    index=$1
    conf=$2
    config_dir="$index"_"$STARTING_PORT"_config

    rm -rf $config_dir
    mkdir $config_dir

    sed -e "s|server-id=|server-id=$((index + 1))|;"\
        "my.cnf" > "$config_dir/my.cnf"
    chmod 444 "$config_dir/my.cnf"

    docker build -t dbserver mysql &>/dev/null
    docker run \
        -v "$(pwd)/$config_dir":/etc/mysql/conf.d \
        -p $((STARTING_PORT + index)):3306 \
        -d \
        -e MYSQL_ALLOW_EMPTY_PASSWORD=1 \
        dbserver &>/dev/null
    id=$(docker ps -q -l)
    ip=$(docker inspect $id | grep -w IPAddress -m 1 | awk '{print substr($2, 2, length($2)-3)}')
    sleep 100
    echo $ip
}

master_setup() {
    mysql -h$VM_ADDR -P$STARTING_PORT -uroot <<<\
        "CREATE USER 'rso'@'%' IDENTIFIED BY 'rso';
         GRANT ALL PRIVILEGES ON *.* TO 'rso'@'%';
         CREATE USER 'replication'@'%' IDENTIFIED BY 'replication';
         GRANT REPLICATION SLAVE ON *.* TO 'replication'@'%';
         CREATE USER 'monitor'@'%' IDENTIFIED BY 'monitor';
         CREATE USER 'manager'@'%' IDENTIFIED BY 'manager';
         GRANT ALL PRIVILEGES ON *.* TO 'manager'@'%';
         CREATE DATABASE rso;
         CREATE DATABASE keycloak;
         INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
         SET GLOBAL rpl_semi_sync_master_enabled=1;"

}

slave_setup() {
    mysql -h$VM_ADDR -P$1 -uroot <<<\
        "CHANGE MASTER TO
            MASTER_HOST='$2',
            MASTER_PORT=3306,
            MASTER_USER='replication',
            MASTER_PASSWORD='replication';
         SET GLOBAL read_only = 1;
         INSTALL PLUGIN rpl_semi_sync_slave SONAME 'semisync_slave.so';
         SET GLOBAL rpl_semi_sync_slave_enabled=1;
         START SLAVE;
         STOP SLAVE IO_THREAD;
         START SLAVE IO_THREAD;"
}

share_keys() {
    keys=""
    for id in $(docker ps -n $((NO_SLAVES + 2)) -q)
    do
        key=$(docker exec -it $id bash -c "ssh-keygen -t rsa -N \"\" -f /root/.ssh/id_rsa &>/dev/null; cat /root/.ssh/id_rsa.pub")
        keys="$key\n$keys"
    done
    for id in $(docker ps -n $((NO_SLAVES + 2)) -q)
    do
        docker exec -it $id bash -c "mkdir -p /root/.ssh/ && printf \"$keys\" > /root/.ssh/authorized_keys && service ssh restart"
    done
}

proxy_prepare() {
    insert_cmd="mysql_servers=({address=\"172.17.0.1\"\nport=$STARTING_PORT\nhostgroup=1}"
    for i in $(seq $NO_SLAVES)
    do
        insert_cmd=$insert_cmd",\n{hostgroup=2\naddress=\"172.17.0.1\"\nport=$(($STARTING_PORT + i))}"
    done
    insert_cmd=$insert_cmd")"
    cp ./proxysql.cfg $1/proxysql_done.cfg
    printf $insert_cmd >> $1/proxysql_done.cfg
}

setup_proxy() {
    proxy_dir="proxy_$STARTING_PORT"
    rm -rf $proxy_dir
    mkdir $proxy_dir
    cp proxy/* $proxy_dir
    proxy_prepare $proxy_dir
    manager_prepare $proxy_dir
    docker build -t proxy $proxy_dir
    proxy_port=$((STARTING_PORT + NO_SLAVES + 1))
    docker run -d -p$proxy_port:6033 proxy
    share_keys
    echo "Started proxy on port: $proxy_port"
    docker exec -it $(docker ps -q -l) bash -c "masterha_manager --conf=/etc/mha_manager.cfg"
}

manager_prepare() {
    insert_cmd=""
    for id in $(docker ps -n $((NO_SLAVES + 1)) -q)
    do
        ip=$(docker inspect $id | grep -w IPAddress -m 1 | awk '{print substr($2, 2, length($2)-3)}')
        insert_cmd=$insert_cmd"\n[server-$id]\nhostname=host-$id\nip=$ip\nport=3306\n"
    done
    cp ./mha_manager.cfg $1/mha_manager_done.cfg
    printf $insert_cmd >> $1/mha_manager_done.cfg
}

main
