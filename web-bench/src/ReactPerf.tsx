import React, { useState, useEffect, useRef, useMemo } from 'react';

interface MetricPoint {
  timestamp: number;
  renderTime: number;
  commitTime: number;
  totalLatency: number;
}

interface ReactPerfProps {
  nodeCount?: number;
  updateInterval?: number;
  onMetricsUpdate?: (metrics: MetricPoint) => void;
}

export const ReactPerf: React.FC<ReactPerfProps> = ({
  nodeCount = 1000,
  updateInterval = 16,
  onMetricsUpdate
}) => {
  const [frame, setFrame] = useState(0);
  const startTimeRef = useRef<number>(0);
  const renderStartRef = useRef<number>(0);
  const [metrics, setMetrics] = useState<MetricPoint[]>([]);

  // Simulation of complex data structure for reconciliation
  const nodes = useMemo(() => {
    return Array.from({ length: nodeCount }).map((_, i) => ({
      id: i,
      value: Math.random()
    }));
  }, [nodeCount]);

  useEffect(() => {
    const timer = setInterval(() => {
      renderStartRef.current = performance.now();
      setFrame((f) => f + 1);
    }, updateInterval);

    return () => clearInterval(timer);
  }, [updateInterval]);

  useLayoutEffect(() => {
    const commitTime = performance.now();
    const duration = commitTime - renderStartRef.current;
    
    // Total latency from interval trigger to DOM update
    const totalLatency = commitTime - (startTimeRef.current || commitTime);

    const newMetric: MetricPoint = {
      timestamp: commitTime,
      renderTime: duration,
      commitTime: commitTime,
      totalLatency: totalLatency
    };

    if (onMetricsUpdate) {
      onMetricsUpdate(newMetric);
    }

    setMetrics((prev) => [...prev.slice(-100), newMetric]);
    startTimeRef.current = performance.now();
  }, [frame]);

  const avgLatency = metrics.length > 0
    ? metrics.reduce((acc, m) => acc + m.renderTime, 0) / metrics.length
    : 0;

  return (
    <div style={{
      padding: '20px',
      fontFamily: 'monospace',
      background: '#1a1a1a',
      color: '#00ff00',
      borderRadius: '8px',
      border: '1px solid #333'
    }}>
      <h3>React VDOM Reconciliation Mapper</h3>
      <div style={{ marginBottom: '10px' }}>
        <div>Nodes: {nodeCount}</div>
        <div>Avg Render Latency: {avgLatency.toFixed(3)}ms</div>
        <div>Current Frame: {frame}</div>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${Math.ceil(Math.sqrt(nodeCount))}, 1fr)`,
        gap: '1px',
        height: '300px',
        overflow: 'hidden',
        border: '1px solid #444'
      }}>
        {nodes.map((node) => (
          <div
            key={node.id}
            style={{
              width: '100%',
              height: '100%',
              backgroundColor: `rgba(0, 255, 0, ${(node.value * (frame % 10)) / 10})`,
              transition: 'none'
            }}
          />
        ))}
      </div>

      <div style={{ marginTop: '20px' }}>
        <canvas
          ref={(canvas) => {
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            if (!ctx) return;
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.strokeStyle = '#00ff00';
            ctx.beginPath();
            metrics.forEach((m, i) => {
              const x = (i / metrics.length) * canvas.width;
              const y = canvas.height - (m.renderTime * 10);
              if (i === 0) ctx.moveTo(x, y);
              else ctx.lineTo(x, y);
            });
            ctx.stroke();
          }}
          width={600}
          height={100}
          style={{ width: '100%', height: '100px', background: '#000' }}
        />
      </div>
    </div>
  );
};

// Polyfill for useLayoutEffect in SSR if needed
const useLayoutEffect = typeof window !== 'undefined' ? React.useLayoutEffect : React.useEffect;

export default ReactPerf;