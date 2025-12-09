FROM php:8.2-fpm

WORKDIR /app

# Create non-root user for running the application
RUN useradd -m -u 1001 -s /sbin/nologin phpuser

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

# Configure nginx to use /tmp for writable directories and run as non-root
RUN mkdir -p /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp && \
    chown -R phpuser:phpuser /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp && \
    echo 'user phpuser; \n\
pid /tmp/nginx.pid; \n\
error_log /dev/stderr warn; \n\
events { \n\
    worker_connections 1024; \n\
} \n\
http { \n\
    include /etc/nginx/mime.types; \n\
    default_type application/octet-stream; \n\
    client_body_temp_path /tmp/client_temp; \n\
    proxy_temp_path /tmp/proxy_temp; \n\
    fastcgi_temp_path /tmp/fastcgi_temp; \n\
    uwsgi_temp_path /tmp/uwsgi_temp; \n\
    scgi_temp_path /tmp/scgi_temp; \n\
    server { \n\
        listen 4567; \n\
        server_name _; \n\
        root /app/public; \n\
        index index.php; \n\
        access_log off; \n\
        add_header X-Frame-Options "SAMEORIGIN" always; \n\
        add_header X-Content-Type-Options "nosniff" always; \n\
        add_header X-XSS-Protection "1; mode=block" always; \n\
        location / { \n\
            try_files $uri /index.php$is_args$args; \n\
        } \n\
        location ~ \.php$ { \n\
            fastcgi_pass 127.0.0.1:9000; \n\
            fastcgi_index index.php; \n\
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name; \n\
            include fastcgi_params; \n\
        } \n\
    } \n\
}' > /etc/nginx/nginx.conf && \
    chown phpuser:phpuser /etc/nginx/nginx.conf

# Configure PHP-FPM security and logging
RUN sed -i 's/^;access.log = .*/access.log = \/dev\/null/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;catch_workers_output = .*/catch_workers_output = yes/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;clear_env = .*/clear_env = no/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^user = .*/user = phpuser/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^group = .*/group = phpuser/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;pm.status_path = .*/pm.status_path = \/status/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;ping.path = .*/ping.path = \/ping/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;ping.response = .*/ping.response = pong/' /usr/local/etc/php-fpm.d/www.conf

# Set proper permissions for application directory
RUN chown -R phpuser:phpuser /app && \
    chmod 755 /app

EXPOSE 4567

# Switch to non-root user
USER phpuser

# Start both PHP-FPM and nginx
CMD php-fpm -D && nginx -g 'daemon off;'
