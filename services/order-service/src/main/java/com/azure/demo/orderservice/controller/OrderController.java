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

    // REST endpoints for API Gateway integration
    @PostMapping
    public ResponseEntity<OrderDetails> createOrder(@Valid @RequestBody OrderProcessingRequest request) {
        logger.info("Creating order for customer: {}, product: {}", 
                   request.getCustomerId(), request.getProductId());
        
        try {
            OrderDetails order = orderProcessingService.processOrder(request);
            logger.info("Successfully created order with ID: {}", order.getId());
            return ResponseEntity.ok(order);
        } catch (Exception e) {
            logger.error("Error creating order: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping
    public ResponseEntity<List<OrderDetails>> getAllOrders() {
        logger.info("Fetching all orders");
        
        try {
            List<OrderDetails> orders = orderProcessingService.getAllOrders();
            return ResponseEntity.ok(orders);
        } catch (Exception e) {
            logger.error("Error fetching all orders: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/{orderId}")
    public ResponseEntity<OrderDetails> getOrderById(@PathVariable Long orderId) {
        logger.info("Fetching order by ID: {}", orderId);
        
        try {
            OrderDetails order = orderProcessingService.getOrderById(orderId);
            if (order != null) {
                return ResponseEntity.ok(order);
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            logger.error("Error fetching order {}: {}", orderId, e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @PutMapping("/{orderId}/status")
    public ResponseEntity<Void> updateOrderStatus(@PathVariable Long orderId, @RequestBody StatusUpdateRequest request) {
        logger.info("Updating status for order {}: {}", orderId, request.getStatus());
        
        try {
            boolean updated = orderProcessingService.updateOrderStatus(orderId, request.getStatus());
            if (updated) {
                return ResponseEntity.ok().build();
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            logger.error("Error updating order status for {}: {}", orderId, e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    @PutMapping("/{orderId}/payment")
    public ResponseEntity<Void> updateOrderPayment(@PathVariable Long orderId, @RequestBody PaymentUpdateRequest request) {
        logger.info("Updating payment for order {}: paymentId={}, status={}", 
                   orderId, request.getPaymentId(), request.getPaymentStatus());
        
        try {
            boolean updated = orderProcessingService.updateOrderPayment(
                orderId, request.getPaymentId(), request.getPaymentStatus());
            if (updated) {
                return ResponseEntity.ok().build();
            } else {
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            logger.error("Error updating order payment for {}: {}", orderId, e.getMessage(), e);
            return ResponseEntity.internalServerError().build();
        }
    }

    // Request DTOs for update endpoints
    public static class StatusUpdateRequest {
        private String status;
        
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
    }

    public static class PaymentUpdateRequest {
        private String paymentId;
        private String paymentStatus;
        
        public String getPaymentId() { return paymentId; }
        public void setPaymentId(String paymentId) { this.paymentId = paymentId; }
        public String getPaymentStatus() { return paymentStatus; }
        public void setPaymentStatus(String paymentStatus) { this.paymentStatus = paymentStatus; }
    }
}