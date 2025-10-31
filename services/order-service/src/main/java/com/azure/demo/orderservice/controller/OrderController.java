package com.azure.demo.orderservice.controller;

import com.azure.demo.orderservice.model.OrderDetails;
import com.azure.demo.orderservice.model.OrderProcessingRequest;
import com.azure.demo.orderservice.service.OrderProcessingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;
import java.util.List;
import java.util.concurrent.CompletableFuture;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private static final Logger logger = LoggerFactory.getLogger(OrderController.class);

    @Autowired
    private OrderProcessingService orderProcessingService;

    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("Order Service is healthy");
    }

    @PostMapping("/process")
    public ResponseEntity<OrderDetails> processOrder(@Valid @RequestBody OrderProcessingRequest request) {
        logger.info("Processing order for customer: {}, product: {}", 
                   request.getCustomerId(), request.getProductId());
        
        try {
            OrderDetails processedOrder = orderProcessingService.processOrder(request);
            logger.info("Successfully processed order with ID: {}", processedOrder.getId());
            return ResponseEntity.ok(processedOrder);
        } catch (Exception e) {
            logger.error("Error processing order: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @PostMapping("/process-async")
    public ResponseEntity<String> processOrderAsync(@Valid @RequestBody OrderProcessingRequest request) {
        logger.info("Async processing order for customer: {}, product: {}", 
                   request.getCustomerId(), request.getProductId());
        
        CompletableFuture.runAsync(() -> {
            try {
                orderProcessingService.processOrder(request);
                logger.info("Async order processing completed for customer: {}", request.getCustomerId());
            } catch (Exception e) {
                logger.error("Error in async order processing: {}", e.getMessage(), e);
            }
        });
        
        return ResponseEntity.accepted().body("Order processing started");
    }

    @GetMapping("/customer/{customerId}")
    public ResponseEntity<List<OrderDetails>> getOrdersByCustomer(@PathVariable String customerId) {
        logger.info("Fetching orders for customer: {}", customerId);
        
        try {
            List<OrderDetails> orders = orderProcessingService.getOrdersByCustomer(customerId);
            return ResponseEntity.ok(orders);
        } catch (Exception e) {
            logger.error("Error fetching orders for customer {}: {}", customerId, e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/{orderId}/status")
    public ResponseEntity<String> getOrderStatus(@PathVariable Long orderId) {
        logger.info("Fetching status for order: {}", orderId);
        
        try {
            String status = orderProcessingService.getOrderStatus(orderId);
            if (status != null) {
                return ResponseEntity.ok(status);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            logger.error("Error fetching order status for {}: {}", orderId, e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @PostMapping("/{orderId}/validate")
    public ResponseEntity<Boolean> validateOrder(@PathVariable Long orderId) {
        logger.info("Validating order: {}", orderId);
        
        try {
            boolean isValid = orderProcessingService.validateOrder(orderId);
            return ResponseEntity.ok(isValid);
        } catch (Exception e) {
            logger.error("Error validating order {}: {}", orderId, e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @PostMapping("/bulk-process")
    public ResponseEntity<String> processBulkOrders(@RequestBody List<OrderProcessingRequest> requests) {
        logger.info("Processing bulk orders, count: {}", requests.size());
        
        try {
            orderProcessingService.processBulkOrders(requests);
            return ResponseEntity.ok("Bulk order processing completed");
        } catch (Exception e) {
            logger.error("Error processing bulk orders: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }
}