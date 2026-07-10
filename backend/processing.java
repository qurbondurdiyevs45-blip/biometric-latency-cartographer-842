package com.biometric.latency.service;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

@Slf4j
@Service
public class BatchProcessingService {

    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public BatchProcessingService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class LatencyMetric {
        private UUID id;
        private String kernelType;
        private String backend;
        private double deltaMs;
        private Timestamp timestamp;
    }

    @Data
    public static class AggregateReport {
        private String kernelType;
        private String backend;
        private double meanLatency;
        private double p99Latency;
        private long sampleCount;
    }

    @Async("processExecutor")
    @Transactional
    public CompletableFuture<String> processHistoricalLogs(String batchId) {
        log.info("Starting heavy-duty batch processing for ID: {}", batchId);

        try {
            // 1. Fetch raw sub-millisecond data points
            String fetchSql = "SELECT id, kernel_type, backend, delta_ms, event_time " +
                              "FROM raw_latency_logs WHERE processed = false LIMIT 10000";
            
            List<LatencyMetric> metrics = jdbcTemplate.query(fetchSql, (rs, rowNum) -> new LatencyMetric(
                UUID.fromString(rs.getString("id")),
                rs.getString("kernel_type"),
                rs.getString("backend"),
                rs.getDouble("delta_ms"),
                rs.getTimestamp("event_time")
            ));

            if (metrics.isEmpty()) {
                return CompletableFuture.completedFuture("Empty batch. No work to perform.");
            }

            // 2. Perform statistical analysis (P99 calculation and Mean)
            // Grouping and calculation logic normally handled via Streams or SQL for performance
            String analysisSql = "INSERT INTO latency_aggregates (kernel_type, backend, mean_latency, p99_latency, sample_count, window_end) " +
                                 "SELECT kernel_type, backend, AVG(delta_ms), " +
                                 "PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY delta_ms), " +
                                 "COUNT(*), CURRENT_TIMESTAMP " +
                                 "FROM raw_latency_logs WHERE processed = false " +
                                 "GROUP BY kernel_type, backend";

            jdbcTemplate.update(analysisSql);

            // 3. Mark records as processed
            String updateSql = "UPDATE raw_latency_logs SET processed = true WHERE processed = false";
            int updatedRows = jdbcTemplate.update(updateSql);

            log.info("Successfully processed {} records for Cartographer batch {}", updatedRows, batchId);
            return CompletableFuture.completedFuture("Processed " + updatedRows + " records.");

        } catch (Exception e) {
            log.error("Critical failure during batch processing: {}", e.getMessage(), e);
            throw new RuntimeException("Latency batch process failed", e);
        }
    }

    public List<AggregateReport> getLatestCartography() {
        String sql = "SELECT kernel_type, backend, mean_latency, p99_latency, sample_count " +
                     "FROM latency_aggregates ORDER BY window_end DESC LIMIT 50";
        
        return jdbcTemplate.query(sql, (rs, rowNum) -> {
            AggregateReport report = new AggregateReport();
            report.setKernelType(rs.getString("kernel_type"));
            report.setBackend(rs.getString("backend"));
            report.setMeanLatency(rs.getDouble("mean_latency"));
            report.setP99Latency(rs.getDouble("p99_latency"));
            report.setSampleCount(rs.getLong("sample_count"));
            return report;
        });
    }

    @Transactional
    public void cleanupOldLogs(int daysRetention) {
        log.info("Excision of historical logs older than {} days", daysRetention);
        String sql = "DELETE FROM raw_latency_logs WHERE event_time < CURRENT_DATE - INTERVAL '" + daysRetention + " days'";
        int deleted = jdbcTemplate.update(sql);
        log.info("Cartographer cleanup complete. Removed {} stale data points.", deleted);
    }
}