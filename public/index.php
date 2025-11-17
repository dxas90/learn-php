<?php
declare(strict_types=1);

use App\Kernel;

require_once __DIR__ . '/../vendor/autoload.php';

use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Route;
use Symfony\Component\Routing\RouteCollection;
use Symfony\Component\Routing\Matcher\UrlMatcher;
use Symfony\Component\Routing\RequestContext;
use Symfony\Component\Routing\Generator\UrlGenerator;
use LearnPhp\Helpers;

// App start timestamp
if (!defined('START_TIME')) {
    define('START_TIME', microtime(true));
}

// App info
global $APP_INFO;
$APP_INFO = [
    'name' => getenv('APP_NAME') ?: 'learn-php',
    'version' => getenv('APP_VERSION') ?: '0.0.1',
    'environment' => getenv('APP_ENV') ?: 'development',
    'timestamp' => (new \DateTime('now', new \DateTimeZone('UTC')))->format('c')
];
k
// Simple in-process Prometheus-style metrics (best-effort, no external lib required)
// NOTE: PHP is stateless per-request. Metrics shown are from the current request lifecycle only.
// For persistent metrics across requests, use APCu, Redis, or external Prometheus exporter.
$PROM_METRICS = [
    'http_requests' => [], // keyed by method|path|status => count
    'request_duration_seconds' => [] // store durations to emit simple summary
];

// Pre-populate with sample historical data for demonstration (in production, use persistent storage)
$PROM_METRICS['http_requests']['GET|/|200'] = 42;
$PROM_METRICS['http_requests']['GET|/ping|200'] = 15;
$PROM_METRICS['http_requests']['GET|/healthz|200'] = 8;
$PROM_METRICS['request_duration_seconds']['GET|/|200'] = [0.012, 0.015, 0.011];
$PROM_METRICS['request_duration_seconds']['GET|/ping|200'] = [0.001, 0.002];
$PROM_METRICS['request_duration_seconds']['GET|/healthz|200'] = [0.008];

function prometheus_inc_request(string $method, string $path, int $status): void
{
    global $PROM_METRICS;
    $key = sprintf('%s|%s|%s', $method, $path, (string)$status);
    if (!isset($PROM_METRICS['http_requests'][$key])) {
        $PROM_METRICS['http_requests'][$key] = 0;
    }
    $PROM_METRICS['http_requests'][$key]++;
}

function prometheus_observe_duration(string $method, string $path, int $status, float $seconds): void
{
    global $PROM_METRICS;
    $key = sprintf('%s|%s|%s', $method, $path, (string)$status);
    if (!isset($PROM_METRICS['request_duration_seconds'][$key])) {
        $PROM_METRICS['request_duration_seconds'][$key] = [];
    }
    $PROM_METRICS['request_duration_seconds'][$key][] = $seconds;
}

function prometheus_render_metrics(): string
{
    global $PROM_METRICS;
    $lines = [];
    // Counters
    foreach ($PROM_METRICS['http_requests'] as $key => $count) {
        list($method, $path, $status) = explode('|', $key, 3);
        $labels = sprintf('method="%s",path="%s",status="%s"', addslashes($method), addslashes($path), addslashes($status));
        $lines[] = sprintf('http_requests_total{%s} %d', $labels, $count);
    }
    // Simple request duration (summary as count + sum)
    foreach ($PROM_METRICS['request_duration_seconds'] as $key => $values) {
        list($method, $path, $status) = explode('|', $key, 3);
        $labels = sprintf('method="%s",path="%s",status="%s"', addslashes($method), addslashes($path), addslashes($status));
        $sum = array_sum($values);
        $count = count($values);
        $lines[] = sprintf('http_request_duration_seconds_sum{%s} %F', $labels, $sum);
        $lines[] = sprintf('http_request_duration_seconds_count{%s} %d', $labels, $count);
    }
    return implode("\n", $lines) . "\n";
}

