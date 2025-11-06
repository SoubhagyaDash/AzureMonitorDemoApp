"""
Event Processor Service - Python

Processes events from Azure Event Hub using OSS OpenTelemetry SDK.
This service demonstrates distributed tracing across the event-driven architecture.
"""

import asyncio
import json
import logging
import os
import random
import time
from typing import Dict, Any, Optional
from datetime import datetime

import structlog
from azure.eventhub import EventData
from azure.eventhub.aio import EventHubConsumerClient, EventHubProducerClient
from azure.cosmos.aio import CosmosClient
from redis.asyncio import Redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# OpenTelemetry imports
from opentelemetry import trace, metrics, baggage
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
# from opentelemetry.instrumentation.azure_eventhub import AzureEventHubInstrumentor  # Not available
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.semconv.trace import SpanAttributes
from opentelemetry.trace import Status, StatusCode

# Configure OpenTelemetry
def setup_telemetry():
    """Setup OpenTelemetry with OSS SDK for OTLP export to Azure Monitor"""
    
    # Read OTLP endpoints from environment (will be injected by Azure Monitor)
    otlp_traces_endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
    otlp_metrics_endpoint = os.getenv("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT")
    otlp_logs_endpoint = os.getenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT")
    
    # Configure resource attributes
    resource = Resource.create({
        "service.name": "event-processor",
        "service.version": "1.0.0",
        "deployment.environment": os.getenv("ENVIRONMENT", "production"),
        "deployment.platform": "kubernetes",
        "deployment.cloud": "azure"
    })
    
    # Configure tracing
    trace_provider = TracerProvider(resource=resource)
    
    # Add OTLP span exporter if endpoint is configured
    if otlp_traces_endpoint:
        otlp_exporter = OTLPSpanExporter(
            endpoint=otlp_traces_endpoint,
            insecure=True
        )
        span_processor = BatchSpanProcessor(otlp_exporter)
        trace_provider.add_span_processor(span_processor)
    
    trace.set_tracer_provider(trace_provider)
    
    # Configure metrics
    if otlp_metrics_endpoint:
        metric_reader = PeriodicExportingMetricReader(
            OTLPMetricExporter(
                endpoint=otlp_metrics_endpoint,
                insecure=True
            ),
            export_interval_millis=30000
        )
        metrics.set_meter_provider(MeterProvider(
            resource=resource,
            metric_readers=[metric_reader]
        ))
    else:
        metrics.set_meter_provider(MeterProvider(resource=resource))
    
    # Configure logging
    if otlp_logs_endpoint:
        logger_provider = LoggerProvider(resource=resource)
        logger_provider.add_log_record_processor(
            BatchLogRecordProcessor(
                OTLPLogExporter(
                    endpoint=otlp_logs_endpoint,
                    insecure=True
                )
            )
        )
        
        # Add OTLP handler to Python logging
        handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
        logging.getLogger().addHandler(handler)
    
    # Enable automatic instrumentation
    # AzureEventHubInstrumentor().instrument()  # Not available in this version
    RequestsInstrumentor().instrument()
    RedisInstrumentor().instrument()

# Setup telemetry
setup_telemetry()

# Get tracer and meter
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# Custom metrics
events_processed_counter = meter.create_counter(
    "events_processed_total",
    description="Total number of events processed"
)

processing_duration_histogram = meter.create_histogram(
    "event_processing_duration_seconds",
    description="Time spent processing events"
)

errors_counter = meter.create_counter(
    "event_processing_errors_total",
    description="Total number of processing errors"
)

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.add_log_level,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.make_filtering_bound_logger(20),
    logger_factory=structlog.PrintLoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Configuration
class Config:
    EVENT_HUB_CONNECTION_STRING = os.getenv("EVENT_HUB_CONNECTION_STRING", "")
    EVENT_HUB_NAME = os.getenv("EVENT_HUB_NAME", "orders")
    CONSUMER_GROUP = os.getenv("EVENT_HUB_CONSUMER_GROUP", "$Default")
    
    COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT", "")
    COSMOS_KEY = os.getenv("COSMOS_KEY", "")
    COSMOS_DATABASE = os.getenv("COSMOS_DATABASE", "EventProcessing")
    COSMOS_CONTAINER = os.getenv("COSMOS_CONTAINER", "ProcessedEvents")
    
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
    
    # Failure injection settings
    FAILURE_INJECTION_ENABLED = os.getenv("FAILURE_INJECTION_ENABLED", "true").lower() == "true"
    LATENCY_INJECTION_PROBABILITY = float(os.getenv("LATENCY_INJECTION_PROBABILITY", "0.1"))
    ERROR_INJECTION_PROBABILITY = float(os.getenv("ERROR_INJECTION_PROBABILITY", "0.05"))

