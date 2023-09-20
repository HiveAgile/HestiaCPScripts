#!/bin/bash
# Ruta del archivo de configuración
CONFIG_FILE="/etc/docker-backup.conf"
RESTORE_DOCKERS=/usr/bin/restaurar_dockers

if [ ! -f $RESTORE_DOCKERS ]; then
wget -q -O /usr/bin/restaurar_dockers https://gist.githubusercontent.com/aitorroma/77c2d98354260773969e23e4ea817239/raw/7981f96355e79219ced46129aa7eb3c7a8b31b7a/restaura.sh && chmod +x /usr/bin/restaurar_dockers
fi

# Verificar si el archivo de configuración existe
if [ ! -f $CONFIG_FILE ]; then
  echo "El archivo de configuración no existe. Creando uno nuevo..."
  
  # Crear el archivo de configuración con valores predeterminados
  echo "# Retención de copias de seguridad (en días)" > $CONFIG_FILE
  echo "LOCAL_RETENTION=3" >> $CONFIG_FILE
  echo "REMOTE_RETENTION=30" >> $CONFIG_FILE
  
  # Preguntar al usuario si desea habilitar las notificaciones de Telegram
  read -p "¿Quieres habilitar las notificaciones de Telegram? (s/n): " enable_telegram
  enable_telegram=$(echo "$enable_telegram" | tr '[:upper:]' '[:lower:]')  # Convertir a minúsculas
  if [ "$enable_telegram" == "s" ]; then
    read -p "Introduce tu token de Telegram: " TOKEN
    read -p "Introduce tu chat ID de Telegram: " CHAT_ID
    
    # Añadir las variables de Telegram al archivo de configuración
    echo "TOKEN=\"$TOKEN\"" >> $CONFIG_FILE
    echo "CHAT_ID=\"$CHAT_ID\"" >> $CONFIG_FILE
  fi
fi

# Cargar las variables desde el archivo de configuración

source $CONFIG_FILE

URL="https://api.telegram.org/bot$TOKEN/sendMessage"

# Función para enviar mensajes a Telegram
send_telegram_message() {
  local message="$1"
  curl -s -X POST $URL -d chat_id="$CHAT_ID" -d text="$message" --data-urlencode "disable_web_page_preview=true" --data-urlencode "parse_mode=markdown" &>/dev/null
}


# Verificar si el archivo de configuración existe
if [ -f ~/.config/rclone/rclone.conf ]; then
  
  # Verificar si la sección [eu2] ya existe en el archivo de configuración
  if grep -q "\[eu2\]" ~/.config/rclone/rclone.conf; then
  :  # no hacer nada
  else
    echo ""
    # Pedir al usuario las claves de acceso
    read -p "Introduce tu Access Key ID: " access_key_id
    read -p "Introduce tu Secret Access Key: " secret_access_key

    # Añadir la nueva configuración al final del archivo existente
    echo "
[eu2]
type = s3
provider = Ceph
env_auth = false
access_key_id = $access_key_id
secret_access_key = $secret_access_key
endpoint = https://eu2.contabostorage.com" >> ~/.config/rclone/rclone.conf

    echo "Sección [eu2] añadida exitosamente al archivo de configuración."
  fi
else
  echo "El archivo de configuración de rclone no existe. Instalando rclone..."

  # Instalar rclone (Ajusta este comando según tu sistema operativo)
  sudo apt update
  sudo apt install rclone -y

  # Crear el directorio de configuración si no existe
  mkdir -p ~/.config/rclone

  # Pedir al usuario las claves de acceso
  read -p "Introduce tu Access Key ID: " access_key_id
  read -p "Introduce tu Secret Access Key: " secret_access_key

  # Generar el archivo de configuración
  echo "[eu2]
type = s3
provider = Ceph
env_auth = false
access_key_id = $access_key_id
secret_access_key = $secret_access_key
endpoint = https://eu2.contabostorage.com" > ~/.config/rclone/rclone.conf

  echo "Archivo de configuración de rclone creado exitosamente."
fi


# Nombre del bucket que quieres crear
BUCKET_NAME="dockers"

# Nombre de la configuración remota en rclone
REMOTE_NAME="eu2"

# Verificar si el bucket ya existe
if rclone lsd ${REMOTE_NAME}: | grep -q "${BUCKET_NAME}"; then
  echo ""
