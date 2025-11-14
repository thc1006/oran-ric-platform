#!/usr/bin/env python3
"""
KPIMON xApp - KPI Monitoring Application
O-RAN Release J compliant implementation
Version: 1.0.0
"""

import json
import time
import logging
import threading
from typing import Dict, List, Any
from datetime import datetime
import redis
import influxdb_client
from influxdb_client.client.write_api import SYNCHRONOUS
from ricxappframe.xapp_frame import RMRXapp, rmr
from ricxappframe.xapp_sdl import SDLWrapper
from mdclogpy import Logger
from prometheus_client import Counter, Gauge, Histogram, start_http_server
import numpy as np

# Configure logging
logger = Logger(name="KPIMON")
logger.set_level(logging.INFO)

# Prometheus metrics
MESSAGES_RECEIVED = Counter('kpimon_messages_received_total', 'Total number of messages received')
MESSAGES_PROCESSED = Counter('kpimon_messages_processed_total', 'Total number of messages processed')
KPI_VALUES = Gauge('kpimon_kpi_value', 'Current KPI values', ['kpi_type', 'cell_id'])
PROCESSING_TIME = Histogram('kpimon_processing_time_seconds', 'Time spent processing messages')

# E2SM-KPM v3.0 Message Types (O-RAN Release J)
RIC_INDICATION = 12050
RIC_SUB_REQ = 12010
RIC_SUB_RESP = 12011
RIC_SUB_DEL_REQ = 12012
RIC_SUB_DEL_RESP = 12013

