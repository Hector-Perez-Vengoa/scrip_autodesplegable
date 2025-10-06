#!/usr/bin/env bash
set -euo pipefail

############################################
# >>> CONFIGURA ESTAS VARIABLES <<<
############################################
REGION="us-east-1"

# Nombre, Key Pair y Security Group existentes (según tu consigna)
INSTANCE_NAME="dsn5c-lab07-gdiaz-ec2-www"
KEY_NAME="dsn5c-lab07-gdiaz-kp-login"
SG_NAME="dsn5a-lab07-gdiaz-sg-sshttps"   # Debe permitir al menos TCP 22 (opcional) y TCP 80

# Subdominios (ajusta a los que quieras usar)
SUB1="gx06.asesoresti.net"
SUB2="gx60.asesoresti.net"

# Emails de admin para los VirtualHosts (opcional)
ADMIN1="admin@${SUB1}"
ADMIN2="admin@${SUB2}"

# Tipo de instancia
INSTANCE_TYPE="t2.micro"

# Subred: si no indicas, usará una subred por defecto de tu VPC default
SUBNET_ID=""   # opcional: "subnet-xxxxxxxx"; dejar vacío para que AWS elija

############################################
# No edites abajo salvo que sepas qué haces
############################################

echo "==> Región: $REGION"
aws configure set region "$REGION" >/dev/null

# Obtiene la AMI más reciente de Ubuntu 22.04 LTS desde SSM Parameter Store (oficial)
echo "==> Obteniendo AMI Ubuntu 22.04 LTS desde SSM..."
UBUNTU_AMI="$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id \
  --query 'Parameter.Value' --output text)"
echo "AMI: $UBUNTU_AMI"

# Busca el Security Group ID por nombre
echo "==> Buscando Security Group ID para '$SG_NAME'..."
SG_ID="$(aws ec2 describe-security-groups --group-names "$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  echo "ERROR: No se encontró el Security Group con nombre '$SG_NAME' en $REGION"
  exit 1
fi
echo "SG_ID: $SG_ID"

# Construye el script de User Data (cloud-init) para configurar Apache y VHosts
echo "==> Generando user-data..."
USER_DATA=$(cat <<'EOF'
#cloud-config
runcmd:
  - bash -lc 'export DEBIAN_FRONTEND=noninteractive'
  - bash -lc 'apt-get update -y && apt-get install -y apache2 curl'
  # Crear carpetas para ambos subdominios
  - bash -lc 'mkdir -p /var/www/__SUB1__/public_html'
  - bash -lc 'mkdir -p /var/www/__SUB2__/public_html'
  # Propietario (para editar como usuario ubuntu); Apache en Ubuntu corre como www-data, pero lectura es suficiente
  - bash -lc 'chown -R ubuntu:ubuntu /var/www/__SUB1__/public_html'
  - bash -lc 'chown -R ubuntu:ubuntu /var/www/__SUB2__/public_html'
  - bash -lc 'chmod -R 755 /var/www'
  # index.html para SUB1
  - bash -lc "cat >/var/www/__SUB1__/public_html/index.html <<HTML
<html>
  <head><title>Bienvenido a __SUB1__!</title></head>
  <body>
    <h1>El Virtual Host __SUB1__ está funcionando!</h1>
  </body>
</html>
HTML"
  # index.html para SUB2
  - bash -lc "cat >/var/www/__SUB2__/public_html/index.html <<HTML
<html>
  <head><title>Bienvenido a __SUB2__!</title></head>
  <body>
    <h1>El Virtual Host __SUB2__ está funcionando!</h1>
  </body>
</html>
HTML"
  # VirtualHost SUB1
  - bash -lc "cat >/etc/apache2/sites-available/__SUB1__.conf <<APACHECONF
<VirtualHost *:80>
    ServerAdmin __ADMIN1__
    ServerName __SUB1__
    ServerAlias __SUB1__
    DocumentRoot /var/www/__SUB1__/public_html
    ErrorLog \${APACHE_LOG_DIR}/__SUB1___error.log
    CustomLog \${APACHE_LOG_DIR}/__SUB1___access.log combined
</VirtualHost>
APACHECONF"
  # VirtualHost SUB2
  - bash -lc "cat >/etc/apache2/sites-available/__SUB2__.conf <<APACHECONF
<VirtualHost *:80>
    ServerAdmin __ADMIN2__
    ServerName __SUB2__
    ServerAlias __SUB2__
    DocumentRoot /var/www/__SUB2__/public_html
    ErrorLog \${APACHE_LOG_DIR}/__SUB2___error.log
    CustomLog \${APACHE_LOG_DIR}/__SUB2___access.log combined
</VirtualHost>
APACHECONF"
  # Habilitar sitios y deshabilitar el default
  - bash -lc 'a2ensite __SUB1__.conf'
  - bash -lc 'a2ensite __SUB2__.conf'
  - bash -lc 'a2dissite 000-default.conf || true'
  # Probar configuración y reiniciar Apache
  - bash -lc 'apache2ctl configtest'
  - bash -lc 'systemctl reload apache2 || systemctl restart apache2'
EOF
)

# Reemplazar placeholders por los valores reales
USER_DATA="${USER_DATA//__SUB1__/$SUB1}"
USER_DATA="${USER_DATA//__SUB2__/$SUB2}"
USER_DATA="${USER_DATA//__ADMIN1__/$ADMIN1}"
USER_DATA="${USER_DATA//__ADMIN2__/$ADMIN2}"

# Si no hay SUBNET_ID, dejamos que AWS elija una por defecto
EXTRA_NET_ARGS=()
if [[ -n "$SUBNET_ID" ]]; then
  EXTRA_NET_ARGS+=(--subnet-id "$SUBNET_ID" --associate-public-ip-address)
else
  EXTRA_NET_ARGS+=(--associate-public-ip-address)
fi

echo "==> Lanzando instancia EC2 Ubuntu con User Data para Apache+VHosts..."
RUN_JSON="$(aws ec2 run-instances \
  --image-id "$UBUNTU_AMI" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  "${EXTRA_NET_ARGS[@]}" \
  --user-data "$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query 'Instances[0].{Id:InstanceId}' --output json)"

INSTANCE_ID="$(echo "$RUN_JSON" | jq -r '.Id')"
if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "null" ]]; then
  echo "ERROR: No se pudo lanzar la instancia."
  exit 1
fi
echo "InstanceId: $INSTANCE_ID"

echo "==> Esperando a que la instancia esté running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

echo "==> Obteniendo IP pública..."
PUBLIC_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
echo "Public IP: $PUBLIC_IP"

echo
echo "======================================================="
echo " La instancia '$INSTANCE_NAME' está lista."
echo " IP pública:  $PUBLIC_IP"
echo " Subdominios: $SUB1  |  $SUB2"
echo "======================================================="
echo
echo ">> Prueba local (antes de crear DNS) con Host header:"
echo "curl -H 'Host: $SUB1' http://$PUBLIC_IP/"
echo "curl -H 'Host: $SUB2' http://$PUBLIC_IP/"
echo
echo ">> Luego crea 2 registros DNS tipo A en tu zona:"
echo "  $SUB1  -> $PUBLIC_IP"
echo "  $SUB2  -> $PUBLIC_IP"
echo
echo ">> Después podrás probar por nombre:"
echo "curl http://$SUB1/"
echo "curl http://$SUB2/"
