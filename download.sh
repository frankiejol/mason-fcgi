#!/bin/bash

set -e

echo "WARNING: I will download and overwrite those files:"

grep wget $0 | grep -v grep | awk -Fmaster '{ print "\t" $2 }'

while [ "$ok" != "y"  -a  "$ok" != "Y" ]; do
	echo -n "Shall I go ahead [y/N]: "
	read -e ok
	if [ "$ok" == "" ]; then
		ok="n"
	fi
	if [ "$ok" == "n"  -o  "$ok" == "N" ]; then
		echo "quitting"
		exit
	fi
done

echo "Downloading"

cd /etc/init.d/
wget http://github.com/frankiejol/mason-fcgi/raw/master/etc/init.d/fcgi
chmod +x fcgi
cd /etc/default/
wget http://github.com/frankiejol/mason-fcgi/raw/master/etc/default/fcgi
mkdir -p /var/www/mason
cd /var/www/mason
wget http://github.com/frankiejol/mason-fcgi/raw/master/var/www/mason/mason_fcgi.pl
chmod +x mason_fcgi.pl
mkdir /var/run/fcgi
chown www-data /var/run/fcgi
mkdir /var/log/nginx/fcgi
chown www-data /var/log/nginx/fcgi
mkdir /var/www/mason/workspace
chown www-data /var/www/mason/workspace
cd /etc/nginx
wget http://github.com/frankiejol/mason-fcgi/raw/master/etc/nginx/nginx-fcgi.conf
cd sites-available
wget http://github.com/frankiejol/mason-fcgi/raw/master/etc/nginx/sites-available/mason
cd ../sites-enabled
rm default
ln -s ../sites-available/mason .