class KPIMonitor:
    """
    KPI Monitor xApp implementation
    Collects and analyzes KPIs from E2 nodes via E2SM-KPM v3.0
    """
    
    def __init__(self, config_path: str = "/app/config/config.json"):
        """Initialize KPIMON xApp"""
        self.config = self._load_config(config_path)
        self.xapp = None
        self.sdl = SDLWrapper(use_fake_sdl=False)
        self.running = False
        self.subscriptions = {}
        self.kpi_buffer = []
        
        # Initialize data stores
        self._init_redis()
        self._init_influxdb()
        
        # KPI definitions for O-RAN Release J
        self.kpi_definitions = {
            "DRB.UEThpDl": {"id": 1, "type": "throughput", "unit": "Mbps"},
            "DRB.UEThpUl": {"id": 2, "type": "throughput", "unit": "Mbps"},
            "DRB.RlcSduDelayDl": {"id": 3, "type": "latency", "unit": "ms"},
            "DRB.PacketLossDl": {"id": 4, "type": "loss", "unit": "percentage"},
            "RRU.PrbUsedDl": {"id": 5, "type": "resource", "unit": "percentage"},
            "RRU.PrbUsedUl": {"id": 6, "type": "resource", "unit": "percentage"},
            "DRB.MeanActiveUeDl": {"id": 7, "type": "load", "unit": "count"},
            "DRB.MeanActiveUeUl": {"id": 8, "type": "load", "unit": "count"},
            "RRC.ConnMax": {"id": 9, "type": "connection", "unit": "count"},
            "RRC.ConnMean": {"id": 10, "type": "connection", "unit": "count"},
            "RRC.ConnEstabSucc": {"id": 11, "type": "success_rate", "unit": "percentage"},
            "HO.AttOutInterEnbN1": {"id": 12, "type": "handover", "unit": "count"},
            "HO.SuccOutInterEnbN1": {"id": 13, "type": "handover", "unit": "count"},
            "PDCP.BytesTransmittedDl": {"id": 14, "type": "volume", "unit": "bytes"},
            "PDCP.BytesTransmittedUl": {"id": 15, "type": "volume", "unit": "bytes"},
            "UE.RSRP": {"id": 16, "type": "signal", "unit": "dBm"},
            "UE.RSRQ": {"id": 17, "type": "signal", "unit": "dB"},
            "UE.SINR": {"id": 18, "type": "signal", "unit": "dB"},
            "QoS.DlPktDelayPerQCI": {"id": 19, "type": "qos", "unit": "ms"},
            "QoS.UlPktDelayPerQCI": {"id": 20, "type": "qos", "unit": "ms"}
        }
        
        logger.info(f"KPIMON xApp initialized with config: {self.config}")
    
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from JSON file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            # Return default config
            return {
                "xapp_name": "kpimon",
                "version": "1.0.0",
                "rmr_port": 4560,
                "http_port": 8080,
                "redis": {
                    "host": "redis-service.ricplt",
                    "port": 6379,
                    "db": 0
                },
                "influxdb": {
                    "url": "http://influxdb-service.ricplt:8086",
                    "token": "my-token",
                    "org": "oran",
                    "bucket": "kpimon"
                },
                "subscription": {
                    "report_period": 1000,  # ms
                    "granularity_period": 1000,  # ms
                    "max_measurements": 20
                }
            }
    
    def _init_redis(self):
        """Initialize Redis connection"""
        try:
            self.redis_client = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                db=self.config['redis']['db'],
                decode_responses=True
            )
            self.redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            self.redis_client = None
    
    def _init_influxdb(self):
        """Initialize InfluxDB connection"""
        try:
            self.influx_client = influxdb_client.InfluxDBClient(
                url=self.config['influxdb']['url'],
                token=self.config['influxdb']['token'],
                org=self.config['influxdb']['org']
            )
            self.write_api = self.influx_client.write_api(write_options=SYNCHRONOUS)
            logger.info("InfluxDB connection established")
        except Exception as e:
            logger.error(f"Failed to connect to InfluxDB: {e}")
            self.influx_client = None
    
    def start(self):
        """Start the xApp"""
        logger.info("Starting KPIMON xApp...")
        
        # Start Prometheus metrics server
        start_http_server(8080)
        
        # Initialize RMR xApp
        # Fixed: Changed from RmrXapp to RMRXapp (correct class name per official docs)
        # Added use_fake_sdl parameter as required by ricxappframe 3.2.2
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=self.config.get('rmr_port', 4560),
                            use_fake_sdl=False)
        self.running = True
        
        # Start subscription thread
        sub_thread = threading.Thread(target=self._subscription_manager)
        sub_thread.daemon = True
        sub_thread.start()
        
        # Start KPI processor thread
        processor_thread = threading.Thread(target=self._kpi_processor)
        processor_thread.daemon = True
        processor_thread.start()
        
        # Run the xApp
        logger.info("KPIMON xApp started successfully")
        self.xapp.run(thread=True)
        
        # Keep main thread alive
        while self.running:
            time.sleep(1)
    
    def _handle_message(self, rmr_xapp, summary, sbuf):
        """Handle incoming RMR messages

        Fixed: Updated function signature to match ricxappframe 3.2.2 API
        - Changed xapp -> rmr_xapp (per official docs)
        - Changed payload -> sbuf (message buffer)
        - Added rmr_free() to properly release buffer
        """
        MESSAGES_RECEIVED.inc()

        msg_type = summary[rmr.RMR_MS_MSG_TYPE]
        logger.debug(f"Received message type: {msg_type}")

        # Extract payload from buffer (returns bytes, need to decode)
        payload_bytes = rmr.get_payload(sbuf)
        payload = payload_bytes.decode('utf-8') if payload_bytes else ""

        with PROCESSING_TIME.time():
            if msg_type == RIC_INDICATION:
                self._handle_indication(payload)
            elif msg_type == RIC_SUB_RESP:
                self._handle_subscription_response(payload)
            elif msg_type == RIC_SUB_DEL_RESP:
                self._handle_subscription_delete_response(payload)
            else:
                logger.warning(f"Unknown message type: {msg_type}")

        MESSAGES_PROCESSED.inc()

        # Free the message buffer (required by ricxappframe API)
        rmr_xapp.rmr_free(sbuf)
    
    def _handle_indication(self, payload):
        """Handle RIC Indication messages containing KPIs"""
        try:
            # Parse E2SM-KPM v3.0 indication
            indication = json.loads(payload)
            
            # Extract KPI data
            cell_id = indication.get('cell_id')
            ue_id = indication.get('ue_id')
            timestamp = indication.get('timestamp', datetime.now().isoformat())
            measurements = indication.get('measurements', [])
            
            logger.debug(f"Received {len(measurements)} measurements from cell {cell_id}")
            
            # Process each measurement
            for measurement in measurements:
                kpi_name = measurement.get('name')
                kpi_value = measurement.get('value')
                
                if kpi_name in self.kpi_definitions:
                    kpi_data = {
                        'timestamp': timestamp,
                        'cell_id': cell_id,
                        'ue_id': ue_id,
                        'kpi_name': kpi_name,
                        'kpi_value': kpi_value,
                        'kpi_type': self.kpi_definitions[kpi_name]['type'],
                        'unit': self.kpi_definitions[kpi_name]['unit']
                    }
                    
                    # Add to buffer for batch processing
                    self.kpi_buffer.append(kpi_data)
                    
                    # Update Prometheus metrics
                    KPI_VALUES.labels(kpi_type=kpi_name, cell_id=cell_id).set(kpi_value)
                    
                    # Store in Redis for real-time access
                    if self.redis_client:
                        key = f"kpi:{cell_id}:{kpi_name}"
                        self.redis_client.setex(key, 300, json.dumps(kpi_data))
                        self.redis_client.zadd(f"kpi:timeline:{cell_id}", {timestamp: kpi_value})
            
            # Trigger anomaly detection
            self._detect_anomalies(cell_id, measurements)
            
        except Exception as e:
            logger.error(f"Error handling indication: {e}")
    
    def _handle_subscription_response(self, payload):
        """Handle subscription response"""
        try:
            resp = json.loads(payload)
            req_id = resp.get('request_id')
            status = resp.get('status')
            
            if status == 'success':
                self.subscriptions[req_id] = {
                    'status': 'active',
                    'timestamp': datetime.now().isoformat()
                }
                logger.info(f"Subscription {req_id} activated successfully")
            else:
                logger.error(f"Subscription {req_id} failed: {resp.get('reason')}")
        except Exception as e:
            logger.error(f"Error handling subscription response: {e}")
    
    def _handle_subscription_delete_response(self, payload):
        """Handle subscription delete response"""
        try:
            resp = json.loads(payload)
            req_id = resp.get('request_id')
            
            if req_id in self.subscriptions:
                del self.subscriptions[req_id]
                logger.info(f"Subscription {req_id} deleted successfully")
        except Exception as e:
            logger.error(f"Error handling subscription delete response: {e}")
    
    def _subscription_manager(self):
        """Manage E2 subscriptions"""
        while self.running:
            try:
                # Create subscription request for E2SM-KPM v3.0
                sub_request = {
                    "request_id": f"kpimon_{int(time.time())}",
                    "ran_function_id": 2,  # E2SM-KPM
                    "event_trigger": {
                        "report_period": self.config['subscription']['report_period']
                    },
                    "actions": [
                        {
                            "action_id": 1,
                            "action_type": "report",
                            "measurements": list(self.kpi_definitions.keys()),
                            "granularity_period": self.config['subscription']['granularity_period']
                        }
                    ]
                }
                
                # Send subscription request
                self._send_message(RIC_SUB_REQ, json.dumps(sub_request))
                logger.info(f"Sent subscription request: {sub_request['request_id']}")
                
                # Wait before next subscription check
                time.sleep(60)
                
            except Exception as e:
                logger.error(f"Error in subscription manager: {e}")
                time.sleep(10)
    
    def _kpi_processor(self):
        """Process KPI buffer and store in InfluxDB"""
        while self.running:
            try:
                if len(self.kpi_buffer) >= 100:  # Batch size
                    batch = self.kpi_buffer[:100]
                    self.kpi_buffer = self.kpi_buffer[100:]
                    
                    # Write to InfluxDB
                    if self.influx_client:
                        points = []
                        for kpi in batch:
                            point = influxdb_client.Point("kpi_measurement") \
                                .tag("cell_id", kpi['cell_id']) \
                                .tag("kpi_name", kpi['kpi_name']) \
                                .tag("kpi_type", kpi['kpi_type']) \
                                .field("value", float(kpi['kpi_value'])) \
                                .time(kpi['timestamp'])
                            points.append(point)
                        
                        self.write_api.write(
                            bucket=self.config['influxdb']['bucket'],
                            org=self.config['influxdb']['org'],
                            record=points
                        )
                        logger.debug(f"Wrote {len(points)} KPI points to InfluxDB")
                
                time.sleep(1)
                
            except Exception as e:
                logger.error(f"Error in KPI processor: {e}")
                time.sleep(5)
    
    def _detect_anomalies(self, cell_id: str, measurements: List[Dict]):
        """Detect anomalies in KPI data"""
        try:
            # Simple threshold-based anomaly detection
            anomalies = []
            
            for measurement in measurements:
                kpi_name = measurement.get('name')
                kpi_value = measurement.get('value')
                
                # Define thresholds
                thresholds = {
                    "DRB.PacketLossDl": 5.0,  # Alert if packet loss > 5%
                    "RRU.PrbUsedDl": 90.0,     # Alert if PRB usage > 90%
                    "RRU.PrbUsedUl": 90.0,     # Alert if PRB usage > 90%
                    "UE.RSRP": -110.0,         # Alert if RSRP < -110 dBm
                    "RRC.ConnEstabSucc": 95.0  # Alert if success rate < 95%
                }
                
                if kpi_name in thresholds:
                    threshold = thresholds[kpi_name]
                    
                    if kpi_name in ["UE.RSRP"]:
                        if kpi_value < threshold:
                            anomalies.append({
                                'kpi': kpi_name,
                                'value': kpi_value,
                                'threshold': threshold,
                                'type': 'below_threshold'
                            })
                    elif kpi_name in ["RRC.ConnEstabSucc"]:
                        if kpi_value < threshold:
                            anomalies.append({
                                'kpi': kpi_name,
                                'value': kpi_value,
                                'threshold': threshold,
                                'type': 'below_threshold'
                            })
                    else:
                        if kpi_value > threshold:
                            anomalies.append({
                                'kpi': kpi_name,
                                'value': kpi_value,
                                'threshold': threshold,
                                'type': 'above_threshold'
                            })
            
            if anomalies:
                self._raise_alarm(cell_id, anomalies)
        
        except Exception as e:
            logger.error(f"Error detecting anomalies: {e}")
    
    def _raise_alarm(self, cell_id: str, anomalies: List[Dict]):
        """Raise alarm for detected anomalies"""
        alarm = {
            'timestamp': datetime.now().isoformat(),
            'cell_id': cell_id,
            'anomalies': anomalies,
            'severity': 'warning'
        }
        
        # Store alarm in Redis
        if self.redis_client:
            self.redis_client.rpush(f"alarms:{cell_id}", json.dumps(alarm))
            self.redis_client.expire(f"alarms:{cell_id}", 86400)  # 24 hours
        
        logger.warning(f"Anomaly detected in cell {cell_id}: {anomalies}")
    
    def _send_message(self, msg_type: int, payload: str):
        """Send RMR message"""
        if self.xapp:
            success = self.xapp.rmr_send(payload.encode(), msg_type)
            if not success:
                logger.error(f"Failed to send message type {msg_type}")
    
    def stop(self):
        """Stop the xApp"""
        logger.info("Stopping KPIMON xApp...")
        self.running = False
        if self.xapp:
            self.xapp.stop()
        if self.influx_client:
            self.influx_client.close()
        logger.info("KPIMON xApp stopped")


if __name__ == "__main__":
    # Create and start KPIMON xApp
    kpimon = KPIMonitor()
    
    try:
        kpimon.start()
    except KeyboardInterrupt:
        kpimon.stop()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        kpimon.stop()
