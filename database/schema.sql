-- Biometric Latency Cartographer - Database Schema
-- Optimized for PostgreSQL/SQLite compatibility

-- Hardware Profiles: Defines the physical machine and input devices used during testing
CREATE TABLE IF NOT EXISTS hardware_profiles (
    profile_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_name VARCHAR(255) NOT NULL,
    os_kernel VARCHAR(100) NOT NULL, -- e.g., 'Linux 6.5.0-AMD', 'Darwin 23.1.0', 'Windows 10.0.22631'
    cpu_model VARCHAR(255) NOT NULL,
    gpu_model VARCHAR(255) NOT NULL,
    monitor_refresh_rate INTEGER NOT NULL, -- Hz
    input_polling_rate INTEGER NOT NULL,   -- Hz (e.g., 1000Hz or 8000Hz mice)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Rendering Backends: Different software stacks being benchmarked
CREATE TABLE IF NOT EXISTS rendering_backends (
    backend_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL, -- 'WebGL', 'WebGPU', 'DirectX12', 'Vulkan', 'Metal'
    framework VARCHAR(50) NOT NULL, -- 'React', 'Vue', 'Svelte', 'Native-C++', 'Flutter'
    vsync_enabled BOOLEAN DEFAULT FALSE,
    double_buffered BOOLEAN DEFAULT TRUE,
    UNIQUE(name, framework, vsync_enabled, double_buffered)
);

-- Latency Sessions: Metadata for a specific suite of tests
CREATE TABLE IF NOT EXISTS latency_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES hardware_profiles(profile_id) ON DELETE CASCADE,
    backend_id INTEGER REFERENCES rendering_backends(backend_id),
    test_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ambient_temperature_c DECIMAL(4,2),
    notes TEXT
);

-- Benchmark Samples: Individual sub-millisecond measurements
-- High density data storage
CREATE TABLE IF NOT EXISTS benchmark_samples (
    sample_id BIGSERIAL PRIMARY KEY,
    session_id UUID REFERENCES latency_sessions(session_id) ON DELETE CASCADE,
    
    -- Sub-millisecond timing stored in microseconds (μs) for precision
    -- Measured from hardware interrupt to pixel change detection (Photodiode/UI feedback)
    raw_latency_us INTEGER NOT NULL, 
    
    -- Breakdown of latency components if detectable
    kernel_dispatch_us INTEGER,
    render_pipeline_us INTEGER,
    buffer_swap_us INTEGER,
    
    -- Frame context
    frame_number BIGINT NOT NULL,
    jitter_delta_us INTEGER,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Aggregate Statistics View: For heatmap and cartography visualization
CREATE VIEW v_backend_latency_comparison AS
SELECT 
    hp.os_kernel,
    rb.name AS backend_name,
    rb.framework,
    COUNT(bs.sample_id) AS sample_count,
    ROUND(AVG(bs.raw_latency_us) / 1000.0, 3) AS avg_latency_ms,
    ROUND(MIN(bs.raw_latency_us) / 1000.0, 3) AS min_latency_ms,
    ROUND(MAX(bs.raw_latency_us) / 1000.0, 3) AS max_latency_ms,
    ROUND(STDDEV(bs.raw_latency_us) / 1000.0, 3) AS jitter_ms
FROM benchmark_samples bs
JOIN latency_sessions ls ON bs.session_id = ls.session_id
JOIN hardware_profiles hp ON ls.profile_id = hp.profile_id
JOIN rendering_backends rb ON ls.backend_id = rb.backend_id
GROUP BY hp.os_kernel, rb.name, rb.framework;

-- Indices for performance on large datasets
CREATE INDEX idx_samples_session_id ON benchmark_samples(session_id);
CREATE INDEX idx_sessions_profile_id ON latency_sessions(profile_id);
CREATE INDEX idx_profiles_kernel ON hardware_profiles(os_kernel);