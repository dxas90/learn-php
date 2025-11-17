FROM php:8.2-cli

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y git unzip && rm -rf /var/lib/apt/lists/*

# Install composer
RUN set -eux; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm composer-setup.php

COPY . /app
RUN if [ -f composer.json ]; then composer install --no-dev --no-interaction --no-scripts; fi

EXPOSE 4567
# Suppress PHP built-in server access logs by redirecting stderr to /dev/null
# Our application handles logging via error_log() in index.php
CMD ["sh", "-c", "php -S 0.0.0.0:4567 -t public 2>/dev/null"]
