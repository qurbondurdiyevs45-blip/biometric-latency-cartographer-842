use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use std::collections::VecDeque;
use std::sync::Mutex;
use std::net::UdpSocket;

#[derive(Debug, Clone, Copy)]
pub struct LatencySignal {
    pub sequence: u64,
    pub timestamp_us: u128,
    pub event_type: u8, // 0: Input, 1: Kernel Acknowledge, 2: Frame Buffer Swap
}

pub struct DiagnosticEngine {
    is_running: Arc<AtomicBool>,
    signal_buffer: Arc<Mutex<VecDeque<LatencySignal>>>,
    telemetry_addr: String,
}

impl DiagnosticEngine {
    pub fn new(telemetry_addr: &str) -> Self {
        Self {
            is_running: Arc::new(AtomicBool::new(false)),
            signal_buffer: Arc::new(Mutex::new(VecDeque::with_capacity(1024))),
            telemetry_addr: telemetry_addr.to_string(),
        }
    }

    pub fn start(&self) {
        self.is_running.store(true, Ordering::SeqCst);
        let running = Arc::clone(&self.is_running);
        let buffer = Arc::clone(&self.signal_buffer);
        let addr = self.telemetry_addr.clone();

        thread::spawn(move || {
            let socket = UdpSocket::bind("0.0.0.0:0").expect("Failed to bind UDP socket");
            let mut sequence_counter: u64 = 0;
            
            println!("Biometric Engine: High-precision polling started on core 0.");

            while running.load(Ordering::SeqCst) {
                let start_tick = Instant::now();
                
                // Capture high-precision timestamp immediately
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_micros();

                let signal = LatencySignal {
                    sequence: sequence_counter,
                    timestamp_us: now,
                    event_type: 0, 
                };

                {
                    let mut signals = buffer.lock().expect("Lock poisoned");
                    if signals.len() >= 1024 {
                        signals.pop_front();
                    }
                    signals.push_back(signal);
                }

                // Prepare telemetry packet (Binary format: 8 bytes seq, 16 bytes ts, 1 byte type)
                let mut packet = Vec::with_capacity(25);
                packet.extend_from_slice(&signal.sequence.to_le_bytes());
                packet.extend_from_slice(&signal.timestamp_us.to_le_bytes());
                packet.push(signal.event_type);

                let _ = socket.send_to(&packet, &addr);

                sequence_counter += 1;

                // Busy-wait for sub-millisecond precision instead of thread::sleep
                // Target: 2000Hz polling (500 microseconds)
                while start_tick.elapsed() < Duration::from_micros(500) {
                    std::hint::spin_loop();
                }
            }
        });
    }

    pub fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
    }

    pub fn get_metrics(&self) -> Vec<LatencySignal> {
        let signals = self.signal_buffer.lock().expect("Lock poisoned");
        signals.iter().cloned().collect()
    }
}

fn main() {
    let engine = DiagnosticEngine::new("127.0.0.1:9001");
    engine.start();

    println!("Biometric Latency Cartographer: Core Engine Active");
    println!("Streaming microsecond-precise telemetry to 127.0.0.1:9001");

    // Keep the main thread alive to allow the engine to route signals
    let (tx, rx) = std::sync::mpsc::channel::<()>();
    ctrlc::set_handler(move || {
        println!("\nShutdown signal received.");
        tx.send(()).unwrap();
    }).expect("Error setting Ctrl-C handler");

    rx.recv().unwrap();
    engine.stop();
    println!("Engine stopped gracefully.");
}

mod tests {
    #[test]
    fn test_timing_precision() {
        let start = std::time::Instant::now();
        let ts_start = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_micros();
        std::thread::sleep(std::time::Duration::from_millis(10));
        let ts_end = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_micros();
        let elapsed = ts_end - ts_start;
        assert!(elapsed >= 10000 && elapsed < 15000);
    }
}