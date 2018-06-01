Replication howto

Jak ktoś jest odważny, to może spróbować skryptu start_sqls.sh, deklaruje, że
__u mnie działa__.  Skrypt wymaga obecności wszystkich `proxysql` `mysql` i
`mysqld` w $PATH, oraz nieobecności wszystkich proxysql i mysqld w procesach.
Poza tym, powinien działać uruchomiony z CWD='.' i jednym argumentem
oznaczajacym liczbe slave'ów. Przykład użycia: PATH="../bin/:$PATHą"
./start_sqls.sh 3

Pierwszym krokiem jest postawienie n instancji serwerów sql, gdzie n > 1 w
konfiguracji 1 master oraz n - 1 slaveów. Tutaj pomocne są pliki konfiguracyjne
master.cnf oraz slave.cnf. Na ich końcu jest lista zmiennych do uzupełnienia,
generalnie polecam uzupełnienie jak na wzorku:

server-id=2
port=3308
datadir=/home/kksiaze/Programs/mysql/slave
socket=/home/kksiaze/Programs/mysql/slave/slave.socket
pid-file=/home/kksiaze/Programs/mysql/slave/slave.pid
general_log_file=/home/kksiaze/Programs/mysql/slave/slave.log

Gdzie wszystkie wartości mają być unikalne dla każdego servera mysql ofc.

Gdy już to mamy, uruchomienie serwera to kwestia znanych już:

mysqld --defaults-file=$UZUPELNIONY_CONFIG --initialize-insecure
mysqld --defaults-file=$UZUPELNIONY_CONFIG --console

(oraz wcześniejszego ubicia poprzednich mysqld działających, o ile są)

Jeśli wszystko działa, to do serwerów podłączymy się przy użyciu komendy:

mysql -u root -S $SOCKET

gdzie socket jest odpowiadającą wartością z configu, u mnie
[...]/slave/slave.socket.

Importujemy teraz użytkowników na potem (i ew. keycloaka) do mastera, kwestia
zaimportowania dwóch plików:

mysql -u root -S $master_socket < master.sql
mysql -u root -S $master_socket < keycloak.sql

A na każdym ze slave'ów wykonujemy:

CHANGE MASTER TO MASTER_HOST='127.0.0.1', MASTER_PORT=3306, MASTER_USER='replication', MASTER_PASSWORD='replication';
SET GLOBAL read_only = 1;
START SLAVE;

Jeśli wszystko działa, to nie dość, że żaden z serwerów nie rzuci errorem, to
jeszcze po chwili na slave'ach powinny się pojawić dane z mastera, w
szczególności userzy replication, rso i monitor. Rzucić okiem w stylu:

select * from mysql.user;

Kolejną rzeczą jest setup proxysqla, zaczynamy ponownie od upewnienia się, że
jest martwy. Ze "świeżą" konfiguracją odpala się go:

proxysql --initial

I volia, można się podłączyć przy użyciu:

mysql -uadmin -padmin -h 127.0.0.1 -P 6032

Konfiguracja znajduje się w pliku proxy.sql, trzeba tam tylko podmienić linię TO_REPLACE_BY_SED na:

INSERT INTO mysql_servers(hostgroup_id, hostname, port) VALUES (1, '127.0.0.1', 3306);

z danymi mastera oraz dopisać dla każdego slave:

INSERT INTO mysql_servers(hostgroup_id, hostname, port) VALUES (2, '127.0.0.1', $PORT);
                                    (note zmiana z 1 na 2 tutaj ^)

uzupełniajac $PORT portami slave'ów. Majac tak przygotowany plik, wołamy:

mysql -uadmin -padmin -h 127.0.0.1 -P 6032 < $proxy_sql

I proxysql zostało skonfigurowane. Aplikacje mają dostęp przez port 6033, user:
rso, password: rso My też możemy sprawdzić poprawność konfiguracji, w
szczególności łącząc się:

mysql -urso -prso -h 127.0.0.1 -P 6033

I wykonując jakieś operacje, w szczególności pomocne jest "select @@port;",
które powinno zwrócić port jednego ze slave'ów.

iptables -A INPUT -i docker0 -j ACCEPT
