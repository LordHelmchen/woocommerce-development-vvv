#!/usr/bin/env bash
# Provision WooCommerce Development

# fetch the first host as the primary domain. If none is available, generate a default using the site name
DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAIN_NO_TLD=`echo ${DOMAIN} | grep -Po '.*(?=\.)'`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}


# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/nginx-error.log
touch ${VVV_PATH_TO_SITE}/log/nginx-access.log


# If we delete public_html, let's just start over.
if [[ ! -d "${VVV_PATH_TO_SITE}/public_html" ]]; then

  echo "Creating directory public_html for WooCommerce Development...\n"
  mkdir -p ${VVV_PATH_TO_SITE}/public_html
  cd ${VVV_PATH_TO_SITE}/public_html

  # **
  # WordPress
  # **

  # Download WordPress
  echo "Downloading the latest version of WordPress into the public_html folder...\n"
  wp core download --locale=en_US 

  # Install WordPress.
  echo "Creating wp-config in public_html...\n"
  wp core config --dbname='${DB_NAME}' --dbuser=wp --dbpass=wp --dbhost='localhost' --dbprefix=wp_ --locale=en_US  --extra-php <<PHP
// Match any requests made via xip.io.
if ( isset( \$_SERVER['HTTP_HOST'] ) && preg_match('/^(${DOMAIN_NO_TLD}.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(.xip.io)\z/', \$_SERVER['HTTP_HOST'] ) ) {
    define( 'WP_HOME', 'http://' . \$_SERVER['HTTP_HOST'] );
    define( 'WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST'] );
}

define( 'WP_DEBUG', true );
define( 'WP_DEBUG_DISPLAY', false );
define( 'WP_DEBUG_LOG', true );
define( 'SCRIPT_DEBUG', true );
define( 'JETPACK_DEV_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"
  
  
  echo "Customization"
  
    # Update Blog Description option
  echo 'Updating tagline...\n'
  noroot wp option update blogdescription 'WooCommerce Development VVV' 

  # **
  # Your themes
  # **
  echo 'Installing themes...\n'
  noroot wp theme install storefront --activate 

  # Delete unrequired themes
  echo "Deleting unrequired default themes..."
  noroot wp theme delete twentyfifteen  

  # **
  # # Create pages
  # **
  echo "Creating pages for the Storefront theme..."
  noroot wp post create --post_type=page --post_title='Homepage' --post_status=publish --post_author=1 
  noroot wp post create --post_type=page --post_title='Blog' --post_status=publish --post_author=1 

  # **
  # # Set homepage template for the storefront theme to the page post meta
  # **
  echo "Setting Storefront homepage template meta..."
  noroot wp post meta set 3 _wp_page_template template-homepage.php 

  # **
  # # Enable a page to display as the frontpage of the site.
  # # Set the homepage as the frontpage of the site.
  # # Set the Blog page as the posts page for the site.
  # **
  echo "Setting Storefront pages as the WordPress Frontpage and Posts Page..."
  noroot wp option update show_on_front page 
  noroot wp option update page_on_front 3 
  noroot wp option update page_for_posts 4 

  # **
  # # Create Menus
  # **
  echo "Create Custom WordPress Primary Menu..."
  noroot wp menu create 'Primary Menu' 

  echo "Assign primary menu to the storefront themes primary location..."
  noroot wp menu location assign primary-menu primary 

  echo "Adding basic menu items to the Primary Menu..."
  noroot wp menu item add-custom primary-menu Home https://${DOMAIN}/ 
  noroot wp menu item add-post primary-menu 4 --title='Blog' 

  # **
  # # Plugins
  # **

  echo 'Installing plugins...\n'
  noroot wp plugin install woocommerce --activate 
  noroot wp plugin install wc-invoice-gateway 
  noroot wp plugin install wordpress-importer --activate 
  noroot wp plugin install homepage-control --activate 
  noroot wp plugin install customizer-reset-by-wpzoom --activate 
  noroot wp plugin install user-switching --activate 
  noroot wp plugin install regenerate-thumbnails --activate 
  noroot wp plugin install wp-mail-logging 
  noroot wp plugin install wp-crontrol --activate 
  noroot wp plugin install loco-translate 
  noroot wp plugin install query-monitor 
  noroot wp plugin install jetpack --activate 
  noroot wp plugin install developer --activate 
  noroot wp plugin install rewrite-rules-inspector --activate 
  noroot wp plugin install log-deprecated-notices 
  noroot wp plugin install log-viewer 
  #noroot wp plugin install wordpress-beta-tester 
  #noroot wp plugin install debug-bar --activate 
  #noroot wp plugin install debug-bar-console --activate 
  #noroot wp plugin install debug-bar-cron --activate 
  #noroot wp plugin install debug-bar-extender --activate 


  # Delete unrequired default plugins
  echo "Deleting unrequired default plugins..."
  wp plugin delete hello   
  #wp plugin delete akismet 

  cd ${VVV_PATH_TO_SITE}/public_html
  # Add Github hosted plugins.
  echo 'Installing public remote Git repo software installs...\n'
  git clone --recursive https://github.com/mattyza/matty-theme-quickswitch.git        wp-content/plugins/matty-theme-quickswitch
  wp plugin activate matty-theme-quickswitch 
  
  #echo "Installing woocommerce from github...\n"
  #git clone --recursive https://github.com/woocommerce/woocommerce.git    wp-content/plugins/woocommerce

  # **
  # Unit Data
  # **

  # Import the WordPress unit data.
  echo 'Installing WordPress theme unit test data...\n'
  curl -O https://wpcom-themes.svn.automattic.com/demo/theme-unit-test-data.xml
  wp import theme-unit-test-data.xml --authors=create 
  rm theme-unit-test-data.xml

  # Import the WooCommerce unit data.
  echo 'Installing WooCommerce dummy product data...\n'
  curl -O https://raw.githubusercontent.com/woocommerce/woocommerce/master/dummy-data/dummy-data.xml
  wp import dummy-data.xml --authors=create 
  rm dummy-data.xml

  # Replace any urls from the WordPress unit data
  echo 'Adjusting urls in database...\n'
  wp search-replace 'wpthemetestdata.wordpress.com' '${DOMAIN}' --skip-columns=guid 

  # Update the sites permalink structure
  echo 'Update permalink structure...\n'
  wp option update permalink_structure '/%postname%/' 
  wp rewrite flush 
  
  
else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"
  noroot wp core update-db 

  # Update Plugins
  echo "Updating plugins for WooCommerce Development VVV...\n"
  noroot wp plugin update --all 
  
  # **
  # Your themes
  # **
  echo "Updating themes for WooCommerce Development VVV...\n"
  noroot wp theme update --all

fi

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi




  cd ${VVV_PATH_TO_SITE}/public_html

  # Updates
  if $(wp core is-installed ); then

    # Update WordPress.
    echo "Updating WordPress for WooCommerce Development VVV...\n"
    wp core update 
    wp core update-db 

    # Update Plugins
    echo "Updating plugins for WooCommerce Development VVV...\n"
    wp plugin update --all 

    # **
    # Your themes
    # **
    echo "Updating themes for WooCommerce Development VVV...\n"
    wp theme update --all 

  fi

  cd ..

fi
