<?php
/**
 * Biometric Latency Cartographer - Legacy Bridge
 * 
 * Interfacing script for legacy logging systems over FastCGI.
 * This handler processes incoming sub-millisecond telemetry data and
 * persists it to legacy flat-file databases and system logs for 
 * historical audit trails during kernel-level latency testing.
 */

declare(strict_types=1);

namespace BiometricLatencyCartographer;

header('Content-Type: application/json');
header('X-Content-Type-Options: nosniff');

class LegacyHandler
{
    private const LOG_DIR = __DIR__ . '/../logs/legacy';
    private const MAX_PAYLOAD_SIZE = 1048576; // 1MB

    private string $requestId;

    public function __construct()
    {
        $this->requestId = bin2hex(random_bytes(8));
        if (!is_dir(self::LOG_DIR)) {
            mkdir(self::LOG_DIR, 0755, true);
        }
    }

    public function handleRequest(): void
    {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            $this->sendError('Invalid request method', 405);
            return;
        }

        $input = file_get_contents('php://input');
        if (strlen($input) > self::MAX_PAYLOAD_SIZE) {
            $this->sendError('Payload too large', 413);
            return;
        }

        $data = json_decode($input, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            $this->sendError('Malformed JSON payload', 400);
            return;
        }

        if (!$this->validateTelemetry($data)) {
            $this->sendError('Invalid telemetry schema', 422);
            return;
        }

        if ($this->processLog($data)) {
            echo json_encode([
                'status' => 'success',
                'request_id' => $this->requestId,
                'timestamp' => microtime(true)
            ]);
        } else {
            $this->sendError('Internal persistence error', 500);
        }
    }

    private function validateTelemetry(array $data): bool
    {
        $required = ['kernel_id', 'backend', 'latency_ms', 'samples'];
        foreach ($required as $field) {
            if (!isset($data[$field])) {
                return false;
            }
        }

        return is_numeric($data['latency_ms']) && is_array($data['samples']);
    }

    private function processLog(array $data): bool
    {
        $filename = sprintf(
            '%s/%s-%s.log',
            self::LOG_DIR,
            date('Y-m-d'),
            preg_replace('/[^a-z0-9]/i', '_', $data['kernel_id'])
        );

        $entry = [
            'id' => $this->requestId,
            'time' => date('Y-m-d H:i:s') . '.' . sprintf('%03d', (microtime(true) * 1000) % 1000),
            'remote_addr' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            'agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
            'payload' => $data
        ];

        $csvLine = sprintf(
            "[%s] [%s] %s | %s | %f ms | Samples: %d\n",
            $entry['time'],
            $entry['id'],
            $data['backend'],
            $data['kernel_id'],
            $data['latency_ms'],
            count($data['samples'])
        );

        // Append to human-readable log
        file_put_contents($filename, $csvLine, FILE_APPEND | LOCK_EX);

        // Append to raw JSON stream for legacy parser compatibility
        return (bool)file_put_contents(
            self::LOG_DIR . '/stream.jsonl',
            json_encode($entry) . "\n",
            FILE_APPEND | LOCK_EX
        );
    }

    private function sendError(string $message, int $code): void
    {
        http_response_code($code);
        echo json_encode([
            'status' => 'error',
            'code' => $code,
            'message' => $message,
            'request_id' => $this->requestId
        ]);
    }
}

try {
    $handler = new LegacyHandler();
    $handler->handleRequest();
} catch (\Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'fatal',
        'message' => 'Legacy bridge failure: ' . $e->getMessage()
    ]);
}