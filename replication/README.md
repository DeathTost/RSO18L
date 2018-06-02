# HOW DO I INTO REPLICATION

### 1. Master of Puppets

Zaglądamy do pliku my.cnf w repo. Szybko zauważamy, że brakuje mu opcji
server-id. Uzupełniamy ją dowolną **pozytywną** wartością (na przyszłość: mają
tutaj być unikalne wartości __across whole system__). Tak powstały nowy config
umieszczamy w jakimś katalogu, np. `master_config`.

Pora ruszyć z Dockerem:
```
    docker build -t dbserver mysql
    docker run \
        -v master_config:/etc/mysql/conf.d \
        -p 3306:3306 \
        -d \
        -e MYSQL_ALLOW_EMPTY_PASSWORD = 1 \
        dbserver
```

> W opcji `-p 3306:3306` zdefiniowaliśmy port na naszej maszynie na który
> mapować ma się 3306 z kontenera (przypadkiem to również 3306). Dalsze
> przykłady pisane są z myślą, że nikt nie będzie próbował mapować dwóch tych
> samych portów.

Po tym nasz master powinien działać, tj. możemy się na niego zalogować: `mysql
-h127.0.0.1 -P3306 -uroot` (dla windowsów jest to `-h192.168.99.100`). Skoro
tak, to wchodzimy i wykonujemy następujące komendy:
```
    CREATE USER 'rso'@'%' IDENTIFIED BY 'rso';
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
```

Jest to również dobry moment na wprowadzenie własnych danych, potrzebnych
serwisom do działania.

### 2. Powerslave

__Krok należy powtarzać do osiągnięcia zadowalającej ilości niewolników,
zazwyczaj jeden.__

Podobnie jak w przypadku mastera, kopiujemy uzupełniony inną wartością config
do nowego folderu i wykonujemy:
```
    docker run \
        -v slave_config:/etc/mysql/conf.d \
        -p 3307:3306 \
        -d \
        -e MYSQL_ALLOW_EMPTY_PASSWORD = 1 \
        dbserver
```

Powinniśmy móc się zalogować w podobny sposób jak do mastera (tylko podając
odpowiedni port). Stąd wykonujemy:
```
    CHANGE MASTER TO
        MASTER_HOST='192.168.99.100',
        MASTER_PORT=3306,
        MASTER_USER='replication',
        MASTER_PASSWORD='replication';
    SET GLOBAL read_only = 1;
    INSTALL PLUGIN rpl_semi_sync_slave SONAME 'semisync_slave.so';
    SET GLOBAL rpl_semi_sync_slave_enabled=1;
    START SLAVE;
    STOP SLAVE IO_THREAD;
    START SLAVE IO_THREAD;
```

Gdzieś teraz powinniśmy na slavie zobaczyć dane z mastera, w szczególności te
dodatkowe, ale również użytkowników:
```
    SELECT * FROM mysql.user;
```

### 3. Ergo Proxy

Tym razem otwieramy proxysql.cfg, umieszczamy się na końcu i dopisujemy regułkę
serwerów według wzorku:
```
mysql_servers =
(
    {
        address="192.168.99.100" #or "172.17.0.1"
        port=3306
        hostgroup=1
    },
    {
        address="192.168.99.100" #or "172.17.0.1"
        port=3307
        hostgroup=2
    }
)
```
wpisując wszystkie utworzone wcześniej serwery. Ważną zmienną jest `hostgroup`,
które przyjmuje wartości: 1 dla mastera i 2 dla slave'ów. Gotowy plik
umieszczamy w katalogu proxy pod nazwą proxysql\_done.cfg

**Windows untested, propably won't work**:
Nieco na przyszłość: w podobny sposób wypełniamy mha\_manager.cnf, wymagana jest
jedynie nieco inna składnia:
```
[server default]
user=manager
password=manager
ssh_user=root

manager_workdir=/var/log/mha_manager/
remote_workdir=/var/log/mha_manager

[server1]
hostname=host1
ip=172.17.0.3
port=3306

[server2]
hostname=host2
ip=172.17.0.2
port=3306
```
Który to również ma wylądować w katalogu proxy, tym razem pod nazwą
mha\_manager\_done.cfg

> To config dla mha, jako że on wymaga komunikacji przez ssh, ważne żeby
> podawać te "wewnętrzne" adresy dockera, po to, żeby mha mógł później zrobić
> `ssh root@172.17.0.2`. Te adresy mają się również zgadzać z konfiguracją
> master-slave, tj. z komendą `CHANGE MASTER TO MASTER_HOST=[...],
> MASTER_PORT=[...]`, gdzie też powinniśmy pewnie wpisać 172.17.0.x oraz port
> 3306.

Proxy uruchamiamy w poniższy sposób:
```
    docker build -t proxy proxy
    docker run -p 3308:6033 -d proxy
```

Do działającego proxy możemy normalnie wejść przez mysqla:
```
    mysql -h192.168.99.100 -P3308 -urso -prso
```
Gdzie powinniśmy zobaczyć wszystkie dane tak, jak ustawiliśmy je na masterze.

### 4. Moves Like Manager

Jeśli jednak zdecydowaliśmy się w poprzednim punkcie na wybór bramki Windows
untested, następnym krokiem jest ustawienie komunikacji ssh pomiędzy
kontenerami. W tym celu przelatujemy się po wszystkich kontenerach, pomocne są
komendy:
```
    docker ps
    docker exec -it $id bash
```
Na każdym z kontenerów wykonujemy `ssh-keygen -t rsa -N "" -f
/root/.ssh/id_rsa`, po czym zapisujemy sobie gdzieś na boku zawartość pliku
`/root/.ssh/id_rsa.pub`. Po skończonej rundce zaczynamy drugą, tym razem
wklejając każdy klucz publiczny do pliku `/root/.ssh/authorized_keys` oraz
restartując ssh (`service ssh restart`).

Przy odrobinie szczęscia wszystko zadziała poprawnie gdy wykonamy:
```
    docker exec -it $(id kontenera z proxy) bash -c "masterha_manager --conf=/etc/mha_manager.cfg"
```

I, gdyby naszedł nas kaprys na ubicie kontenera z masterem, nasz poczciwy
manager wybierze jednego ze slave'ów na mastera

...po czym zakończy działanie (przynajmniej w przypadku 1 slave'a).

### 5. Known issues

* MHA jest nieprzetestowane na Windowsie.
* MHA kończy działanie po wywaleniu jednego mastera.

   Generalnie to nie jestem pewny czy to jest issue (albo jak duże to jest
   issue), na pewno zmiana tego zachowania będzie niesamowicie uciążliwa: MHA
   informacje o serwerach ściąga z pliku konfiguracyjnego, jeśli któryś z
   serwerów przestanie działać (albo chcemy dodać nowy), trzeba ponownie
   zmieniać config.

* Skrypt nie jest przystosowany do bycia uruchomionym kilkukrotnie (w celu stworzenia osobnych środowisk dla każdego mikroserwisu)

   Do poprawki na dniach.

* Windowsowy skrypt jest outdated

   ¯\_(ツ)\_/¯
