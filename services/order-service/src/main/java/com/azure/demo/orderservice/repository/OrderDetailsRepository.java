package com.azure.demo.orderservice.repository;

import com.azure.demo.orderservice.model.OrderDetails;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface OrderDetailsRepository extends JpaRepository<OrderDetails, Long> {
    
    List<OrderDetails> findByCustomerIdOrderByCreatedAtDesc(String customerId);
    
    List<OrderDetails> findByStatus(String status);
    
    List<OrderDetails> findByProductId(Integer productId);
    
    @Query("SELECT o FROM OrderDetails o WHERE o.createdAt BETWEEN :startDate AND :endDate ORDER BY o.createdAt DESC")
    List<OrderDetails> findOrdersByDateRange(@Param("startDate") LocalDateTime startDate, 
                                           @Param("endDate") LocalDateTime endDate);
    
    @Query("SELECT COUNT(o) FROM OrderDetails o WHERE o.customerId = :customerId AND o.status = :status")
    Long countByCustomerIdAndStatus(@Param("customerId") String customerId, @Param("status") String status);
    
    @Query("SELECT o FROM OrderDetails o WHERE o.processingTimeMs > :thresholdMs ORDER BY o.processingTimeMs DESC")
    List<OrderDetails> findSlowProcessingOrders(@Param("thresholdMs") Long thresholdMs);
}