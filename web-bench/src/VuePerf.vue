<template>
  <div class="vue-perf-container">
    <div class="stats-header">
      <h3>Vue 3 Composition API Latency Graph</h3>
      <div class="metrics">
        <span>Frame Index: {{ frameCount }}</span>
        <span>Avg Lag: {{ averageLag.toFixed(3) }}ms</span>
      </div>
    </div>

    <div class="viewport" ref="viewportRef">
      <canvas ref="canvasRef"></canvas>
    </div>

    <div class="controls">
      <button @click="resetBenchmarks" class="btn-reset">Reset Metrics</button>
      <div class="status-indicator" :class="{ active: isStressed }">
        {{ isStressed ? 'Under Load' : 'Stable' }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, watchEffect } from 'vue';

interface LatencyPoint {
  timestamp: number;
  delta: number;
}

const viewportRef = ref<HTMLElement | null>(null);
const canvasRef = ref<HTMLCanvasElement | null>(null);
const frameCount = ref(0);
const latencies = ref<LatencyPoint[]>([]);
const isStressed = ref(false);

const MAX_SAMPLES = 200;
let animationFrameId: number;
let lastTimestamp = 0;

const averageLag = computed(() => {
  if (latencies.value.length === 0) return 0;
  const sum = latencies.value.reduce((acc, p) => acc + p.delta, 0);
  return sum / latencies.value.length;
});

const resetBenchmarks = () => {
  latencies.value = [];
  frameCount.value = 0;
};

const updateVisuals = () => {
  const canvas = canvasRef.value;
  if (!canvas) return;

  const ctx = canvas.getContext('2d', { alpha: false });
  if (!ctx) return;

  const width = canvas.width;
  const height = canvas.height;

  // Clear background
  ctx.fillStyle = '#121212';
  ctx.fillRect(0, 0, width, height);

  // Draw Grid
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 1;
  for (let i = 0; i < 10; i++) {
    const y = (height / 10) * i;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }

  // Draw Latency Path
  if (latencies.value.length > 2) {
    ctx.beginPath();
    ctx.strokeStyle = '#00ffcc';
    ctx.lineWidth = 2;
    
    const step = width / MAX_SAMPLES;
    latencies.value.forEach((p, idx) => {
      const x = idx * step;
      // Scale: 16.67ms (60fps) is mid-point
      const y = height - (p.delta * (height / 33.33));
      
      if (idx === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }
};

const tick = (timestamp: number) => {
  if (lastTimestamp !== 0) {
    const delta = timestamp - lastTimestamp;
    
    // Track micro-stutters in reactive state
    latencies.value.push({ timestamp, delta });
    if (latencies.value.length > MAX_SAMPLES) {
      latencies.value.shift();
    }
    
    frameCount.value++;
    isStressed.value = delta > 17.5; // Threshold for dropped frames at 60Hz
  }
  
  lastTimestamp = timestamp;
  updateVisuals();
  animationFrameId = requestAnimationFrame(tick);
};

onMounted(() => {
  const canvas = canvasRef.value;
  if (canvas && viewportRef.value) {
    canvas.width = viewportRef.value.clientWidth;
    canvas.height = viewportRef.value.clientHeight;
  }
  animationFrameId = requestAnimationFrame(tick);
});

onUnmounted(() => {
  cancelAnimationFrame(animationFrameId);
});
</script>

<style scoped>
.vue-perf-container {
  display: flex;
  flex-direction: column;
  background: #1e1e1e;
  color: #e0e0e0;
  padding: 1rem;
  border-radius: 8px;
  font-family: 'Inter', system-ui, sans-serif;
  height: 400px;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
}

.stats-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.metrics {
  display: flex;
  gap: 1.5rem;
  font-family: 'JetBrains Mono', monospace;
  font-size: 0.9rem;
}

.viewport {
  flex-grow: 1;
  background: #000;
  border: 1px solid #333;
  position: relative;
  overflow: hidden;
}

canvas {
  width: 100%;
  height: 100%;
  display: block;
}

.controls {
  margin-top: 1rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.btn-reset {
  background: #ff4757;
  border: none;
  color: white;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  cursor: pointer;
  font-weight: 600;
  transition: opacity 0.2s;
}

.btn-reset:hover {
  opacity: 0.8;
}

.status-indicator {
  padding: 0.25rem 0.75rem;
  border-radius: 20px;
  font-size: 0.75rem;
  text-transform: uppercase;
  background: #2f3542;
}

.status-indicator.active {
  background: #ffa502;
  color: #000;
  font-weight: bold;
}
</style>