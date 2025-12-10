# Builder stage - install dependencies
FROM php:8.3-fpm-alpine3.20 AS builder

WORKDIR /app

# Install build dependencies and composer
RUN apk add --no-cache \
    git \
    unzip \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy composer files
COPY composer.json composer.lock* ./

# Install PHP dependencies
RUN composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader

# Production stage - minimal Alpine with PHP-FPM and nginx
FROM php:8.3-fpm-alpine3.20 AS production

WORKDIR /app

# Install nginx and runtime dependencies
RUN apk add --no-cache \
    nginx \
    tzdata \
    ca-certificates

# Create non-root user
RUN addgroup -g 1001 phpuser && \
    adduser -D -u 1001 -G phpuser phpuser

# Copy nginx config and create temp directories
COPY nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /tmp/nginx /var/lib/nginx/logs && \
    chown -R phpuser:phpuser /tmp/nginx /var/lib/nginx

# Configure PHP-FPM
RUN sed -i 's/^;access.log = .*/access.log = \/dev\/null/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;catch_workers_output = .*/catch_workers_output = yes/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;clear_env = .*/clear_env = no/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^user = www-data/user = phpuser/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^group = www-data/group = phpuser/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;pm.status_path = .*/pm.status_path = \/status/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;ping.path = .*/ping.path = \/ping/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^;ping.response = .*/ping.response = pong/' /usr/local/etc/php-fpm.d/www.conf

# Copy vendor from builder
COPY --from=builder --chown=phpuser:phpuser /app/vendor ./vendor

# Copy application code
COPY --chown=phpuser:phpuser . .

# Set proper permissions
RUN chown -R phpuser:phpuser /app

EXPOSE 4567

# Switch to non-root user
USER phpuser

# Health check using PHP's standard library
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD php -r "\$fp = @fsockopen('127.0.0.1', 4567, \$errno, \$errstr, 3); if (!\$fp) exit(1); fwrite(\$fp, 'GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n'); \$response = fread(\$fp, 1024); fclose(\$fp); exit(strpos(\$response, '200 OK') !== false ? 0 : 1);" || exit 1

# Start both PHP-FPM and nginx
CMD php-fpm -D && nginx -g 'daemon off;'
