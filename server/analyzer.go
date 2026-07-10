package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

// LatencySample represents a single timing point from a client node
type LatencySample struct {
	NodeID       string  `json:"node_id"`
	KernelType   string  `json:"kernel_type"`
	Backend      string  `json:"backend"`
	Timestamp    int64   `json:"timestamp"`    // Unix Nanoseconds
	InputLatency float64 `json:"input_latency"` // Milliseconds
}

// AggregationWindow holds stats for a specific time slice
type AggregationWindow struct {
	StartTime  int64              `json:"start_time"`
	EndTime    int64              `json:"end_time"`
	SampleCount int                `json:"sample_count"`
	AverageMs  float64            `json:"average_ms"`
	MinMs      float64            `json:"min_ms"`
	MaxMs      float64            `json:"max_ms"`
	NodesActive int                `json:"nodes_active"`
	Breakdown  map[string]float64 `json:"kernel_breakdown"`
}

type AnalyzerService struct {
	mu         sync.RWMutex
	samples    []LatencySample
	windowSize time.Duration
}

func NewAnalyzerService() *AnalyzerService {
	return &AnalyzerService{
		samples:    make([]LatencySample, 0),
		windowSize: 1 * time.Second,
	}
}

func (s *AnalyzerService) HandleIngest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var sample LatencySample
	if err := json.NewDecoder(r.Body).Decode(&sample); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if sample.Timestamp == 0 {
		sample.Timestamp = time.Now().UnixNano()
	}

	s.mu.Lock()
	s.samples = append(s.samples, sample)
	// Keep a rolling buffer of the last 10,000 samples to prevent memory exhaustion
	if len(s.samples) > 10000 {
		s.samples = s.samples[len(s.samples)-10000:]
	}
	s.mu.Unlock()

	w.WriteHeader(http.StatusAccepted)
}

func (s *AnalyzerService) HandleReport(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if len(s.samples) == 0 {
		json.NewEncoder(w).Encode(AggregationWindow{})
		return
	}

	now := time.Now().UnixNano()
	lookback := now - s.windowSize.Nanoseconds()

	var total float64
	var count int
	min := 999999.0
	max := 0.0
	nodes := make(map[string]bool)
	kernels := make(map[string][]float64)

	for _, sample := range s.samples {
		if sample.Timestamp > lookback {
			total += sample.InputLatency
			count++
			nodes[sample.NodeID] = true
			kernels[sample.KernelType] = append(kernels[sample.KernelType], sample.InputLatency)

			if sample.InputLatency < min {
				min = sample.InputLatency
			}
			if sample.InputLatency > max {
				max = sample.InputLatency
			}
		}
	}

	if count == 0 {
		json.NewEncoder(w).Encode(AggregationWindow{StartTime: lookback, EndTime: now})
		return
	}

	breakdown := make(map[string]float64)
	for k, vals := range kernels {
		var kSum float64
		for _, v := range vals {
			kSum += v
		}
		breakdown[k] = kSum / float64(len(vals))
	}

	report := AggregationWindow{
		StartTime:   lookback,
		EndTime:     now,
		SampleCount: count,
		AverageMs:   total / float64(count),
		MinMs:       min,
		MaxMs:       max,
		NodesActive: len(nodes),
		Breakdown:   breakdown,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(report)
}

func main() {
	service := NewAnalyzerService()

	http.HandleFunc("/ingest", service.HandleIngest)
	http.HandleFunc("/report", service.HandleReport)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "OK")
	})

	port := ":8080"
	log.Printf("Biometric Latency Cartographer: Aggregator Service starting on %s...", port)
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatal(err)
	}
}