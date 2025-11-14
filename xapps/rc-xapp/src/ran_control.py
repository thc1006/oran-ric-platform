#!/usr/bin/env python3
"""
RAN Control xApp - RAN Control and Optimization Application
O-RAN Release J compliant implementation
Version: 1.0.0
"""

import json
import time
import logging
import threading
import asyncio
from typing import Dict, List, Any, Optional
from datetime import datetime
from dataclasses import dataclass
from enum import Enum
import numpy as np
from ricxappframe.xapp_frame import RMRXapp, rmr
from mdclogpy import Logger
from flask import Flask, request, jsonify
import redis

# Configure logging
logger = Logger(name="RAN_CONTROL")
logger.set_level(logging.INFO)

# Flask app for REST API
app = Flask(__name__)

# E2SM-RC v2.0 Message Types (O-RAN Release J)
RIC_CONTROL_REQ = 12040
RIC_CONTROL_ACK = 12041
RIC_CONTROL_FAILURE = 12042
RIC_INDICATION = 12050
RIC_SUB_REQ = 12010
RIC_SUB_RESP = 12011
A1_POLICY_REQ = 20010
A1_POLICY_RESP = 20011

class ControlActionType(Enum):
    """E2SM-RC Control Action Types"""
    HANDOVER = 1
    RESOURCE_ALLOCATION = 2
    BEARER_CONTROL = 3
    LOAD_BALANCING = 4
    SLICE_CONTROL = 5
    POWER_CONTROL = 6
    MOBILITY_CONTROL = 7
    QOS_CONTROL = 8
    PDCP_DUPLICATION = 9
    DRX_CONTROL = 10

@dataclass
class ControlAction:
    """Control action data structure"""
    action_id: int
    action_type: ControlActionType
    ue_id: Optional[str]
    cell_id: str
    parameters: Dict[str, Any]
    timestamp: str
    priority: str = "normal"
    timeout: int = 5000  # ms

