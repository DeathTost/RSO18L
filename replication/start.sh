#!/bin/bash

NO_SLAVES=$1
STARTING_PORT=${2:-3306}

main() {
    master_ip=$(common_setup 0 master)
    master_setup $master_ip
    for i in $(seq 1 $((NO_SLAVES)))
    do
        slave_ip=$(common_setup $i slave)
        slave_setup $slave_ip
    done
    proxy_prepare
    docker build -t proxy proxy
    docker run -p6033:6033 proxy
}

common_setup() {
    index=$1
    conf=$2
    config_dir="$index"_config

    rm -rf $config_dir
    mkdir $config_dir

    sed -e "s|server-id=|server-id=$((index + 1))|;"\
        "my.cnf" > "$config_dir/my.cnf"

    id=$(docker run \
        -v $(pwd)/$config_dir:/etc/mysql/conf.d \
        -p $((STARTING_PORT + index)):3306 \
        -d \
        -e MYSQL_ALLOW_EMPTY_PASSWORD=1 \
        mysql:5.7)
    ip=$(docker inspect $id | grep -w IPAddress -m 1 | awk '{print substr($2, 2, length($2)-3)}')
    sleep 30
    echo $ip
}

master_setup() {
    mysql -h$1 -P3306 -uroot < master/my.sql
}

slave_setup() {
    mysql -h$1 -P3306 -uroot <<<\
        "CHANGE MASTER TO
            MASTER_HOST='172.17.0.1',
            MASTER_PORT=$STARTING_PORT,
            MASTER_USER='replication',
            MASTER_PASSWORD='replication';
         SET GLOBAL read_only = 1;
         START SLAVE;"
}

proxy_prepare() {
    insert_cmd="mysql_servers=({address=\"172.17.0.1\"\nport=$STARTING_PORT\nhostgroup=1}"
    for i in $(seq $NO_SLAVES)
    do
        insert_cmd=$insert_cmd",\n{hostgroup=2\naddress=\"172.17.0.1\"\nport=$(($STARTING_PORT + i))}"
    done
    insert_cmd=$insert_cmd")"
    cp ./proxysql.cfg proxy/proxysql_done.cfg
    printf $insert_cmd >> proxy/proxysql_done.cfg
}

main
