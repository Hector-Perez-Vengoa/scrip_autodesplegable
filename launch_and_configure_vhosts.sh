#!/bin/bash
# ==========================================
# Script para configurar 2 VirtualHosts en Amazon Linux 2023
# Autor: Héctor Pérez Vengoa
# Fecha: 2025-10-06
# ==========================================

DOM1="gx26.asesoresti.net"
DOM2="gy26.asesoresti.net"

echo "==> Actualizando paquetes..."
sudo dnf update -y

echo "==> Instalando Apache (httpd)..."
sudo dnf install -y httpd

echo "==> Habilitando y arrancando servicio..."
sudo systemctl enable httpd
sudo systemctl start httpd

echo "==> Creando directorios de los dominios..."
sudo mkdir -p /var/www/$DOM1/public_html
sudo mkdir -p /var/www/$DOM2/public_html

echo "==> Asignando propietario actual..."
sudo chown -R $USER:$USER /var/www/$DOM1/public_html
sudo chown -R $USER:$USER /var/www/$DOM2/public_html
sudo chmod -R 755 /var/www

echo "==> Creando index.html del primer dominio..."
cat <<EOF | sudo tee /var/www/$DOM1/public_html/index.html > /dev/null
<html>
  <head>
    <title>Bienvenido a $DOM1!</title>
  </head>
  <body>
    <h1>El Virtual Host $DOM1 está funcionando!</h1>
  </body>
</html>
EOF

echo "==> Copiando index.html para el segundo dominio..."
sudo cp /var/www/$DOM1/public_html/index.html /var/www/$DOM2/public_html/index.html
sudo sed -i "s/$DOM1/$DOM2/g" /var/www/$DOM2/public_html/index.html

echo "==> Creando configuración de VirtualHosts..."
sudo tee /etc/httpd/conf.d/$DOM1.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin admin@$DOM1
    ServerName $DOM1
    DocumentRoot /var/www/$DOM1/public_html
    ErrorLog /var/log/httpd/$DOM1-error.log
    CustomLog /var/log/httpd/$DOM1-access.log combined
</VirtualHost>
EOF

sudo tee /etc/httpd/conf.d/$DOM2.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin admin@$DOM2
    ServerName $DOM2
    DocumentRoot /var/www/$DOM2/public_html
    ErrorLog /var/log/httpd/$DOM2-error.log
    CustomLog /var/log/httpd/$DOM2-access.log combined
</VirtualHost>
EOF

echo "==> Verificando configuración de Apache..."
sudo apachectl configtest

echo "==> Reiniciando Apache..."
sudo systemctl restart httpd

echo "==> Instalando curl..."
sudo dnf install -y curl

echo "==> Probando dominios..."
curl $DOM1
curl $DOM2

echo "✅ Configuración completada exitosamente en Amazon Linux 2023."
