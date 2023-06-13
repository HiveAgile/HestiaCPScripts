#!/bin/bash

## Generar Fichero de credenciales.

config_file="/etc/uptime-kuma.ini"

# Verificar si el archivo de configuración existe
if [ -f "$config_file" ]; then
  source $config_file
else
  clear
  echo "Introduce el API_HOST de Uptime Kuma"
  echo " "

  # Solicitar las variables de configuración al usuario
  read -p "API_HOST: " api_host
  read -p "API_USER: " api_user
  read -s -p "API_PASSWORD: " api_password
  echo

  # Crear el archivo de configuración con las variables ingresadas
  echo "API_HOST=$api_host" > "$config_file"
  echo "API_USER=$api_user" >> "$config_file"
  echo "API_PASSWORD=$api_password" >> "$config_file"
  chmod 600 $config_file
  
  (crontab -l 2>/dev/null; echo "0 * * * * /usr/bin/bash /etc/monitor.sh") | crontab -

  source $config_file
fi

## Obtener el Token

TOKEN=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" --data "username=$API_USER&password=$API_PASSWORD" $API_HOST/login/access-token | jq -r ".access_token")
# Obtener el nombre del host
host_name=$(hostname)

# Realizar la petición GET para obtener la lista de etiquetas
response=$(curl -s -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOKEN}" $API_HOST/tags)

# Obtener el ID de la etiqueta si $host_name está presente en name
tag_id=$(echo "$response" | jq -r '.tags[] | select(.name == "'"$host_name"'") | .id')

if [ -n "$tag_id" ]; then
  echo "La etiqueta con el nombre $host_name ya existe. ID de la etiqueta: $tag_id"
else
  echo "La etiqueta con el nombre $host_name no existe. Insertando etiqueta..."

  # Realizar la petición POST para insertar la etiqueta solo si no existe previamente
  insert_response=$(curl -s -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOKEN}" -d '{ "name": "'"$host_name"'", "color": "#059669"}' $API_HOST/tags)

  # Obtener el ID de la etiqueta insertada
  tag_id=$(echo "$insert_response" | jq -r '.id')

  echo "Etiqueta insertada. ID de la etiqueta: $tag_id"
fi

# Registrar máquinas

output_file="/tmp/domains.txt"

# Obtener la lista de dominios desde la API de UptimeKuma solo si el archivo no existe
if [ ! -f "$output_file" ]; then
  curl -s -L -H 'Accept: application/json' -H "Authorization: Bearer ${TOKEN}" $API_HOST/monitors/ | jq -r '.monitors[].name' | tr -d '\"' > "$output_file"
fi

# Verificar la existencia de HestiaCP
if dpkg -s hestia &> /dev/null; then
  # HestiaCP está instalado

  for domain in /home/*/web/*; do
    if [ -d "$domain" ]; then
      domain_name=$(basename "$domain")

      # Validar si el dominio ya existe en el archivo
      if grep -q "^${domain_name}$" "$output_file"; then
        echo "El dominio $domain_name ya existe en el archivo."
      else
        echo "Agregando el dominio $domain_name"

        # Agregar el dominio al archivo
        echo "$domain_name" >> "$output_file"

        # Realizar la petición para agregar el host en UptimeKuma
        response=$(curl -s -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOKEN}" -d '{
          "type": "http",
          "name": "'"$domain_name"'",
          "interval": 60,
          "maxretries": 3,
          "url": "https://'"$domain_name"'"
        }' $API_HOST/monitors)

        # Capturar el monitorID de la respuesta JSON
        monitor_id=$(echo "$response" | jq -r '.monitorID')

        if [ -n "$monitor_id" ]; then
          echo "Monitor ID: $monitor_id"

          # Realizar la petición para agregar la etiqueta (tag)
          curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN}" -d '{ "tag_id": '$tag_id' }' "$API_HOST/monitors/$monitor_id/tag"
        fi
      fi
    fi
  done

else
  echo "⚠️ HestiaCP no está instalado"

  # Verificar la existencia de Traefik en Docker
  if [ $(docker ps -a | grep traefik | wc -l) -gt 0 ]; then
    echo "✅ Traefik ha sido detectado"
    
    # Obtener el path de acme.json de Traefik
    ACME_JSON=$(docker inspect traefik | jq -r '.[].HostConfig.Binds' | grep acme.json | cut -d ":" -f 1 | tr -d \" | awk {'print $1'})

    # Extraer los dominios de acme.json
    DOMAINS=$(jq .Certificates[].Domain.Main $ACME_JSON | tr -d \")
    
    # Recorrer los dominios obtenidos de Traefik
    for domain in $DOMAINS; do
      echo "Agregando el dominio $domain"

      # Validar si el dominio ya existe en el archivo
      if grep -q "^${domain}$" "$output_file"; then
        echo "El dominio $domain ya existe en el archivo."
      else
        # Agregar el dominio al archivo
        echo "$domain" >> "$output_file"

        # Realizar la petición para agregar el host en UptimeKuma
        response=$(curl -s -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOKEN}" -d '{
          "type": "http",
          "name": "'"$domain"'",
          "interval": 60,
          "maxretries": 3,
          "url": "https://'"$domain"'"
        }' $API_HOST/monitors)

        # Capturar el monitorID de la respuesta JSON
        monitor_id=$(echo "$response" | jq -r '.monitorID')

        if [ -n "$monitor_id" ]; then
          echo "Monitor ID: $monitor_id"

          # Realizar la petición para agregar la etiqueta (tag)
          curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN}" -d '{ "tag_id": '$tag_id' }' "$API_HOST/monitors/$monitor_id/tag"
        fi
      fi
    done

  else
    echo "❌ No he detectado ni HestiaCP ni Traefik instalado"
  fi
fi

## Borrar log
\rm "$output_file"
