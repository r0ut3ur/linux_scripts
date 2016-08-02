#!/bin/bash
# Skydoo Security
# VideoSurveillance
# 
# Thibault Smeyers - 07/2016
# GPL
#
# Syntaxe: # sudo ./postinstall.sh
# Penser à verifier la version de PHP pour le PATH :)

VERSION="0.1"
#HOME_PATH=`grep $USERNAME /etc/passwd | awk -F':' '{ print $6 }'`
MYSQL_ROOT_PASSWORD=PASSWORD_HERE

#=============================================================================
# Liste des applications à installer
LISTE=""
# LAMP
LISTE=$LISTE" apache2 php mysql-server libapache2-mod-php php-mysql"
# ZoneMinder
LISTE=$LISTE" zoneminder php-gd"

#=============================================================================

# Test que le script est lance en root
if [ $EUID -ne 0 ]; then
  echo "Le script doit être lancé en root !" 1>&2
  exit 1
fi

# Mise a jour du systeme
#-----------------------

echo "Mise a jour du systeme"

# Update
apt update 2>&1 | grep NO_PUBKEY | perl -pwe 's#^.+NO_PUBKEY (.+)$#$1#' | xargs apt-key adv --recv-keys --keyserver keyserver.ubuntu.com

# Upgrade
apt dist-upgrade

# Installations de logiciels
#---------------------------

echo "Installation des logiciels suivants: $LISTE"

apt -y install $LISTE

# Configuration de LAMP
#----------------------

# Remplacement du fichier my.cnf (Suppression des valeurs pré-configurées)
rm /etc/mysql/my.cnf
cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/my.cnf

# Modification du fichier my.cnf pour ZM
sed -i "/\[mysqld\]/a 'sql_mode = NO_ENGINE_SUBSTITUTION'" /etc/mysql/my.cnf

# Redemarrage de MySQL pour appliquer les changements
systemctl restart mysql

# Automatisation de mysql_secure_installation
apt -y install expect

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter password for user root:\"
send \"$MYSQL_ROOT_PASSWORD\r\"
expect \"Press y|Y for Yes, any other key for No:\"
send \"n\r\"
expect \"Change the password for root ?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")

echo "$SECURE_MYSQL"

# Creation des bases de donnees pour ZoneMinder
#----------------------------------------------

mysql -uroot -p$MYSQL_ROOT_PASSWORD < /usr/share/zoneminder/db/zm_create.sql
mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "grant all on zm.* to 'zmuser'@localhost identified by 'zmpass';"
mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD reload

# Creation d'un nouvel utilisateur
#---------------------------------

adduser www-data video

# Application de permissions pour Apache et ajout de modules
#-----------------------------------------------------------

chmod 740 /etc/zm/zm.conf
chown root:www-data /etc/zm/zm.conf

a2enmod cgi
a2enconf zoneminder
a2enmod rewrite

# Fix sur les permissions, et pour un bon fonctionnement de l'API
#----------------------------------------------------------------

chown -R www-data:www-data /usr/share/zoneminder/

#<Directory /usr/share>
#	AllowOverride All
#	Require all granted
#</Directory>
#<Directory /var/www/>
#	Options Indexes FollowSymLinks
#	AllowOverride All
#	Require all granted
#</Directory>
sed -i ':a;N;$!ba;s/AllowOverride None/AllowOverride All/2' /etc/apache2/apache2.conf
sed -i ':a;N;$!ba;s/AllowOverride None/AllowOverride All/2' /etc/apache2/apache2.conf

# Demarrage de ZoneMinder
#------------------------

systemctl enable zoneminder
service zoneminder start

# TimeZone PHP
#-------------

sed -i ':a;N;$!ba;s/;date.timezone =/date.timezone = Europe\/Brussels/' /etc/php/7.0/apache2/php.ini
service apache2 reload

# Nettoyage
#----------

apt -y purge expect
apt autoremove
apt autoclean

echo "========================================================================"
echo
echo "Liste des logiciels installés: $LISTE"
echo "ZoneMinder est installe, et accessible sur http://ip_de_la_box/zm/"
echo
echo "========================================================================"

# Fin du script
#---------------
