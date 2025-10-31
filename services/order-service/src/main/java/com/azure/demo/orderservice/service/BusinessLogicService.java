package com.azure.demo.orderservice.service;

import com.azure.demo.orderservice.model.OrderDetails;
import com.azure.demo.orderservice.model.OrderProcessingRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

@Service
public class BusinessLogicService {

    private static final Logger logger = LoggerFactory.getLogger(BusinessLogicService.class);

    public void validateOrderRules(OrderProcessingRequest request) {
        logger.debug("Validating order rules for customer: {}", request.getCustomerId());

        // Simulate business rule validations
        if (request.getQuantity() > 1000) {
            throw new IllegalArgumentException("Order quantity exceeds maximum allowed limit");
        }

        if (request.getTotalAmount().compareTo(BigDecimal.valueOf(100000)) > 0) {
            throw new IllegalArgumentException("Order amount exceeds credit limit");
        }

        // Simulate customer validation
        if ("BLACKLISTED".equals(request.getCustomerId())) {
            throw new IllegalArgumentException("Customer is not eligible for orders");
        }

        logger.debug("Order rules validation passed for customer: {}", request.getCustomerId());
    }

    public boolean validateOrder(OrderDetails order) {
        logger.debug("Validating order: {}", order.getId());

        // Simulate order validation logic
        if (order.getQuantity() <= 0) {
            return false;
        }

        if (order.getTotalAmount().compareTo(BigDecimal.ZERO) <= 0) {
            return false;
        }

        if ("CANCELLED".equals(order.getStatus())) {
            return false;
        }

        logger.debug("Order validation passed for order: {}", order.getId());
        return true;
    }

    public void processLargeOrder(OrderDetails order) {
        logger.info("Processing large order: {} with quantity: {}", order.getId(), order.getQuantity());

        // Simulate additional processing for large orders
        try {
            Thread.sleep(500); // Simulate additional processing time
            
            // Update status for large orders
            order.setStatus("PENDING_APPROVAL");
            
            logger.info("Large order {} marked for approval", order.getId());
            
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.warn("Large order processing interrupted for order: {}", order.getId());
        }
    }
}