<script lang="ts">
  import { onMount, afterUpdate } from 'svelte';

  export let name: string = "Svelte (Compiled No-VDOM)";
  
  let frameCount = 0;
  let startTime = performance.now();
  let latestLatency = 0;
  let active = false;
  let dataPoints: number[] = [];
  let rafId: number;

  const sampleSize = 100;

  function toggleTest() {
    active = !active;
    if (active) {
      startTime = performance.now();
      frameCount = 0;
      dataPoints = [];
      runLoop();
    } else {
      cancelAnimationFrame(rafId);
    }
  }

  function runLoop() {
    if (!active) return;
    
    const now = performance.now();
    // Simulate high-frequency UI updates to measure overhead
    frameCount++;
    
    // Logic: Force a reactive change every frame
    latestLatency = performance.now() - now;
    
    rafId = requestAnimationFrame(runLoop);
  }

  afterUpdate(() => {
    if (active && frameCount > 0) {
      const renderEnd = performance.now();
      const drift = renderEnd - performance.now(); // Measuring micro-task queue speed
      dataPoints = [...dataPoints.slice(-(sampleSize - 1)), renderEnd - startTime];
      startTime = renderEnd;
    }
  });

  onMount(() => {
    return () => cancelAnimationFrame(rafId);
  });

  $: averageLatency = dataPoints.length 
    ? (dataPoints.reduce((a, b) => a + b, 0) / dataPoints.length).toFixed(4) 
    : "0.0000";

</script>

<div class="perf-container">
  <header>
    <h3>{name}</h3>
    <div class="status" class:active>{active ? 'RUNNING' : 'IDLE'}</div>
  </header>

  <div class="metrics">
    <div class="metric-box">
      <span class="label">Avg Render Delta</span>
      <span class="value">{averageLatency}ms</span>
    </div>
    <div class="metric-box">
      <span class="label">Frames Tracked</span>
      <span class="value">{frameCount}</span>
    </div>
  </div>

  <div class="visualizer">
    {#each dataPoints as point, i}
      <div 
        class="bar" 
        style="height: {Math.min(point * 50, 100)}%; left: {(i / sampleSize) * 100}%"
      ></div>
    {/each}
  </div>

  <button on:click={toggleTest}>
    {active ? 'Stop Diagnostic' : 'Start Diagnostic'}
  </button>
</div>

<style>
  .perf-container {
    background: #1a1a1a;
    color: #00ff41;
    padding: 1.5rem;
    border-radius: 8px;
    font-family: 'JetBrains Mono', 'Fira Code', monospace;
    border: 1px solid #333;
    width: 320px;
  }

  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
  }

  h3 {
    margin: 0;
    font-size: 0.9rem;
    text-transform: uppercase;
  }

  .status {
    font-size: 0.7rem;
    padding: 2px 6px;
    border: 1px solid #444;
  }

  .status.active {
    background: #004400;
    border-color: #00ff41;
    box-shadow: 0 0 5px #00ff41;
  }

  .metrics {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-bottom: 1rem;
  }

  .metric-box {
    background: #000;
    padding: 0.5rem;
    border-radius: 4px;
  }

  .label {
    display: block;
    font-size: 0.6rem;
    color: #888;
  }

  .value {
    font-size: 1.1rem;
    font-weight: bold;
  }

  .visualizer {
    height: 60px;
    background: #000;
    position: relative;
    margin-bottom: 1rem;
    overflow: hidden;
    border-bottom: 1px solid #00ff41;
  }

  .bar {
    position: absolute;
    bottom: 0;
    width: 2px;
    background: #00ff41;
    transition: height 0.05s ease;
  }

  button {
    width: 100%;
    background: transparent;
    border: 1px solid #00ff41;
    color: #00ff41;
    padding: 0.5rem;
    cursor: pointer;
    text-transform: uppercase;
    font-size: 0.8rem;
    transition: all 0.2s;
  }

  button:hover {
    background: #00ff41;
    color: #000;
  }
</style>