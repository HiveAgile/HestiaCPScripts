#!/bin/bash

source /usr/local/hestia/data/users/admin/user.conf
MONIT_DIR=/etc/monit/conf.d
clear
echo " "
echo -n "¿Deseas usar una contraseña aleatoria? (si/no): "
read respuesta

if [ "$respuesta" = "si" ]; then
  # Generar una contraseña aleatoria
  MONIT_PASSWORD=$(openssl rand -base64 12)
  echo "Tu contraseña aleatoria es: $MONIT_PASSWORD"
else
  # Solicitar una contraseña
  echo -n "Introduce tu contraseña: "
  read -s MONIT_PASSWORD
  echo
  echo "Has introducido: $MONIT_PASSWORD"
fi

# Exportar la contraseña como una variable de entorno
export MONIT_PASSWORD


if ! which monit > /dev/null; then
  echo "Monit no está instalado. Instalando..."
  
  # Actualizar la lista de paquetes disponibles
  sudo apt update

  # Instalar Monit
  sudo apt install monit -y
  systemctl enable monit
else
  echo "Monit ya está instalado."
fi


cat << EOF > $MONIT_DIR/web-interface

set httpd port 2812
use address $(curl -s ifconfig.me) #IP Pública de nuestro servidor Cloud
allow 0.0.0.0/0.0.0.0
allow 'admin':'$MONIT_PASSWORD' # usuario:contraseña cambiar estos datos por otros más seguros
EOF

## Monit PHP-FPM

echo "## PHP FPM" > $MONIT_DIR/php_fpm
for a in $(systemctl |grep -o "php...-fpm") ;do echo -e  "check process $a with pidfile /var/run/php/$a.pid\n  start program = \"/usr/sbin/service $a start\" with timeout 60 seconds\n  stop program  = \"/usr/sbin/service $a stop\"\n  if 3 restarts within 5 cycles then timeout\n\n";done >> $MONIT_DIR/php_fpm

## Monit SSH

cat << EOF > $MONIT_DIR/ssh
check process sshd with pidfile /var/run/sshd.pid
start program "/etc/init.d/ssh start"
stop program "/etc/init.d/ssh stop"
if failed port 22 protocol ssh then restart
if 3 restarts within 5 cycles then unmonitor
EOF

## Monit docker network

# Crear script para comprobar y crear red Docker 'web' si no existe
cat << 'EOF' > /usr/local/bin/check_or_create_docker_network_web.sh
#!/bin/bash

# Script proactivo: comprueba si la red Docker 'web' existe; si no, la crea.

if docker network inspect web > /dev/null 2>&1; then
  echo "✅ La red 'web' ya existe."
  exit 0
else
  echo "⚠️  La red 'web' no existe. Creándola..."
  docker network create --driver bridge web
  if [ $? -eq 0 ]; then
    echo "✅ Red 'web' creada correctamente."
    exit 0
  else
    echo "❌ Error al crear la red 'web'."
    exit 1
  fi
fi
EOF

# Dar permisos de ejecución al script
chmod +x /usr/local/bin/check_or_create_docker_network_web.sh

# Configurar Monit para ejecutar el script como programa de verificación proactiva
cat << EOF > $MONIT_DIR/docker_network_web
check program docker_network_web with path "/usr/local/bin/check_or_create_docker_network_web.sh"
  every 5 cycles
EOF

## Monit Docker is run.

cat << EOF > $MONIT_DIR/docker
check process docker with pidfile /var/run/docker.pid
  start program = "/bin/systemctl start docker"
  stop program  = "/bin/systemctl stop docker"
  if failed unixsocket /var/run/docker.sock then restart
  if 3 restarts within 5 cycles then unmonitor
  depends on backup_lock
EOF

cat << EOF > $MONIT_DIR/backup_lock
check file backup_lock with path /var/run/backup.pid
  if does exist then unmonitor
EOF

## Hestia Docker
cat << 'EOF' > /usr/local/bin/check_hestia_docker.sh
#!/bin/bash

# No hacer nada si hay un backup en curso
if [ -f /var/run/backup.pid ]; then
  echo "🔒 Backup en curso. No se controla el contenedor hestia-docker."
  exit 0
fi

# Verificar si el contenedor está corriendo
if docker ps --format '{{.Names}}' | grep -q '^hestia-docker$'; then
  echo "✅ Contenedor hestia-docker está en ejecución."
  exit 0
else
  echo "⚠️  Contenedor hestia-docker no está activo. Intentando arrancarlo..."
  docker start hestia-docker >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "✅ Contenedor hestia-docker arrancado correctamente."
    exit 0
  else
    echo "❌ Fallo al arrancar el contenedor hestia-docker."
    exit 1
  fi
