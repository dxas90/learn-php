FROM php:8.2-fpm

WORKDIR /app

# Install system dependencies including nginx
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Install composer
RUN set -eux; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm composer-setup.php

COPY . /app
RUN if [ -f composer.json ]; then composer install --no-dev --no-interaction --no-scripts; fi

# Configure nginx
RUN echo 'server { \n\
    listen 4567; \n\
    server_name _; \n\
    root /app/public; \n\
    index index.php; \n\
    access_log off; \n\
    error_log /dev/stderr warn; \n\
    location / { \n\
        try_files $uri /index.php$is_args$args; \n\
    } \n\
    location ~ \.php$ { \n\
        fastcgi_pass 127.0.0.1:9000; \n\
        fastcgi_index index.php; \n\
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; \n\
        include fastcgi_params; \n\
    } \n\
}' > /etc/nginx/sites-available/default

# Configure PHP-FPM to log only errors
RUN sed -i 's/^;access.log = .*/access.log = \/dev\/null/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;catch_workers_output = .*/catch_workers_output = yes/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;clear_env = .*/clear_env = no/' /usr/local/etc/php-fpm.d/www.conf

EXPOSE 4567

# Start both PHP-FPM and nginx
CMD php-fpm -D && nginx -g 'daemon off;'
