#!/bin/bash
#

# Define a list of theme repositories.


# Make a database, if we don't already have one
echo -e "\nCreating database 'bu_develop' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS bu_develop"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON bu_develop.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
if [[ ! -d /srv/log/bu-develop ]]; then
	mkdir /srv/log/bu-develop
fi
	touch /srv/log/bu-develop/error.log
	touch /srv/log/bu-develop/access.log

# Install and configure the latest stable version of WordPress
if [[ ! -d /srv/www/bu-develop ]]; then
  echo "Checking out WordPress trunk. See https://develop.svn.wordpress.org/trunk"
  noroot svn checkout "https://develop.svn.wordpress.org/trunk/src" "/tmp/bu-develop"

  cd /tmp/bu-develop/

  echo "Moving BU Develop to a shared directory, /srv/www/bu-develop"
  mv /tmp/bu-develop /srv/www/bu-develop

  cd /srv/www/bu-develop/
  echo "Creating wp-config.php for bu.develop"
  noroot wp core config --dbname=bu_develop --dbuser=wp --dbpass=wp --quiet --extra-php --allow-root <<PHP
  // Match any requests made via xip.io.
  if ( isset( \$_SERVER['HTTP_HOST'] ) && preg_match('/^(bu.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(.xip.io)\z/', \$_SERVER['HTTP_HOST'] ) ) {
  	define( 'WP_HOME', 'http://' . \$_SERVER['HTTP_HOST'] );
  	define( 'WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST'] );
  }
  define( 'WP_DEBUG', true );
PHP

	# Install WordPress...
	echo "Configuring WordPress Multisite Subdirectory..."
		wp core install --url=bu.dev --quiet --title="BU Develop" --admin_name=admin --admin_email="admin@local.dev" --admin_password="password"
	PHP

  # Install WordPress Multisite...
  echo "Installing WordPress Multisite ..."
  noroot wp core multisite-install --title="BU Develop" --admin_user=admin --admin_email="admin@local.dev" --allow-root

else
  echo "Updating BU develop..."
  cd /srv/www/bu-develop/
  if [[ -e .svn ]]; then
    svn up
  else
    if [[ $(git rev-parse --abbrev-ref HEAD) == 'master' ]]; then
      git pull --no-edit git://develop.git.wordpress.org/src master
    else
      echo "Skip auto git pull on develop.git.wordpress.org since not on master branch"
    fi
  fi
fi