else
  echo "El bucket ${BUCKET_NAME} no existe. Creando..."
  
  # Crear el nuevo bucket
  rclone mkdir ${REMOTE_NAME}:${BUCKET_NAME}
  
  if [ $? -eq 0 ]; then
    echo "Bucket ${BUCKET_NAME} creado exitosamente."
  else
    echo "Error al crear el bucket ${BUCKET_NAME}."
  fi
fi

# Comprueba si 'parallel' está instalado y, si no, lo instala
if ! command -v parallel &> /dev/null; then
  echo "GNU Parallel no está instalado. Instalando..."
  apt update && apt install -y parallel
fi

# Función para comprobar si un contenedor está en funcionamiento
check_running_containers() {
  cd "$1"
  if docker-compose ps 2>/dev/null | grep -q 'Up'; then
    echo "$1"
  fi
}

# Exporta la función para que esté disponible para GNU Parallel
export -f check_running_containers

# Directorio base que contiene los contenedores
CONTAINERS_DIR="/root/containers"

# Utiliza GNU Parallel para ejecutar la función en cada subdirectorio y almacena los resultados en un array
readarray -t running_containers_dirs < <(find $CONTAINERS_DIR -name docker-compose.yml -exec dirname {} \; | parallel -j 0 --no-notice check_running_containers)



# Recorre cada directorio con contenedores en funcionamiento
for dir in "${running_containers_dirs[@]}"; do
  cd $dir
  docker-compose stop
done

# Elimina copias de seguridad locales antiguas
find $BACKUP_DIR -name "docker-backup_$HOSTNAME-*.tar.gz" -mtime +$LOCAL_RETENTION -exec rm {} \;


# Función para realizar la copia de seguridad de todos los contenedores
backup_containers() {
  # Detecta todos los directorios que podrían contener archivos de Docker
  readarray -t all_docker_dirs < <(find /root/containers -mindepth 1 -maxdepth 1 -type d)
  
  # Fecha de la copia de seguridad
  backupDate=$(date +'%F')
  echo "Fecha de la copia de seguridad: $backupDate"

  # Directorio donde se almacenarán las copias de seguridad
  BACKUP_DIR="/backups/docker"

  # Crea el directorio de copia de seguridad si no existe
  mkdir -p $BACKUP_DIR

  # Realiza la copia de seguridad
  cd $BACKUP_DIR
  tar -czvf docker-backup_$HOSTNAME-$backupDate.tar.gz ${all_docker_dirs[@]}
  if [ $? -eq 0 ]; then

    backup_size=$(du -h docker-backup_$HOSTNAME-$backupDate.tar.gz | awk '{print $1}')

    echo "Copia de seguridad realizada con éxito."
    send_telegram_message "🎉 Copia de seguridad completada con éxito en $HOSTNAME.Tamaño: $backup_size."
  else
    echo "Error al realizar la copia de seguridad."
    send_telegram_message "⚠️ Error al realizar la copia de seguridad en $HOSTNAME."
    exit 1
  fi
}

# Llama a la función para realizar la copia de seguridad
backup_containers

# Reinicia los contenedores
for dir in "${running_containers_dirs[@]}"; do
  cd $dir
  docker-compose start
done

echo "La copia de seguridad local se ha completado en ${BACKUP_DIR}/docker-backup_$HOSTNAME-$backupDate.tar.gz"

echo " "
echo "Sincronizando remoto"

# Usa rclone para copiar en el almacenamiento remoto y eliminar copias de seguridad antiguas
rclone copy -P $(find $BACKUP_DIR -type f  -ls |tail -n 1 |rev |awk {'print $1'}|rev) eu2:/dockers

if [ $? -eq 0 ]; then
    send_telegram_message "🎉 Copia de seguridad de $HOSTNAME subida con éxito al almacenamiento en la nube."
else
    send_telegram_message "⚠️ Error al subir la copia de seguridad de $HOSTNAME al almacenamiento en la nube."
    echo "Error al realizar la copia de seguridad."
    send_telegram_message "⚠️ Error al realizar la copia de seguridad en $HOSTNAME."
    exit 1
fi

echo " "
echo "Borrando backups viejos"
rclone delete eu2:/dockers --min-age=${REMOTE_RETENTION}d
