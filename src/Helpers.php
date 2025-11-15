<?php
namespace LearnPhp;

use Symfony\Component\HttpFoundation\Response;

class Helpers
{
    public static function isoTimestamp(): string
    {
        $dt = new \DateTime('now', new \DateTimeZone('UTC'));
        return $dt->format('c');
    }

    public static function jsonResponse(array $data, int $status = 200): Response
    {
        $response = new Response(json_encode($data, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT), $status);
        $response->headers->set('Content-Type', 'application/json');
        // Security headers
        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');
        $response->headers->set('X-XSS-Protection', "1; mode=block");
        $response->headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');
        $response->headers->set('Content-Security-Policy', "default-src 'self'");
        // CORS - allow from configured origin or *
        $origin = getenv('CORS_ORIGIN') ?: '*';
        $response->headers->set('Access-Control-Allow-Origin', $origin);
        $response->headers->set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
        $response->headers->set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

        return $response;
    }

    public static function applySecurityHeaders(Response $response): Response
    {
        // Security headers
        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');
        $response->headers->set('X-XSS-Protection', "1; mode=block");
        $response->headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');
        $response->headers->set('Content-Security-Policy', "default-src 'self'");
        $response->headers->set('Access-Control-Allow-Origin', getenv('CORS_ORIGIN') ?: '*');
        $response->headers->set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
        $response->headers->set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

        return $response;
    }
}