// Basic request logging (skip in test)
// Note: Disable web server access logs (nginx/apache/php-fpm) to avoid duplicate logging
// For nginx: access_log off; in server block
// For Apache: CustomLog /dev/null combined in VirtualHost
if (getenv('APP_ENV') !== 'test') {
    $timestamp = (new \DateTime('now', new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s\Z');
    $userAgent = $_SERVER['HTTP_USER_AGENT'] ?? 'Unknown';
    error_log(sprintf("[INFO] %s %s %s - User-Agent: %s", $timestamp, $_SERVER['REQUEST_METHOD'], $_SERVER['REQUEST_URI'], $userAgent));
}

$routes = new RouteCollection();

$routes->add('root', new Route('/', ['_controller' => function (Request $request) {
    global $APP_INFO;
    $welcome = [
        'message' => 'Welcome to learn-php API',
        'description' => 'A simple PHP microservice for learning and demonstration',
        'links' => [
            'repository' => 'https://github.com/dxas90/learn-php',
            'issues' => 'https://github.com/dxas90/learn-php/issues'
        ],
        'endpoints' => [
            ['path' => '/', 'method' => 'GET', 'description' => 'API welcome and documentation'],
            ['path' => '/ping', 'method' => 'GET', 'description' => 'Simple ping-pong response'],
            ['path' => '/healthz', 'method' => 'GET', 'description' => 'Health check endpoint'],
            ['path' => '/info', 'method' => 'GET', 'description' => 'Application and system information'],
            ['path' => '/version', 'method' => 'GET', 'description' => 'Application version'],
            ['path' => '/echo', 'method' => 'POST', 'description' => 'Echo back the request body'],
            ['path' => '/metrics', 'method' => 'GET', 'description' => 'Prometheus metrics endpoint']
        ]
    ];

    return Helpers::jsonResponse(['success' => true, 'data' => $welcome, 'timestamp' => Helpers::isoTimestamp()]);
}]));

$routes->add('ping', new Route('/ping', ['_controller' => function () {
    $response = new Response('pong');
    $response->headers->set('Content-Type', 'text/plain');
    $response = Helpers::applySecurityHeaders($response);
    return $response;
}]));

$routes->add('version', new Route('/version', ['_controller' => function (Request $request) {
    $version = getenv('APP_VERSION') ?: '0.0.1';
    return Helpers::jsonResponse(['success' => true, 'data' => ['version' => $version], 'timestamp' => Helpers::isoTimestamp()]);
}]));

$routes->add('healthz', new Route('/healthz', ['_controller' => function (Request $request) {
    $start = defined('START_TIME') ? START_TIME : $_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true);
    $uptime = microtime(true) - (float)($start);
    $memory = memory_get_usage();
    $memory_peak = memory_get_peak_usage();
    $load = function_exists('sys_getloadavg') ? sys_getloadavg() : [];

    $health = [
        'status' => 'healthy',
        'uptime' => $uptime,
        'timestamp' => Helpers::isoTimestamp(),
        'memory' => [
            'usage' => $memory,
            'peak' => $memory_peak,
        ],
        'cpu' => [
            'load' => $load,
        ],
        'version' => getenv('APP_VERSION') ?: '0.0.1',
        'environment' => getenv('APP_ENV') ?: 'development'
    ];

    return Helpers::jsonResponse(['success' => true, 'data' => $health, 'timestamp' => Helpers::isoTimestamp()]);
}]));

$routes->add('info', new Route('/info', ['_controller' => function (Request $request) {
    $memoryUsage = memory_get_usage();
    $memoryPeak = memory_get_peak_usage();
    $load = function_exists('sys_getloadavg') ? sys_getloadavg() : [];

    $info = [
        'application' => [
            'name' => getenv('APP_NAME') ?: 'learn-php',
            'version' => getenv('APP_VERSION') ?: '0.0.1',
            'environment' => getenv('APP_ENV') ?: 'development',
            'timestamp' => Helpers::isoTimestamp()
        ],
        'system' => [
            'php_version' => PHP_VERSION,
            'os' => php_uname('s'),
            'release' => php_uname('r'),
            'version' => php_uname('v'),
            'machine' => php_uname('m'),
            'processor' => php_uname('p'),
            'memory' => [
                'usage' => $memoryUsage,
                'peak' => $memoryPeak
            ],
            'cpu' => [ 'load' => $load ],
        ],
        'environment' => [
            'port' => getenv('PORT') ?: '4567',
            'host' => getenv('HOST') ?: '0.0.0.0',
        ]
    ];

    return Helpers::jsonResponse(['success' => true, 'data' => $info, 'timestamp' => Helpers::isoTimestamp()]);
}]));

$routes->add('echo', new Route('/echo', ['_controller' => function (Request $request) {
    $content = $request->getContent();
    $data = json_decode($content, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        return Helpers::jsonResponse(['success' => false, 'message' => 'Invalid JSON payload', 'timestamp' => Helpers::isoTimestamp()], 400);
    }
    return Helpers::jsonResponse(['success' => true, 'data' => $data, 'timestamp' => Helpers::isoTimestamp()]);
}], [], [], '', [], ['POST']));

// Metrics route (simple Prometheus exposition)
$routes->add('metrics', new Route('/metrics', ['_controller' => function (Request $request) {
    $body = prometheus_render_metrics();
    $resp = new Response($body, 200);
    $resp->headers->set('Content-Type', 'text/plain; version=0.0.4');
    return $resp;
}]));

// Basic CORS preflight handling
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    $response = new Response('', 204);
    $response->headers->set('Access-Control-Allow-Origin', getenv('CORS_ORIGIN') ?: '*');
    $response->headers->set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    $response->headers->set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    $response->send();
    exit;
}

$context = new RequestContext();
$context->fromRequest(Request::createFromGlobals());

$matcher = new UrlMatcher($routes, $context);

try {
    $parameters = $matcher->match($context->getPathInfo());
    $controller = $parameters['_controller'];
    $req = Request::createFromGlobals();
    $start = microtime(true);
    $response = $controller($req);
    $duration = microtime(true) - $start;
    $statusCode = 200;
    if ($response instanceof Response) {
        $statusCode = $response->getStatusCode();
        $response->send();
    } else {
        // Ensure we always return a Response
        $resp = new Response((string)$response);
        $statusCode = $resp->getStatusCode();
        $resp->send();
    }
    // record metrics
    try {
        prometheus_inc_request($_SERVER['REQUEST_METHOD'] ?? 'GET', $context->getPathInfo(), $statusCode);
        prometheus_observe_duration($_SERVER['REQUEST_METHOD'] ?? 'GET', $context->getPathInfo(), $statusCode, $duration);
    } catch (\Throwable $e) {
        // ignore metric errors
    }
} catch (\Symfony\Component\Routing\Exception\ResourceNotFoundException $e) {
    error_log("[ERROR] Resource not found: " . $e->getMessage());
    $resp = Helpers::jsonResponse(['error' => true, 'message' => 'Resource not found', 'statusCode' => 404, 'timestamp' => Helpers::isoTimestamp()], 404);
    $resp->send();
} catch (\Exception $e) {
    error_log("[ERROR] Internal Server Error: " . $e->getMessage());
    $msg = getenv('APP_ENV') === 'production' ? 'Internal Server Error' : $e->getMessage();
    $resp = Helpers::jsonResponse(['error' => true, 'message' => 'Internal Server Error', 'statusCode' => 500, 'timestamp' => Helpers::isoTimestamp(), 'details' => $msg], 500);
    $resp->send();
}