fi
EOF

chmod +x /usr/local/bin/check_hestia_docker.sh

cat << EOF > $MONIT_DIR/hestia_docker
check program hestia_docker with path "/usr/local/bin/check_hestia_docker.sh"
  every 2 cycles
EOF


## Monit DNS
cat << EOF > $MONIT_DIR/named
check process named with pidfile /var/run/named/named.pid
 start program = "/etc/init.d/named start"
 stop program = "/etc/init.d/named stop"
 if failed host 127.0.0.1 port 53 type tcp protocol dns then restart
 if failed host 127.0.0.1 port 53 type udp protocol dns then restart
 if 3 restarts within 5 cycles then unmonitor
EOF

## Monit Exim

cat << EOF > $MONIT_DIR/exim4
 check process exim with pidfile /var/run/exim4/exim.pid
   group mail
   start program = "/etc/init.d/exim4 start"
   stop  program = "/etc/init.d/exim4 stop"
   if failed port 25 protocol smtp then restart
   depends on exim_bin
   depends on exim_rc

 check file exim_bin with path /usr/sbin/exim4
   group mail
   if failed checksum then unmonitor
   if failed permission 4755 then unmonitor
   if failed uid root then unmonitor
   if failed gid root then unmonitor

 check file exim_rc with path /etc/init.d/exim4
   group mail
   if failed checksum then unmonitor
   if failed permission 755 then unmonitor
   if failed uid root then unmonitor
   if failed gid root then unmonitor 
EOF

## MySQL

cat << EOF > $MONIT_DIR/MySQL
check process mariadb with pidfile /run/mysqld/mysqld.pid
start program = "/etc/init.d/mariadb start"
stop program = "/etc/init.d/mariadb stop"
if failed host 127.0.0.1 port 3306 then restart
if 3 restarts within 5 cycles then unmonitor
EOF

## MySQL error Log Monit
cat << EOF > $MONIT_DIR/mysql_error
check file error.log with path /var/log/mysql/error.log
if size > 100 MB then alert
EOF

## Monit Disk Space

cat << EOF > $MONIT_DIR/disco
check filesystem "root" with path $(df / | awk 'NR==2{print $1}')
if space usage > 80% for 8 cycles then alert
if space usage > 99% then stop #para nuestro servidor para evitar que se llene
if inode usage > 80% for 8 cycles then alert
if inode usage > 99% then stop #para nuestro servidor para evitar que se llene 
EOF

## Monit Hestia Panel
cat << EOF > $MONIT_DIR/hestia_panel
check process hestia-panel with pidfile /var/run/hestia-nginx.pid
    start program = "/usr/bin/systemctl start hestia"
    stop program  = "/usr/bin/systemctl stop hestia"
EOF

## Monit NGINX
cat << EOF > $MONIT_DIR/nginx
check process nginx with pidfile /var/run/nginx.pid
  start program = "/usr/sbin/service nginx start" with timeout 60 seconds
  stop program  = "/usr/sbin/service nginx stop"
  if failed port 8084 protocol http for 3 cycles then restart
  if failed url http://localhost:8084/ and content = "Active connections:" then alert
EOF



## SMTP Config
cat << EOF > /etc/monit/monitrc
set log /var/log/monit.log
set idfile /var/lib/monit/id
set statefile /var/lib/monit/state

set daemon 120

set eventqueue
    basedir /var/lib/monit/events
    slots 100                     

set mailserver mail.hiveagile.club port 587
    username "monitor@hiveagile.club"
    password "ZRNaLVqZl0619DxJ"
    using tls
    with timeout 30 seconds

set mail-format {
    from: monitor@hiveagile.club
    subject: monit alert -- \$EVENT \$SERVICE
    message: \$EVENT Service \$SERVICE
    Date: \$DATE
    Action: \$ACTION
    Host: \$HOST
    Description: \$DESCRIPTION
    Monit HiveAgile
}

set alert $CONTACT

include /etc/monit/conf.d/*
include /etc/monit/conf-enabled/*

EOF

## Abrir Puerto

v-add-firewall-rule accept 0.0.0.0/0 2812 tcp Monit

## Reload Config
monit reload
clear
echo " "
echo "########## Datos ############"
echo " "
echo "http://"$(hostname -I|awk {'print $1'})":2812"
echo "Usuario: admin"
echo "Password: $MONIT_PASSWORD"

sleep 2; for a in $(systemctl |grep -o php...-fpm);do monit monitor $a ;done

echo " "
echo "Presiona Enter para continuar..."
read
echo "Continuando..."
