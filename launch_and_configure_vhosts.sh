#!/bin/bash
# ==========================================
# Script de configuración automática de Apache2 con 2 VirtualHosts
# Autor: Héctor Pérez Vengoa
# Fecha: 2025-10-06
# ==========================================

# Variables de dominio
DOM1="gx.asesoresti.net"
DOM2="gx2.asesoresti.net"

echo "==> Actualizando paquetes..."
sudo apt update -y

echo "==> Instalando Apache2..."
sudo apt install -y apache2

echo "==> Creando directorios de los dominios..."
sudo mkdir -p /var/www/$DOM1/public_html
sudo mkdir -p /var/www/$DOM2/public_html

echo "==> Asignando propietario actual a las carpetas..."
sudo chown -R $USER:$USER /var/www/$DOM1/public_html
sudo chown -R $USER:$USER /var/www/$DOM2/public_html

echo "==> Ajustando permisos..."
sudo chmod -R 755 /var/www

echo "==> Creando index.html del primer dominio..."
cat <<EOF | sudo tee /var/www/$DOM1/public_html/index.html > /dev/null
<html>
  <head>
    <title>Bienvenido a $DOM1!</title>
  </head>
  <body>
    <h1>El Virtual Host $DOM1 funcionando!</h1>
  </body>
</html>
EOF

echo "==> Copiando y modificando index.html para el segundo dominio..."
sudo cp /var/www/$DOM1/public_html/index.html /var/www/$DOM2/public_html/index.html
sudo sed -i "s/$DOM1/$DOM2/g" /var/www/$DOM2/public_html/index.html

echo "==> Creando archivo de configuración para $DOM1..."
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/$DOM1.conf

sudo tee /etc/apache2/sites-available/$DOM1.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin admin@$DOM1
    ServerName $DOM1
    ServerAlias $DOM1
    DocumentRoot /var/www/$DOM1/public_html
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

echo "==> Creando archivo de configuración para $DOM2..."
sudo cp /etc/apache2/sites-available/$DOM1.conf /etc/apache2/sites-available/$DOM2.conf
sudo sed -i "s/$DOM1/$DOM2/g" /etc/apache2/sites-available/$DOM2.conf

echo "==> Habilitando sitios..."
sudo a2ensite $DOM1.conf
sudo a2ensite $DOM2.conf

echo "==> Deshabilitando el sitio por defecto..."
sudo a2dissite 000-default.conf

echo "==> Verificando configuración de Apache..."
sudo apache2ctl configtest

echo "==> Reiniciando servicio de Apache..."
sudo systemctl restart apache2

echo "==> Instalando curl..."
sudo apt install -y curl

echo "==> Probando acceso a los dominios..."
curl $DOM1
curl $DOM2

echo "✅ Configuración completada exitosamente."
