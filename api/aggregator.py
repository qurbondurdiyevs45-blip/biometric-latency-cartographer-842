import uvicorn
import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any
from scipy import stats

app = FastAPI(title="Biometric Latency Aggregator")

class LatencySamples(BaseModel):
    kernel_id: str
    backend: str
    samples_ms: List[float]

class LatencyMetrics(BaseModel):
    mean: float
    median: float
    std_dev: float
    variance: float
    min_val: float
    max_val: float
    p95: float
    p99: float
    jitter: float
    outlier_count: int
    is_stable: bool

def calculate_jitter(samples: np.ndarray) -> float:
    """Calculates the average difference between consecutive samples."""
    if len(samples) < 2:
        return 0.0
    return float(np.mean(np.abs(np.diff(samples))))

def detect_outliers(samples: np.ndarray) -> int:
    """Uses Z-score to determine number of statistical outliers."""
    if len(samples) < 3:
        return 0
    z_scores = np.abs(stats.zscore(samples))
    return int(np.sum(z_scores > 3))

@app.post("/analyze", response_model=LatencyMetrics)
async def analyze_latency(data: LatencySamples):
    if not data.samples_ms:
        raise HTTPException(status_code=400, detail="Sample list cannot be empty")

    samples = np.array(data.samples_ms)
    
    # Statistical calculations
    mean_val = np.mean(samples)
    std_dev = np.std(samples)
    jitter = calculate_jitter(samples)
    outliers = detect_outliers(samples)
    
    # Stability heuristic: Standard deviation < 5% of mean and low jitter
    is_stable = bool(std_dev < (mean_val * 0.05) and jitter < 1.0)

    metrics = LatencyMetrics(
        mean=float(mean_val),
        median=float(np.median(samples)),
        std_dev=float(std_dev),
        variance=float(np.var(samples)),
        min_val=float(np.min(samples)),
        max_val=float(np.max(samples)),
        p95=float(np.percentile(samples, 95)),
        p99=float(np.percentile(samples, 99)),
        jitter=jitter,
        outlier_count=outliers,
        is_stable=is_stable
    )

    return metrics

@app.get("/health")
async def health_check():
    return {"status": "online", "engine": "numpy", "scipy_enabled": True}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)