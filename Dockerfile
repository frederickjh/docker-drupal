FROM debian:wheezy
MAINTAINER Jose de Leon <jose_de_leon@hotmail.com>
ENV DEBIAN_FRONTEND noninteractive
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Install packages.
RUN apt-get update
RUN apt-get install -y \
	vim \
	git \
	apache2 \
	php-apc \
	php5-fpm \
	php5-cli \
	php5-mysql \
	php5-gd \
	php5-curl \
	libapache2-mod-php5 \
	curl \
	mysql-server \
	mysql-client \
	openssh-server \
	phpmyadmin \
	wget \
	nano \
	postgresql-9.1 \
	postgresql-client \
	php5-pgsql \
	php5-sqlite \
	openjdk-7-jre-headless \
	supervisor
RUN apt-get clean

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php
RUN mv composer.phar /usr/local/bin/composer

# Install Drush 7.
RUN composer global require drush/drush:7.*
RUN composer global update
# Unfortunately, adding the composer vendor dir to the PATH doesn't seem to work. So:
RUN ln -s /root/.composer/vendor/bin/drush /usr/local/bin/drush

# Setup PHP.
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php5/cli/php.ini
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php5/apache2/php.ini
RUN sed -i 's/memory_limit = 128M/memory_limit = 384M/' /etc/php5/apache2/php.ini
RUN sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php5/apache2/php.ini
RUN sed -i 's/max_input_time = 60/max_input_time = 120/' /etc/php5/apache2/php.ini
RUN sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 300M/' /etc/php5/apache2/php.ini
RUN echo 'apc.shm_size = 96M' >> /etc/php5/apache2/conf.d/20-apc.ini

# Setup Apache.
# In order to run our Simpletest tests, we need to make Apache
# listen on the same port as the one we forwarded. Because we use
# 8080 by default, we set it up for that port.
RUN sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/sites-available/default
RUN echo "Listen 8080" >> /etc/apache2/ports.conf
RUN sed -i 's/VirtualHost *:80/VirtualHost */' /etc/apache2/sites-available/default
RUN a2enmod rewrite

# Setup PHPMyAdmin
RUN echo -e "\n# Include PHPMyAdmin configuration\nInclude /etc/phpmyadmin/apache.conf\n" >> /etc/apache2/apache2.conf
RUN sed -i -e "s/\/\/ \$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/\$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/g" /etc/phpmyadmin/config.inc.php

# Setup MySQL, bind on all addresses.
RUN sed -i -e 's/^bind-address\s*=\s*127.0.0.1/#bind-address = 127.0.0.1/' /etc/mysql/my.cnf

# Setup PostgreSQL - TODO (find a better way to do this)
# Configure PostgreSQL
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.1/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.1/main/postgresql.conf

# there might be a docker bug that postgresql could access 
# /etc/ssl/private/ssl-cert-snakeoil.key
RUN sed -i "s/ssl = true/ssl = false/g" /etc/postgresql/9.1/main/postgresql.conf

# start postgresql and create a role
USER postgres
RUN /etc/init.d/postgresql start && \
    psql -e --command "ALTER USER postgres WITH PASSWORD 'postgres'" && \
    /etc/init.d/postgresql stop

# Go back to root
USER root

# Setup SSH.
RUN echo 'root:root' | chpasswd
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN mkdir /var/run/sshd && chmod 0755 /var/run/sshd
RUN mkdir -p /root/.ssh/ && touch /root/.ssh/authorized_keys
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Setup Supervisor.
RUN echo -e '[program:apache2]\ncommand=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND"\nautorestart=true\n\n' >> /etc/supervisor/supervisord.conf
RUN echo -e '[program:mysql]\ncommand=/usr/bin/pidproxy /var/run/mysqld/mysqld.pid /usr/sbin/mysqld\nautorestart=true\n\n' >> /etc/supervisor/supervisord.conf
RUN echo -e '[program:sshd]\ncommand=/usr/sbin/sshd -D\n\n' >> /etc/supervisor/supervisord.conf
# Setup Supervisor PostgreSQL
RUN echo -e '[program:postgresql]\nuser=postgres\nautorestart=true\ncommand=/usr/lib/postgresql/9.1/bin/postgres -D /var/lib/postgresql/9.1/main -c config_file=/etc/postgresql/9.1/main/postgresql.conf\n\n' >> /etc/supervisor/supervisord.conf
# Setup Supervisor Solr
RUN echo -e '[program:solr]\ncommand=/usr/bin/java -Xmx512M -server -jar start.jar\ndirectory=/usr/share/solr/example\nautorestart=true\n\n' >> /etc/supervisor/supervisord.conf

# Download Drupal.
RUN rm -rf /var/www
RUN cd /var && \
# Download the Web Experience Toolkit Drupal distribution
	drush dl wetkit-7.x-4.x-dev && mv /var/wetkit* /var/www
# Replace the line above with the line below to download the stock Drupal distribution
#	drush dl drupal && mv /var/drupal* /var/www
RUN mkdir -p /var/www/sites/default/files && \
	chmod a+w /var/www/sites -R && \
	mkdir /var/www/sites/all/modules/contrib -p && \
	mkdir /var/www/sites/all/modules/custom && \
	mkdir /var/www/sites/all/modules/features && \
	mkdir /var/www/sites/all/themes/contrib -p && \
	mkdir /var/www/sites/all/themes/custom && \
	chown -R www-data:www-data /var/www/

# Setup Adminer - TODO (find a better directory for it)
RUN wget -c http://adminer.org/latest.php -O /var/www/adminer.php
RUN echo '<?php phpinfo(); ?>' > /var/www/php-info.php

# Setup Solr
RUN wget -c http://archive.apache.org/dist/lucene/solr/4.10.4/solr-4.10.4.tgz -O /tmp/solr-4.10.4.tgz
RUN cd /tmp && tar xzf solr-4.10.4.tgz && mv solr-4.10.4 /usr/share/solr
RUN cd /usr/share/solr/example && /usr/bin/java -Xmx512M -server -jar start.jar &

# Start MySQL
RUN /etc/init.d/mysql start

# Start PostgreSQL
RUN /etc/init.d/postgresql start

# Install Drupal
# RUN cd /var/www && drush si -y minimal --db-url=mysql://root:@localhost/drupal --account-pass=admin

EXPOSE 80 3306 22 5432 8983
CMD exec supervisord -n
