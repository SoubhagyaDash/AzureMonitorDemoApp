package com.azure.demo.orderservice.service;

import com.azure.demo.orderservice.model.OrderDetails;
import com.azure.demo.orderservice.model.OrderProcessingRequest;
import com.azure.demo.orderservice.repository.OrderDetailsRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Random;
import java.util.concurrent.CompletableFuture;

@Service
public class OrderProcessingService {

    private static final Logger logger = LoggerFactory.getLogger(OrderProcessingService.class);
    private final Random random = new Random();

    @Autowired
    private OrderDetailsRepository orderRepository;

    @Autowired
    private FailureInjectionService failureInjectionService;

    @Autowired
    private BusinessLogicService businessLogicService;

    public OrderDetails processOrder(OrderProcessingRequest request) {
        long startTime = System.currentTimeMillis();
        
        logger.info("Starting order processing for customer: {}, product: {}", 
                   request.getCustomerId(), request.getProductId());

        try {
            // Inject potential failures for demo purposes
            failureInjectionService.maybeInjectFailure("processOrder");

            // Simulate business logic processing time based on priority
            simulateProcessingTime(request.getPriority());

            // Validate business rules
            businessLogicService.validateOrderRules(request);

            // Create order entity
            OrderDetails order = new OrderDetails(
                request.getCustomerId(),
                request.getProductId(),
                request.getQuantity(),
                request.getUnitPrice(),
                request.getTotalAmount()
            );

            // Simulate different processing paths
            if ("HIGH".equals(request.getPriority())) {
                order.setStatus("EXPEDITED");
            } else if ("URGENT".equals(request.getPriority())) {
                order.setStatus("RUSH");
            }

            // Save to database
            order = orderRepository.save(order);

            // Record processing time
            long processingTime = System.currentTimeMillis() - startTime;
            order.setProcessingTimeMs(processingTime);
            order = orderRepository.save(order);

            // Simulate additional processing for certain cases
            if (request.getQuantity() > 10) {
                businessLogicService.processLargeOrder(order);
            }

            logger.info("Order processing completed for order ID: {} in {}ms", 
                       order.getId(), processingTime);

            return order;

        } catch (Exception e) {
            logger.error("Order processing failed for customer: {}, error: {}", 
                        request.getCustomerId(), e.getMessage(), e);
            throw new RuntimeException("Order processing failed", e);
        }
    }

    public List<OrderDetails> getOrdersByCustomer(String customerId) {
        logger.info("Fetching orders for customer: {}", customerId);
        
        // Inject potential failures
        failureInjectionService.maybeInjectFailure("getOrdersByCustomer");
        
        return orderRepository.findByCustomerIdOrderByCreatedAtDesc(customerId);
    }

    public String getOrderStatus(Long orderId) {
        logger.info("Fetching status for order: {}", orderId);
        
        failureInjectionService.maybeInjectFailure("getOrderStatus");
        
        return orderRepository.findById(orderId)
                .map(OrderDetails::getStatus)
                .orElse(null);
    }

    public boolean validateOrder(Long orderId) {
        logger.info("Validating order: {}", orderId);
        
        failureInjectionService.maybeInjectFailure("validateOrder");
        
        return orderRepository.findById(orderId)
                .map(order -> businessLogicService.validateOrder(order))
                .orElse(false);
    }

    public void processBulkOrders(List<OrderProcessingRequest> requests) {
        logger.info("Processing bulk orders, count: {}", requests.size());
        
        // Process orders in parallel for demonstration
        List<CompletableFuture<Void>> futures = requests.stream()
                .map(request -> CompletableFuture.runAsync(() -> {
                    try {
                        processOrder(request);
                    } catch (Exception e) {
                        logger.error("Failed to process order in bulk for customer: {}", 
                                   request.getCustomerId(), e);
                    }
                }))
                .toList();

        // Wait for all to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        
        logger.info("Bulk order processing completed");
    }

    private void simulateProcessingTime(String priority) {
        try {
            int baseDelay = switch (priority) {
                case "URGENT" -> 50;
                case "HIGH" -> 100;
                default -> 200;
            };
            
            int variation = random.nextInt(100);
            Thread.sleep(baseDelay + variation);
            
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.warn("Processing simulation interrupted");
        }
    }
}