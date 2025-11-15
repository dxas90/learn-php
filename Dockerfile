FROM php:8.2-cli

WORKDIR /app

# Install composer
RUN set -eux; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm composer-setup.php

COPY . /app
RUN if [ -f composer.json ]; then composer install --no-dev --no-interaction --no-scripts; fi

EXPOSE 4567
CMD ["php", "-S", "0.0.0.0:4567", "-t", "public"]
