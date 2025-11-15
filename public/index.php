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

// Basic request logging (skip in test)
if (getenv('APP_ENV') !== 'test') {
    error_log(sprintf("%s %s", $_SERVER['REQUEST_METHOD'], $_SERVER['REQUEST_URI']));
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
            ['path' => '/echo', 'method' => 'POST', 'description' => 'Echo back the request body']
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
    $response = $controller($req);
    if ($response instanceof Response) {
        $response->send();
    } else {
        // Ensure we always return a Response
        $resp = new Response((string)$response);
        $resp->send();
    }
} catch (\Symfony\Component\Routing\Exception\ResourceNotFoundException $e) {
    $resp = Helpers::jsonResponse(['error' => true, 'message' => 'Resource not found', 'statusCode' => 404, 'timestamp' => Helpers::isoTimestamp()], 404);
    $resp->send();
} catch (\Exception $e) {
    $msg = getenv('APP_ENV') === 'production' ? 'Internal Server Error' : $e->getMessage();
    $resp = Helpers::jsonResponse(['error' => true, 'message' => 'Internal Server Error', 'statusCode' => 500, 'timestamp' => Helpers::isoTimestamp(), 'details' => $msg], 500);
    $resp->send();
}