config = Config()

# Pydantic models
class EventProcessingResult(BaseModel):
    event_id: str
    event_type: str
    processing_status: str
    processing_time_ms: float
    timestamp: datetime

class FailureInjectionConfig(BaseModel):
    enabled: bool = True
    latency_probability: float = 0.1
    error_probability: float = 0.05

# FastAPI app for health checks and control endpoints
app = FastAPI(title="Event Processor Service", version="1.0.0")

class EventProcessor:
    def __init__(self):
        self.redis_client: Optional[Redis] = None
        self.cosmos_client: Optional[CosmosClient] = None
        self.cosmos_container = None
        self.consumer_client: Optional[EventHubConsumerClient] = None
        self.producer_client: Optional[EventHubProducerClient] = None
        self.running = False

    async def initialize(self):
        """Initialize all clients and connections"""
        with tracer.start_as_current_span("event_processor_initialize") as span:
            try:
                # Initialize Redis
                self.redis_client = Redis.from_url(config.REDIS_URL)
                await self.redis_client.ping()
                span.set_attribute("redis.initialized", True)
                
                # Initialize Cosmos DB
                if config.COSMOS_ENDPOINT and config.COSMOS_KEY:
                    self.cosmos_client = CosmosClient(config.COSMOS_ENDPOINT, config.COSMOS_KEY)
                    database = self.cosmos_client.get_database_client(config.COSMOS_DATABASE)
                    self.cosmos_container = database.get_container_client(config.COSMOS_CONTAINER)
                    span.set_attribute("cosmos.initialized", True)
                
                # Initialize Event Hub clients
                if config.EVENT_HUB_CONNECTION_STRING:
                    self.consumer_client = EventHubConsumerClient.from_connection_string(
                        config.EVENT_HUB_CONNECTION_STRING,
                        consumer_group=config.CONSUMER_GROUP,
                        eventhub_name=config.EVENT_HUB_NAME
                    )
                    
                    self.producer_client = EventHubProducerClient.from_connection_string(
                        config.EVENT_HUB_CONNECTION_STRING,
                        eventhub_name=config.EVENT_HUB_NAME
                    )
                    span.set_attribute("eventhub.initialized", True)
                
                logger.info("Event processor initialized successfully")
                
            except Exception as e:
                span.record_exception(e)
                span.set_status(Status(StatusCode.ERROR, str(e)))
                logger.error("Failed to initialize event processor", error=str(e))
                raise

    async def process_events(self):
        """Main event processing loop"""
        if not self.consumer_client:
            logger.error("Event Hub consumer client not initialized")
            return

        self.running = True
        logger.info("Starting event processing")

        async def on_event_batch(partition_context, event_batch):
            with tracer.start_as_current_span("process_event_batch") as span:
                span.set_attribute("partition.id", partition_context.partition_id)
                span.set_attribute("batch.size", len(event_batch))
                
                for event in event_batch:
                    await self.process_single_event(event, partition_context)
                
                await partition_context.update_checkpoint()

        async def on_error(partition_context, error):
            logger.error("Event processing error", 
                        partition_id=partition_context.partition_id, 
                        error=str(error))
            errors_counter.add(1, {"error_type": "partition_error"})

        try:
            async with self.consumer_client:
                await self.consumer_client.receive_batch(
                    on_event_batch=on_event_batch,
                    on_error=on_error,
                    max_batch_size=10,
                    max_wait_time=5
                )
        except Exception as e:
            logger.error("Event processing loop failed", error=str(e))
            errors_counter.add(1, {"error_type": "consumer_error"})

    async def process_single_event(self, event: EventData, partition_context):
        """Process a single event with tracing and metrics"""
        start_time = time.time()
        
        with tracer.start_as_current_span("process_single_event") as span:
            try:
                # Extract event data
                event_body = json.loads(event.body_as_str())
                event_type = event.properties.get("EventType", "Unknown")
                source = event.properties.get("Source", "Unknown")
                
                # Set span attributes
                span.set_attribute("event.type", event_type)
                span.set_attribute("event.source", source)
                span.set_attribute("partition.id", partition_context.partition_id)
                
                # Add baggage for distributed context
                baggage.set_baggage("event.type", event_type)
                baggage.set_baggage("event.source", source)
                
                logger.info("Processing event", 
                           event_type=event_type, 
                           source=source,
                           partition=partition_context.partition_id)
                
                # Inject failures for demo purposes
                await self.maybe_inject_failure("process_event")
                
                # Process based on event type
                if event_type == "OrderCreated":
                    await self.handle_order_created(event_body, span)
                elif event_type == "OrderStatusUpdated":
                    await self.handle_order_status_updated(event_body, span)
                else:
                    await self.handle_generic_event(event_body, span)
                
                # Store in Cosmos DB
                if self.cosmos_container:
                    await self.store_processed_event(event_body, event_type, span)
                
                # Cache recent events in Redis
                if self.redis_client:
                    await self.cache_event_summary(event_body, event_type)
                
                # Record metrics
                processing_time = time.time() - start_time
                processing_duration_histogram.record(processing_time)
                events_processed_counter.add(1, {"event_type": event_type, "source": source})
                
                span.set_attribute("processing.duration_ms", processing_time * 1000)
                span.set_status(Status(StatusCode.OK))
                
                logger.info("Event processed successfully", 
                           event_type=event_type,
                           processing_time_ms=processing_time * 1000)
                
            except Exception as e:
                processing_time = time.time() - start_time
                span.record_exception(e)
                span.set_status(Status(StatusCode.ERROR, str(e)))
                errors_counter.add(1, {"error_type": "processing_error"})
                
                logger.error("Event processing failed", 
                           error=str(e),
                           processing_time_ms=processing_time * 1000)

    async def handle_order_created(self, event_data: Dict[str, Any], span):
        """Handle OrderCreated events"""
        with tracer.start_as_current_span("handle_order_created") as child_span:
            order_id = event_data.get("OrderId")
            customer_id = event_data.get("CustomerId")
            
            child_span.set_attribute("order.id", str(order_id))
            child_span.set_attribute("order.customer_id", customer_id)
            
            # Simulate order processing logic
            await asyncio.sleep(random.uniform(0.1, 0.5))
            
            # Simulate sending notification
            await self.send_notification(customer_id, f"Order {order_id} created", child_span)
            
            logger.info("Order created event processed", order_id=order_id, customer_id=customer_id)

    async def handle_order_status_updated(self, event_data: Dict[str, Any], span):
        """Handle OrderStatusUpdated events"""
        with tracer.start_as_current_span("handle_order_status_updated") as child_span:
            order_id = event_data.get("OrderId")
            status = event_data.get("Status")
            
            child_span.set_attribute("order.id", str(order_id))
            child_span.set_attribute("order.status", status)
            
            # Simulate status update processing
            await asyncio.sleep(random.uniform(0.05, 0.2))
            
            logger.info("Order status updated event processed", order_id=order_id, status=status)

    async def handle_generic_event(self, event_data: Dict[str, Any], span):
        """Handle generic events"""
        with tracer.start_as_current_span("handle_generic_event") as child_span:
            # Simulate generic processing
            await asyncio.sleep(random.uniform(0.02, 0.1))
            
            logger.info("Generic event processed", event_keys=list(event_data.keys()))

    async def send_notification(self, customer_id: str, message: str, span):
        """Simulate sending notifications"""
        with tracer.start_as_current_span("send_notification") as child_span:
            child_span.set_attribute("notification.customer_id", customer_id)
            child_span.set_attribute("notification.message", message)
            
            # Simulate notification delay
            await asyncio.sleep(random.uniform(0.01, 0.05))
            
            logger.info("Notification sent", customer_id=customer_id, message=message)

    async def store_processed_event(self, event_data: Dict[str, Any], event_type: str, span):
        """Store processed event in Cosmos DB"""
        with tracer.start_as_current_span("store_processed_event") as child_span:
            try:
                # Use OrderId from event data as unique identifier to prevent duplicates
                order_id = event_data.get("OrderId", f"unknown_{int(time.time() * 1000)}")
                
                document = {
                    "id": f"{event_type}_{order_id}",
                    "eventType": event_type,
                    "eventData": event_data,
                    "processedAt": datetime.utcnow().isoformat(),
                    "processingService": "event-processor"
                }
                
                # Use upsert to handle duplicate events gracefully (event replay from EventHub)
                await self.cosmos_container.upsert_item(document)
                child_span.set_attribute("cosmos.document_id", document["id"])
                
                logger.info("Event stored in Cosmos DB", document_id=document["id"], event_type=event_type, order_id=order_id)
                
            except Exception as e:
                # Conflict errors on upsert indicate concurrent partition processing - this is expected
                error_str = str(e)
                if "Conflict" in error_str and "409" in error_str:
                    logger.warning("Duplicate event already processed (concurrent partition)", 
                                 document_id=f"{event_type}_{order_id}", 
                                 event_type=event_type,
                                 order_id=order_id)
                    child_span.set_attribute("cosmos.duplicate_event", True)
                else:
                    child_span.record_exception(e)
                    logger.error("Failed to store event in Cosmos DB", error=error_str, event_type=event_type)

    async def cache_event_summary(self, event_data: Dict[str, Any], event_type: str):
        """Cache event summary in Redis"""
        try:
            cache_key = f"recent_events:{event_type}"
            event_summary = {
                "timestamp": datetime.utcnow().isoformat(),
                "type": event_type,
                "data": event_data
            }
            
            await self.redis_client.lpush(cache_key, json.dumps(event_summary))
            await self.redis_client.ltrim(cache_key, 0, 99)  # Keep last 100 events
            await self.redis_client.expire(cache_key, 3600)  # Expire in 1 hour
            
        except Exception as e:
            logger.error("Failed to cache event summary", error=str(e))

    async def maybe_inject_failure(self, operation: str):
        """Inject failures for demo purposes"""
        if not config.FAILURE_INJECTION_ENABLED:
            return
        
        # Inject latency
        if random.random() < config.LATENCY_INJECTION_PROBABILITY:
            delay = random.uniform(0.1, 2.0)
            logger.warning("Injecting latency", operation=operation, delay_seconds=delay)
            await asyncio.sleep(delay)
        
        # Inject errors
        if random.random() < config.ERROR_INJECTION_PROBABILITY:
            error_types = ["network", "database", "processing", "timeout"]
            error_type = random.choice(error_types)
            logger.error("Injecting error", operation=operation, error_type=error_type)
            raise Exception(f"Simulated {error_type} error in {operation}")