class RANController:
    """
    RAN Control xApp implementation
    Performs RAN control actions via E2SM-RC v2.0
    """
    
    def __init__(self, config_path: str = "/app/config/config.json"):
        """Initialize RAN Control xApp"""
        self.config = self._load_config(config_path)
        self.xapp = None
        self.running = False
        self.control_queue = []
        self.active_controls = {}
        self.control_policies = {}
        self.network_state = {}
        
        # Initialize Redis connection
        self._init_redis()
        
        # Control optimization algorithms
        self.optimizers = {
            'handover': self._optimize_handover,
            'resource': self._optimize_resources,
            'load_balancing': self._optimize_load_balancing,
            'slice': self._optimize_slice_allocation,
            'power': self._optimize_power_control
        }
        
        # Performance metrics
        self.metrics = {
            'control_actions_sent': 0,
            'control_actions_success': 0,
            'control_actions_failed': 0,
            'handovers_triggered': 0,
            'resource_optimizations': 0,
            'slice_reconfigurations': 0
        }
        
        logger.info(f"RAN Control xApp initialized with config: {self.config}")
    
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from JSON file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict:
        """Return default configuration"""
        return {
            "xapp_name": "ran-control",
            "version": "1.0.0",
            "rmr_port": 4580,
            "http_port": 8100,
            "redis": {
                "host": "redis-service.ricplt",
                "port": 6379,
                "db": 2
            },
            "control": {
                "max_queue_size": 1000,
                "processing_interval": 100,  # ms
                "timeout_default": 5000,  # ms
                "retry_attempts": 3
            },
            "optimization": {
                "handover": {
                    "rsrp_threshold": -100,
                    "rsrq_threshold": -15,
                    "hysteresis": 3,
                    "time_to_trigger": 640  # ms
                },
                "resource": {
                    "prb_threshold_high": 80,
                    "prb_threshold_low": 20,
                    "reallocation_period": 1000  # ms
                },
                "load_balancing": {
                    "load_threshold": 0.7,
                    "min_ue_count": 5,
                    "balancing_period": 5000  # ms
                },
                "slice": {
                    "sla_violation_threshold": 0.95,
                    "resource_efficiency_target": 0.8
                },
                "power": {
                    "target_sinr": 15,  # dB
                    "max_tx_power": 43,  # dBm
                    "min_tx_power": -20,  # dBm
                    "step_size": 1  # dB
                }
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
    
    def start(self):
        """Start the xApp"""
        logger.info("Starting RAN Control xApp...")
        
        # Initialize RMR xApp
        # Fixed: Changed from RmrXapp to RMRXapp (correct class name per official docs)
        # Added use_fake_sdl parameter as required by ricxappframe 3.2.2
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=self.config.get('rmr_port', 4580),
                            use_fake_sdl=False)
        self.running = True
        
        # Start control processor thread
        control_thread = threading.Thread(target=self._control_processor)
        control_thread.daemon = True
        control_thread.start()
        
        # Start optimization thread
        optimization_thread = threading.Thread(target=self._optimization_loop)
        optimization_thread.daemon = True
        optimization_thread.start()
        
        # Start policy manager thread
        policy_thread = threading.Thread(target=self._policy_manager)
        policy_thread.daemon = True
        policy_thread.start()
        
        # Start Flask API in separate thread
        api_thread = threading.Thread(target=self._start_api)
        api_thread.daemon = True
        api_thread.start()
        
        # Run the xApp
        logger.info("RAN Control xApp started successfully")
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
        msg_type = summary[rmr.RMR_MS_MSG_TYPE]

        # Extract payload from buffer (returns bytes, need to decode)
        payload_bytes = rmr.get_payload(sbuf)
        payload = payload_bytes.decode('utf-8') if payload_bytes else ""

        if msg_type == RIC_CONTROL_ACK:
            self._handle_control_ack(payload)
        elif msg_type == RIC_CONTROL_FAILURE:
            self._handle_control_failure(payload)
        elif msg_type == RIC_INDICATION:
            self._handle_indication(payload)
        elif msg_type == A1_POLICY_REQ:
            self._handle_policy_request(summary, payload)
        else:
            logger.debug(f"Received message type: {msg_type}")

        # Free the message buffer (required by ricxappframe API)
        rmr_xapp.rmr_free(sbuf)
    
    def _handle_control_ack(self, payload):
        """Handle control acknowledgment"""
        try:
            ack = json.loads(payload)
            action_id = ack.get('action_id')
            
            if action_id in self.active_controls:
                control = self.active_controls[action_id]
                control['status'] = 'completed'
                control['completion_time'] = datetime.now().isoformat()
                
                # Update metrics
                self.metrics['control_actions_success'] += 1
                
                # Log specific action metrics
                if control['action_type'] == ControlActionType.HANDOVER:
                    self.metrics['handovers_triggered'] += 1
                elif control['action_type'] == ControlActionType.RESOURCE_ALLOCATION:
                    self.metrics['resource_optimizations'] += 1
                elif control['action_type'] == ControlActionType.SLICE_CONTROL:
                    self.metrics['slice_reconfigurations'] += 1
                
                logger.info(f"Control action {action_id} completed successfully")
                
                # Store result in Redis
                if self.redis_client:
                    key = f"control:result:{action_id}"
                    self.redis_client.setex(key, 3600, json.dumps(control))
                
                # Remove from active controls
                del self.active_controls[action_id]
                
        except Exception as e:
            logger.error(f"Error handling control ACK: {e}")
    
    def _handle_control_failure(self, payload):
        """Handle control failure"""
        try:
            failure = json.loads(payload)
            action_id = failure.get('action_id')
            reason = failure.get('reason', 'Unknown')
            
            if action_id in self.active_controls:
                control = self.active_controls[action_id]
                control['status'] = 'failed'
                control['failure_reason'] = reason
                
                # Update metrics
                self.metrics['control_actions_failed'] += 1
                
                logger.error(f"Control action {action_id} failed: {reason}")
                
                # Retry if configured
                if control.get('retry_count', 0) < self.config['control']['retry_attempts']:
                    control['retry_count'] = control.get('retry_count', 0) + 1
                    self.control_queue.append(control)
                    logger.info(f"Retrying control action {action_id} (attempt {control['retry_count']})")
                else:
                    # Store failure in Redis
                    if self.redis_client:
                        key = f"control:failure:{action_id}"
                        self.redis_client.setex(key, 3600, json.dumps(control))
                    
                    del self.active_controls[action_id]
                
        except Exception as e:
            logger.error(f"Error handling control failure: {e}")
    
    def _handle_indication(self, payload):
        """Handle RIC Indication with network state"""
        try:
            indication = json.loads(payload)
            
            cell_id = indication.get('cell_id')
            timestamp = indication.get('timestamp', datetime.now().isoformat())
            measurements = indication.get('measurements', [])
            
            # Update network state
            if cell_id not in self.network_state:
                self.network_state[cell_id] = {}
            
            self.network_state[cell_id].update({
                'timestamp': timestamp,
                'measurements': measurements,
                'load': self._calculate_cell_load(measurements),
                'ue_count': self._extract_ue_count(measurements)
            })
            
            # Check for optimization triggers
            self._check_optimization_triggers(cell_id, measurements)
            
        except Exception as e:
            logger.error(f"Error handling indication: {e}")
    
    def _handle_policy_request(self, summary, payload):
        """Handle A1 policy request"""
        try:
            policy = json.loads(payload)
            policy_type = policy.get('policy_type')
            policy_id = policy.get('policy_id')
            
            # Store policy
            self.control_policies[policy_id] = policy
            
            # Apply policy to control logic
            self._apply_policy(policy)
            
            # Send response
            response = {
                'policy_id': policy_id,
                'status': 'enforced',
                'timestamp': datetime.now().isoformat()
            }
            
            self._send_message(A1_POLICY_RESP, json.dumps(response))
            logger.info(f"Policy {policy_id} enforced: {policy_type}")
            
        except Exception as e:
            logger.error(f"Error handling policy request: {e}")
    
    def _control_processor(self):
        """Process control actions from queue"""
        while self.running:
            try:
                if self.control_queue:
                    control = self.control_queue.pop(0)
                    
                    # Build E2SM-RC control request
                    control_request = self._build_control_request(control)
                    
                    # Send control request
                    self._send_message(RIC_CONTROL_REQ, json.dumps(control_request))
                    
                    # Track active control
                    self.active_controls[control.action_id] = {
                        'action_type': control.action_type,
                        'timestamp': datetime.now().isoformat(),
                        'control': control
                    }
                    
                    self.metrics['control_actions_sent'] += 1
                    logger.info(f"Sent control action: {control.action_id}")
                
                time.sleep(self.config['control']['processing_interval'] / 1000.0)
                
            except Exception as e:
                logger.error(f"Error in control processor: {e}")
                time.sleep(1)
    
    def _build_control_request(self, control: ControlAction) -> Dict:
        """Build E2SM-RC control request"""
        request = {
            'request_id': control.action_id,
            'ran_function_id': 3,  # E2SM-RC
            'control_header': {
                'control_style': self._get_control_style(control.action_type),
                'control_action_id': control.action_type.value,
                'ue_id': control.ue_id,
                'cell_id': control.cell_id
            },
            'control_message': control.parameters,
            'control_ack_request': True,
            'timeout': control.timeout
        }
        
        return request
    
    def _get_control_style(self, action_type: ControlActionType) -> int:
        """Get E2SM-RC control style for action type"""
        style_map = {
            ControlActionType.HANDOVER: 1,
            ControlActionType.RESOURCE_ALLOCATION: 2,
            ControlActionType.BEARER_CONTROL: 3,
            ControlActionType.LOAD_BALANCING: 2,
            ControlActionType.SLICE_CONTROL: 4,
            ControlActionType.POWER_CONTROL: 5,
            ControlActionType.MOBILITY_CONTROL: 1,
            ControlActionType.QOS_CONTROL: 3,
            ControlActionType.PDCP_DUPLICATION: 3,
            ControlActionType.DRX_CONTROL: 6
        }
        return style_map.get(action_type, 1)
    
    def _optimization_loop(self):
        """Main optimization loop"""
        while self.running:
            try:
                # Run each optimizer
                for optimizer_name, optimizer_func in self.optimizers.items():
                    try:
                        actions = optimizer_func()
                        for action in actions:
                            self.control_queue.append(action)
                    except Exception as e:
                        logger.error(f"Error in {optimizer_name} optimizer: {e}")
                
                time.sleep(5)  # Optimization interval
                
            except Exception as e:
                logger.error(f"Error in optimization loop: {e}")
                time.sleep(10)
    
    def _optimize_handover(self) -> List[ControlAction]:
        """Optimize handover decisions"""
        actions = []
        
        try:
            # Get UE measurements from Redis
            if self.redis_client:
                ue_measurements = self._get_ue_measurements()
                
                for ue_id, measurements in ue_measurements.items():
                    # Check handover criteria
                    serving_rsrp = measurements.get('serving_rsrp', -999)
                    neighbor_cells = measurements.get('neighbor_cells', [])
                    
                    best_neighbor = None
                    best_rsrp = serving_rsrp
                    
                    for neighbor in neighbor_cells:
                        neighbor_rsrp = neighbor.get('rsrp', -999)
                        hysteresis = self.config['optimization']['handover']['hysteresis']
                        
                        if neighbor_rsrp > best_rsrp + hysteresis:
                            best_rsrp = neighbor_rsrp
                            best_neighbor = neighbor
                    
                    # Trigger handover if needed
                    if best_neighbor:
                        action = ControlAction(
                            action_id=int(time.time() * 1000),
                            action_type=ControlActionType.HANDOVER,
                            ue_id=ue_id,
                            cell_id=best_neighbor['cell_id'],
                            parameters={
                                'target_cell_id': best_neighbor['cell_id'],
                                'handover_type': 'x2',
                                'cause': 'radio_network_optimization'
                            },
                            timestamp=datetime.now().isoformat(),
                            priority='high'
                        )
                        actions.append(action)
                        logger.info(f"Handover triggered for UE {ue_id} to cell {best_neighbor['cell_id']}")
        
        except Exception as e:
            logger.error(f"Error in handover optimization: {e}")
        
        return actions
    
    def _optimize_resources(self) -> List[ControlAction]:
        """Optimize resource allocation"""
        actions = []
        
        try:
            for cell_id, state in self.network_state.items():
                load = state.get('load', 0)
                
                # Check if resource optimization needed
                if load > self.config['optimization']['resource']['prb_threshold_high']:
                    # High load - optimize resources
                    action = ControlAction(
                        action_id=int(time.time() * 1000),
                        action_type=ControlActionType.RESOURCE_ALLOCATION,
                        ue_id=None,
                        cell_id=cell_id,
                        parameters={
                            'resource_type': 'prb',
                            'action': 'optimize',
                            'target_utilization': 70,
                            'scheduling_algorithm': 'proportional_fair'
                        },
                        timestamp=datetime.now().isoformat(),
                        priority='normal'
                    )
                    actions.append(action)
                    logger.info(f"Resource optimization triggered for cell {cell_id}")
        
        except Exception as e:
            logger.error(f"Error in resource optimization: {e}")
        
        return actions
    
    def _optimize_load_balancing(self) -> List[ControlAction]:
        """Optimize load balancing between cells"""
        actions = []
        
        try:
            # Calculate load imbalance
            cell_loads = {cell_id: state.get('load', 0) 
                         for cell_id, state in self.network_state.items()}
            
            if cell_loads:
                avg_load = np.mean(list(cell_loads.values()))
                threshold = self.config['optimization']['load_balancing']['load_threshold']
                
                # Find overloaded and underloaded cells
                overloaded = [c for c, l in cell_loads.items() if l > avg_load * (1 + threshold)]
                underloaded = [c for c, l in cell_loads.items() if l < avg_load * (1 - threshold)]
                
                if overloaded and underloaded:
                    # Trigger load balancing
                    for overloaded_cell in overloaded:
                        target_cell = underloaded[0]  # Simple selection
                        
                        action = ControlAction(
                            action_id=int(time.time() * 1000),
                            action_type=ControlActionType.LOAD_BALANCING,
                            ue_id=None,
                            cell_id=overloaded_cell,
                            parameters={
                                'source_cell': overloaded_cell,
                                'target_cell': target_cell,
                                'load_transfer_ratio': 0.2,
                                'handover_offset': 3  # dB
                            },
                            timestamp=datetime.now().isoformat(),
                            priority='normal'
                        )
                        actions.append(action)
                        logger.info(f"Load balancing from {overloaded_cell} to {target_cell}")
        
        except Exception as e:
            logger.error(f"Error in load balancing optimization: {e}")
        
        return actions
    
    def _optimize_slice_allocation(self) -> List[ControlAction]:
        """Optimize network slice allocation"""
        actions = []
        
        try:
            # Get slice SLA status from Redis
            if self.redis_client:
                slice_status = self._get_slice_status()
                
                for slice_id, status in slice_status.items():
                    sla_compliance = status.get('sla_compliance', 1.0)
                    threshold = self.config['optimization']['slice']['sla_violation_threshold']
                    
                    if sla_compliance < threshold:
                        # SLA violation - reallocate resources
                        action = ControlAction(
                            action_id=int(time.time() * 1000),
                            action_type=ControlActionType.SLICE_CONTROL,
                            ue_id=None,
                            cell_id='all',
                            parameters={
                                'slice_id': slice_id,
                                'action': 'resource_reallocation',
                                'resource_share_increase': 20,  # percentage
                                'priority_boost': 2
                            },
                            timestamp=datetime.now().isoformat(),
                            priority='high'
                        )
                        actions.append(action)
                        logger.warning(f"Slice {slice_id} SLA violation - reallocating resources")
        
        except Exception as e:
            logger.error(f"Error in slice optimization: {e}")
        
        return actions
    
    def _optimize_power_control(self) -> List[ControlAction]:
        """Optimize transmission power control"""
        actions = []
        
        try:
            # Get UE SINR measurements
            if self.redis_client:
                ue_sinr = self._get_ue_sinr()
                
                for ue_id, sinr in ue_sinr.items():
                    target_sinr = self.config['optimization']['power']['target_sinr']
                    step_size = self.config['optimization']['power']['step_size']
                    
                    if abs(sinr - target_sinr) > 3:  # 3 dB threshold
                        # Adjust power
                        power_adjustment = step_size if sinr < target_sinr else -step_size
                        
                        action = ControlAction(
                            action_id=int(time.time() * 1000),
                            action_type=ControlActionType.POWER_CONTROL,
                            ue_id=ue_id,
                            cell_id='serving',
                            parameters={
                                'power_adjustment': power_adjustment,
                                'target_sinr': target_sinr,
                                'control_type': 'closed_loop'
                            },
                            timestamp=datetime.now().isoformat(),
                            priority='low'
                        )
                        actions.append(action)
                        logger.debug(f"Power control for UE {ue_id}: {power_adjustment} dB")
        
        except Exception as e:
            logger.error(f"Error in power control optimization: {e}")
        
        return actions
    
    def _calculate_cell_load(self, measurements: List[Dict]) -> float:
        """Calculate cell load from measurements"""
        for measurement in measurements:
            if 'prb_usage' in measurement.get('name', '').lower():
                return measurement.get('value', 0)
        return 0
    
    def _extract_ue_count(self, measurements: List[Dict]) -> int:
        """Extract UE count from measurements"""
        for measurement in measurements:
            if 'active_ue' in measurement.get('name', '').lower():
                return int(measurement.get('value', 0))
        return 0
    
    def _check_optimization_triggers(self, cell_id: str, measurements: List[Dict]):
        """Check if optimization should be triggered"""
        # This method would implement various trigger conditions
        pass
    
    def _apply_policy(self, policy: Dict):
        """Apply A1 policy to control behavior"""
        policy_type = policy.get('policy_type')
        
        if policy_type == 'handover_policy':
            # Update handover parameters
            params = policy.get('parameters', {})
            if 'rsrp_threshold' in params:
                self.config['optimization']['handover']['rsrp_threshold'] = params['rsrp_threshold']
            if 'hysteresis' in params:
                self.config['optimization']['handover']['hysteresis'] = params['hysteresis']
                
        elif policy_type == 'resource_policy':
            # Update resource allocation parameters
            params = policy.get('parameters', {})
            if 'prb_threshold_high' in params:
                self.config['optimization']['resource']['prb_threshold_high'] = params['prb_threshold_high']
                
        elif policy_type == 'slice_policy':
            # Update slice management parameters
            params = policy.get('parameters', {})
            if 'sla_violation_threshold' in params:
                self.config['optimization']['slice']['sla_violation_threshold'] = params['sla_violation_threshold']
    
    def _get_ue_measurements(self) -> Dict:
        """Get UE measurements from Redis"""
        measurements = {}
        if self.redis_client:
            # Implementation would fetch actual UE measurements
            pass
        return measurements
    
    def _get_slice_status(self) -> Dict:
        """Get slice status from Redis"""
        status = {}
        if self.redis_client:
            # Implementation would fetch actual slice status
            pass
        return status
    
    def _get_ue_sinr(self) -> Dict:
        """Get UE SINR values from Redis"""
        sinr_values = {}
        if self.redis_client:
            # Implementation would fetch actual SINR values
            pass
        return sinr_values
    
    def _policy_manager(self):
        """Manage and evaluate policies periodically"""
        while self.running:
            try:
                # Evaluate active policies
                for policy_id, policy in self.control_policies.items():
                    # Check if policy conditions are met
                    # and trigger appropriate actions
                    pass
                
                time.sleep(10)  # Policy evaluation interval
                
            except Exception as e:
                logger.error(f"Error in policy manager: {e}")
                time.sleep(10)
    
    def _send_message(self, msg_type: int, payload: str):
        """Send RMR message"""
        if self.xapp:
            success = self.xapp.rmr_send(payload.encode(), msg_type)
            if not success:
                logger.error(f"Failed to send message type {msg_type}")
    
    def _start_api(self):
        """Start Flask REST API"""
        
        @app.route('/health/alive', methods=['GET'])
        def health_alive():
            return jsonify({'status': 'alive'}), 200
        
        @app.route('/health/ready', methods=['GET'])
        def health_ready():
            return jsonify({'status': 'ready'}), 200
        
        @app.route('/control/trigger', methods=['POST'])
        def trigger_control():
            """Manually trigger a control action"""
            try:
                data = request.json
                action = ControlAction(
                    action_id=int(time.time() * 1000),
                    action_type=ControlActionType[data['action_type']],
                    ue_id=data.get('ue_id'),
                    cell_id=data['cell_id'],
                    parameters=data.get('parameters', {}),
                    timestamp=datetime.now().isoformat(),
                    priority=data.get('priority', 'normal')
                )
                self.control_queue.append(action)
                return jsonify({'status': 'queued', 'action_id': action.action_id}), 200
            except Exception as e:
                return jsonify({'error': str(e)}), 400
        
        @app.route('/control/status/<action_id>', methods=['GET'])
        def get_control_status(action_id):
            """Get status of a control action"""
            action_id = int(action_id)
            if action_id in self.active_controls:
                return jsonify(self.active_controls[action_id]), 200
            return jsonify({'error': 'Action not found'}), 404
        
        @app.route('/metrics', methods=['GET'])
        def get_metrics():
            """Get control metrics"""
            return jsonify(self.metrics), 200
        
        @app.route('/network/state', methods=['GET'])
        def get_network_state():
            """Get current network state"""
            return jsonify(self.network_state), 200
        
        app.run(host='0.0.0.0', port=self.config['http_port'])
    
    def stop(self):
        """Stop the xApp"""
        logger.info("Stopping RAN Control xApp...")
        self.running = False
        if self.xapp:
            self.xapp.stop()
        logger.info("RAN Control xApp stopped")


if __name__ == "__main__":
    # Create and start RAN Control xApp
    ran_control = RANController()
    
    try:
        ran_control.start()
    except KeyboardInterrupt:
        ran_control.stop()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        ran_control.stop()
