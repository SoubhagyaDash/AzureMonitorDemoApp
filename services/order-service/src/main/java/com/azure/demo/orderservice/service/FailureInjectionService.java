package com.azure.demo.orderservice.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Random;

@Service
public class FailureInjectionService {

    private static final Logger logger = LoggerFactory.getLogger(FailureInjectionService.class);
    private final Random random = new Random();

    @Value("${failure.injection.enabled:true}")
    private boolean failureInjectionEnabled;

    @Value("${failure.injection.latency.probability:0.1}")
    private double latencyProbability;

    @Value("${failure.injection.error.probability:0.05}")
    private double errorProbability;

    @Value("${failure.injection.latency.min:100}")
    private int minLatencyMs;

    @Value("${failure.injection.latency.max:2000}")
    private int maxLatencyMs;

    public void maybeInjectFailure(String operation) {
        if (!failureInjectionEnabled) {
            return;
        }

        // Inject latency
        if (random.nextDouble() < latencyProbability) {
            injectLatency(operation);
        }

        // Inject errors
        if (random.nextDouble() < errorProbability) {
            injectError(operation);
        }
    }

    private void injectLatency(String operation) {
        int delay = minLatencyMs + random.nextInt(maxLatencyMs - minLatencyMs);
        logger.warn("Injecting {}ms latency for operation: {}", delay, operation);
        
        try {
            Thread.sleep(delay);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.warn("Latency injection interrupted for operation: {}", operation);
        }
    }

    private void injectError(String operation) {
        String[] errorTypes = {"database", "network", "timeout", "validation"};
        String errorType = errorTypes[random.nextInt(errorTypes.length)];
        
        logger.error("Injecting {} error for operation: {}", errorType, operation);
        
        switch (errorType) {
            case "database":
                throw new RuntimeException("Simulated database connection error in " + operation);
            case "network":
                throw new RuntimeException("Simulated network timeout error in " + operation);
            case "timeout":
                throw new RuntimeException("Simulated timeout error in " + operation);
            case "validation":
                throw new IllegalArgumentException("Simulated validation error in " + operation);
            default:
                throw new RuntimeException("Simulated error in " + operation);
        }
    }
}