# Global event processor instance
event_processor = EventProcessor()

# FastAPI endpoints
@app.on_event("startup")
async def startup_event():
    await event_processor.initialize()
    # Auto-start event processing
    if not event_processor.running:
        asyncio.create_task(event_processor.process_events())
        logger.info("Event processing auto-started on startup")

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "event-processor",
        "timestamp": datetime.utcnow().isoformat(),
        "running": event_processor.running
    }

@app.get("/metrics")
async def get_metrics():
    """Get current metrics"""
    return {
        "events_processed": "See Prometheus endpoint",
        "processing_errors": "See Prometheus endpoint",
        "service_uptime": time.time()
    }

@app.post("/start-processing")
async def start_processing():
    """Start event processing"""
    if event_processor.running:
        raise HTTPException(status_code=400, detail="Event processing already running")
    
    asyncio.create_task(event_processor.process_events())
    return {"message": "Event processing started"}

@app.get("/failure-injection")
async def get_failure_injection_config():
    """Get current failure injection configuration"""
    return {
        "enabled": config.FAILURE_INJECTION_ENABLED,
        "latency_probability": config.LATENCY_INJECTION_PROBABILITY,
        "error_probability": config.ERROR_INJECTION_PROBABILITY,
        "service": "event-processor",
        "last_updated": datetime.utcnow().isoformat()
    }

@app.post("/failure-injection")
async def configure_failure_injection(config_update: FailureInjectionConfig):
    """Configure failure injection settings"""
    global config
    config.FAILURE_INJECTION_ENABLED = config_update.enabled
    config.LATENCY_INJECTION_PROBABILITY = config_update.latency_probability
    config.ERROR_INJECTION_PROBABILITY = config_update.error_probability
    
    return {
        "message": "Failure injection configuration updated",
        "config": config_update.dict(),
        "timestamp": datetime.utcnow().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)