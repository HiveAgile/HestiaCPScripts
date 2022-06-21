#!/bin/bash
clear
echo -e "\x1b[41;45m CAMBIANDO TIMEZONE Europe/Madrid \x1b[m"
v-change-sys-timezone Europe/Madrid
echo " "
echo -e "\x1b[41;45m ACTIVANDO ACTUALIZACIONES AUTOMÁTICAS \x1b[m"
v-add-cron-hestia-autoupdate
v-change-sys-config-value 'UPGRADE_SEND_EMAIL_LOG' 'true'
echo " "
echo -e "\x1b[41;45m INSTALANDO RAINLOOP COMO GESTOR DE CORREO \x1b[m"
v-add-sys-rainloop
echo " "
echo -e "\x1b[41;45m CONFIGURANDO IDIOMA ESPAÑOL POR DEFECTO \x1b[m"
v-change-user-language admin es
v-change-sys-language 'es' 'yes'
v-change-sys-config-value 'POLICY_USER_VIEW_SUSPENDED' ''
echo " "
echo -e "\x1b[41;45m ACTIVANDO SOPORTE PARA PHP 7.2 \x1b[m"
v-add-web-php '7.2'
v-restart-service 'apache2' ''
echo " "
echo -e "\x1b[41;45m ACTIVANDO SOPORTE PARA PHP 7.3 \x1b[m"
v-add-web-php '7.3'
v-restart-service 'apache2' ''
echo " "
echo -e "\x1b[41;45m ACTIVANDO SOPORTE PARA PHP 7.4 \x1b[m"
v-add-web-php '7.4'
v-restart-service 'apache2' ''
echo " "
echo -e "\x1b[41;45m ACTIVANDO SOPORTE PARA PHP 8.1 \x1b[m"
v-add-web-php '8.1'
v-restart-service 'php7.2-fpm'
v-restart-service 'php7.3-fpm'
v-restart-service 'php7.4-fpm'
v-restart-service 'php8.0-fpm'
v-restart-service 'php8.1-fpm'
echo " "
echo -e "\x1b[41;45m SETEANDO PHP 8.0 COMO VERSIÓN POR DEFECTO \x1b[m"
v-change-sys-php '8.0'
echo " "
echo -e "\x1b[41;45m ACTIVANDO QUOTAS DE USUARIO \x1b[m"
v-update-user-quota 'admin'
v-add-sys-quota 
echo " "
echo -e "\x1b[41;45m APLICANDO CONFIGURACIÓN POR DEFECTO PHP \x1b[m"
cat << EOF > /tmp/php.txt 
memory_limit = 256M
post_max_size = 150M
upload_max_filesize = 150M
short_open_tag = On
max_execution_time = 500
expose_php = Off
date.timezone = "Europe/Madrid"
disabled_functions = mail
EOF
v-change-sys-service-config  '/tmp/php.txt' 'php' 'yes'
