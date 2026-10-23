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

# Create non-root user matching Helm chart's runAsUser/fsGroup
# Helm values pin runAsUser=1000 and fsGroup=65534 (nobody); the uid MUST match
# or writes to directories chowned at build time fail at runtime.
RUN addgroup -g 1000 phpuser && \
    adduser -D -u 1000 -G phpuser phpuser

# Copy nginx config and prepare writable paths.
# The Helm chart mounts an emptyDir at /tmp with fsGroup=65534, so build-time
# chown of /tmp is shadowed at runtime. nginx's default error log path
# /var/lib/nginx/logs/error.log and the pid dir must either be writable by the
# runtime user or redirected. We redirect everything to /tmp (writable via
# emptyDir + fsGroup) in nginx.conf and in CMD.
COPY nginx.conf /etc/nginx/nginx.conf
RUN chown -R phpuser:phpuser /var/log/nginx /var/lib/nginx

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

# Health check using wget (busybox has it; curl is not installed in the final image)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4567/healthz >/dev/null 2>&1 || exit 1

# Start PHP-FPM and nginx. Create nginx's writable temp dirs under /tmp at
# runtime: /tmp is backed by an emptyDir in the Helm chart, so build-time
# mkdir inside the image is wiped on mount — we must create them in CMD.
CMD ["sh", "-c", "mkdir -p /tmp/nginx && php-fpm -D && exec nginx -g 'daemon off;'"]
