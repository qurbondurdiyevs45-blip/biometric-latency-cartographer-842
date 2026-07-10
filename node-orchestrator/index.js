const cluster = require('cluster');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const NUM_WORKERS = os.cpus().length;
const BASE_PORT = 4000;
const REGISTRY = new Map();

if (cluster.isMaster) {
    console.log(`[Biometric Latency Cartographer] Orchestrator started on PID ${process.pid}`);
    console.log(`[Orchestrator] Spawning ${NUM_WORKERS} kernel-diagnostic nodes...`);

    for (let i = 0; i < NUM_WORKERS; i++) {
        const workerPort = BASE_PORT + i;
        const worker = cluster.fork({ WORKER_PORT: workerPort });
        REGISTRY.set(worker.id, { port: workerPort, state: 'initializing' });
    }

    cluster.on('message', (worker, message) => {
        if (message.type === 'STATUS_UPDATE') {
            REGISTRY.set(worker.id, { ...REGISTRY.get(worker.id), ...message.data });
            console.log(`[Node ${worker.id}] Port ${REGISTRY.get(worker.id).port} status: ${message.data.status}`);
        }
    });

    cluster.on('exit', (worker, code, signal) => {
        console.warn(`[Orchestrator] Worker ${worker.id} died (${signal || code}). Restarting...`);
        const oldPort = REGISTRY.get(worker.id).port;
        REGISTRY.delete(worker.id);
        const newWorker = cluster.fork({ WORKER_PORT: oldPort });
        REGISTRY.set(newWorker.id, { port: oldPort, state: 'restarting' });
    });

    // Control Plane API
    http.createServer((req, res) => {
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Access-Control-Allow-Origin', '*');

        if (req.url === '/health') {
            const health = Array.from(REGISTRY.entries()).map(([id, data]) => ({ id, ...data }));
            res.writeHead(200);
            res.end(JSON.stringify({ status: 'active', workers: health }));
        } else {
            res.writeHead(404);
            res.end(JSON.stringify({ error: 'Not Found' }));
        }
    }).listen(3999, () => {
        console.log('[Orchestrator] Control Plane listening on http://localhost:3999');
    });

} else {
    const port = process.env.WORKER_PORT;
    
    // Each worker starts a sub-process for high-precision kernel timing
    // This simulates the interface between the Node ecosystem and local OS drivers
    const server = http.createServer((req, res) => {
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Content-Type', 'application/json');

        if (req.url === '/latency-pulse') {
            const start = process.hrtime.bigint();
            
            // Artificial load to test scheduler preemption
            let sum = 0;
            for(let i = 0; i < 1e6; i++) sum += Math.sqrt(i);

            const end = process.hrtime.bigint();
            const processingNanoseconds = Number(end - start);
            
            res.writeHead(200);
            res.end(JSON.stringify({
                timestamp: Date.now(),
                kernel_latency_ns: processingNanoseconds,
                node_id: cluster.worker.id,
                port: port,
                load_factor: sum > 0 ? 'nominal' : 'idle'
            }));
        } else {
            res.writeHead(200);
            res.end(JSON.stringify({ worker_id: cluster.worker.id, active: true }));
        }
    });

    server.listen(port, '127.0.0.1', () => {
        process.send({
            type: 'STATUS_UPDATE',
            data: { status: 'online', pid: process.pid }
        });
    });

    // Handle graceful shutdown
    process.on('SIGTERM', () => {
        server.close(() => {
            process.exit(0);
        });
    });
}