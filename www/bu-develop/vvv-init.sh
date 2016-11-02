#!/bin/bash
#

# Define a list of theme repositories.
bu_git_theme_list=(
	bu-admissions
	bu-library
	bu-sph-responsive
	bu-today
	flexi-global
	flexi-honors-college
	r-abroad
	r-agganis
	r-alumni
	r-archaeology
	r-arrows
	r-artofpoetry
	r-biology
	r-brand
	r-busm
	r-cas-sister
	r-cfa
	r-comm
	r-comm-sister
	r-ctsi
	r-dli
	r-eng
	r-evcondept
	r-facilities
	r-gened
	r-hr
	r-id
	r-law
	r-mssp
	r-pardeeschool
	r-pr
	r-questrom
	r-registrar
	r-research
	r-researchsupport
	r-research-sister
	r-pardeeschool
	r-scnc
	r-sed
	r-sphcommportal
	r-urop
	responsive-foundation
	resposnive-framework
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

bu_private_theme_repos() {
	for theme in "${bu_git_theme_list[@]}"
	do
		cd /srv/www/bu-develop/htdocs/wp-content/themes

		if [[ ! -e $theme ]]; then
			echo -e "Theme does not exist. Creating."

			echo -e "\nChecking out "$theme", see https://github.com/bu-ist/"$theme".git"
			git clone "git@github.com:bu-ist/"${bu_git_theme_list[$theme]}".git" $theme
			cd $theme
			bu_update_packages
		else
			echo -e $theme
			cd /srv/www/bu-develop/htdocs/wp-content/themes/$theme
			git pull origin master
			bu_update_packages
		fi

		sleep 5s
	done

}

bu_update_packages() {
	if [[ -e bower.json ]]; then
		bower install
	fi

	if [[ -e Gemfile ]]; then
		bundler install
	fi

	if [[ -e composer.json ]]; then
		composer install
	fi

	if [[ -e package.json ]]; then
		npm install
		grunt build
	fi
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

# add github to the list of known_hosts
# see http://rshestakov.wordpress.com/2014/01/26/how-to-make-vagrant-and-puppet-to-clone-private-github-repo/
echo "Add github.com to known_hosts"
ssh-keyscan -H github.com >> ~/.ssh/known_hosts
ssh -T git@github.com

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

	bu_private_theme_repos
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

	# Install and update all BU private theme GitHub repos.
	bu_private_theme_repos

	# Update all plugins
	install_public_plugins
	noroot wp plugin update-all

	install_public_themes
	noroot wp theme update-all
fi
