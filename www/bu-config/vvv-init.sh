#!/bin/bash
#

# Define a list of theme repositories.
bu_git_theme_list=(
	[bu-today]="bu-today.git"
	[r-eng]="r-eng.git"
	[responsive-foundation]="responsive-foundation.git"
	[resposnive-framework]="responsive-framework.git"
	[r-abroad]="r-abroad.git"
	[r-researchsupport]="r-researchsupport.git"
	[r-research-sister]="r-research-sister.git"
	[r-sphcommportal]="r-sphcommportal.git"
)

# List of publicly accessible plugins.
public_plugins=(
	"blogger-importer"
	"cmb2"
	"enable-media-replace"
	"query-monitor"
	"regenerate-thumbnails"
	"rewrite-rules-inspector"
	"safe-redirect-manager"
	"shortcode-ui"
	"syntaxhighlighter"
	"wordpress-importer"
	"wp-crontrol"
	"wp-latex"
)

# List of publicly accessible themes.
public_themes=(
	"p2"
)

# Function copied from provision.sh for avoiding root.
noroot() {
  sudo -EH -u "vagrant" "$@";
}

install_private_bu_theme_repos() {
    # Install all BU Private repos
    for theme in "${!bu_git_theme_list[@]}"
		do
			#Make sure we are in the themes folder each time.
			cd /srv/www/bu-develop/htdocs/wp-content/themes

			if [[ ! -e $theme ]]; then
				echo -e "Theme does not exist. Creating."

				echo -e "\nChecking out "$theme", see https://github.com/bu-ist/"$theme
				git clone "git@github.com:bu-ist/"${bu_git_theme_list[$theme]}".git" $theme
				cd $theme
				git checkout `git describe --abbrev=0 --tags`
      fi
    done
}

install_public_plugins() {
	cd /srv/www/bu-develop/htdocs
	echo -e "Installing WordPress.org plugins..."
  noroot wp plugin install ${public_plugins[@]}
}

install_public_themes() {
	cd /srv/www/bu-develop/htdocs
	echo -e "Installing WordPress.org themes..."
  noroot wp plugin install ${public_themes[@]}
}

# Set up our GitHub SSH key in order to have access to private repos.
echo -e "\nEnsuring Vagrant has access to our SSH keys..."
key_file=~/.ssh/id_rsa

if [[ -f $key_file ]]; then
	[[ -z $(ssh-add -L | grep $key_file) ]] && ssh-add $key_file
else
	echo -e "\nIt appears you have not set up SSH authentication with GitHub yet. See https://help.github.com/articles/generating-an-ssh-key/"
fi

# Make a database, if we don't already have one
echo -e "\nCreating database 'bu_develop' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS bu_develop"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON bu_develop.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
if [[ ! -d /srv/log/bu-develop/htdocs ]]; then
	mkdir /srv/log/bu-develop/htdocs
fi
	touch /srv/log/bu-develop/error.log
	touch /srv/log/bu-develop/access.log

# Install and configure the latest stable version of WordPress
if [[ ! -d /srv/www/bu-develop/htdocs ]]; then
  echo "Checking out WordPress trunk. See https://develop.svn.wordpress.org/trunk"
  noroot svn checkout "https://develop.svn.wordpress.org/trunk/src" "/tmp/bu-develop/htdocs"

  cd /tmp/bu-develop/htdocs

  echo "Moving BU Develop to a shared directory, /srv/www/bu-develop"
  mv /tmp/bu-develop/htdocs /srv/www/bu-develop/htdocs

  cd /srv/www/bu-develop/htdocs
  echo "Creating wp-config.php for bu.develop"
  noroot wp core config --dbname=bu_develop --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
  // Match any requests made via xip.io.
  if ( isset( \$_SERVER['HTTP_HOST'] ) && preg_match('/^(bu.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(.xip.io)\z/', \$_SERVER['HTTP_HOST'] ) ) {
  	define( 'WP_HOME', 'http://' . \$_SERVER['HTTP_HOST'] );
  	define( 'WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST'] );
  }
  define( 'WP_DEBUG', true );
PHP

	# Install WordPress...
	echo "Configuring WordPress Multisite Subdirectory..."
  noroot wp core multisite-install --url=bu.dev --title="BU Develop" --admin_user=admin --admin_email="admin@local.dev" --admin_password="password"

	install_private_bu_theme_repos
	install_public_plugins
	install_public_themes

else
  echo "Updating BU develop..."
  cd /srv/www/bu-develop/htdocs
  if [[ -e .svn ]]; then
    svn up
  else
    if [[ $(git rev-parse --abbrev-ref HEAD) == 'master' ]]; then
      git pull --no-edit git://develop.git.wordpress.org/src master
    else
      echo "Skip auto git pull on develop.git.wordpress.org since not on master branch"
    fi
  fi

	# Update all plugins
	install_public_plugins
	noroot wp plugin update-all

	install_public_themes
	noroot wp theme update-all
fi
