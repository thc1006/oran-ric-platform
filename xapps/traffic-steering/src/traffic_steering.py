#!/usr/bin/env python3
"""
Traffic Steering xApp
Implements policy-based handover decisions for O-RAN
"""

import json
import time
import logging
from typing import Dict, List, Optional
from dataclasses import dataclass
from threading import Thread
from flask import Flask, jsonify

from ricxappframe.xapp_frame import RMRXapp, rmr
from ricxappframe.xapp_sdl import SDLWrapper
from mdclogpy import Logger

# Configure logging
logger = Logger(name="traffic_steering_xapp")
logger.set_level(logging.INFO)

# RMR Message Types
RIC_SUB_REQ = 12010
RIC_SUB_RESP = 12011
RIC_SUB_DEL_REQ = 12012
RIC_INDICATION = 12050
RIC_CONTROL_REQ = 12040
RIC_CONTROL_RESP = 12041
A1_POLICY_REQ = 20010
A1_POLICY_RESP = 20011

# E2SM Service Model IDs
E2SM_KPM_ID = 0
E2SM_RC_ID = 1

@dataclass
class UEMetrics:
    """UE performance metrics from E2SM-KPM"""
    ue_id: str
    serving_cell: str
    rsrp: float  # Reference Signal Received Power
    rsrq: float  # Reference Signal Received Quality
    dl_throughput: float  # Downlink throughput (Mbps)
    ul_throughput: float  # Uplink throughput (Mbps)
    timestamp: float

@dataclass
class HandoverPolicy:
    """A1 policy for handover thresholds"""
    policy_id: str
    rsrp_threshold: float = -100.0  # dBm
    throughput_threshold: float = 10.0  # Mbps
    load_threshold: float = 0.8  # 80% cell load
    enabled: bool = True

class TrafficSteeringXapp:
    """
    Traffic Steering xApp implementation
    """

    def __init__(self, config_path: str = "/app/config/config.json"):
        """Initialize xApp"""
        self.config = self._load_config(config_path)
        self.xapp = None
        self.running = False

        # Initialize SDL
        self.sdl = SDLWrapper(use_fake_sdl=False)
        self.namespace = "ts_xapp"

        # State management
        self.ue_metrics: Dict[str, UEMetrics] = {}
        self.policies: Dict[str, HandoverPolicy] = {}
        self.subscriptions: Dict[int, Dict] = {}

        # Load default policy from config
        handover_config = self.config.get('handover', {})
        self.default_policy = HandoverPolicy(
            policy_id="default",
            rsrp_threshold=handover_config.get('rsrp_threshold', -100.0),
            throughput_threshold=handover_config.get('throughput_threshold', 10.0),
            load_threshold=handover_config.get('load_threshold', 0.8)
        )

        # Initialize Flask app for health checks
        self.app = Flask(__name__)
        self._setup_routes()

        logger.info("Traffic Steering xApp initialized")

    def _load_config(self, config_path: str) -> dict:
        """Load configuration from file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            logger.warning(f"Config file {config_path} not found, using defaults")
            return {
                'xapp_name': 'traffic-steering',
                'version': '1.0.0',
                'handover': {
                    'rsrp_threshold': -100.0,
                    'rsrq_threshold': -15.0,
                    'throughput_threshold': 10.0,
                    'load_threshold': 0.8
                }
            }

    def _setup_routes(self):
        """Setup Flask routes for health checks"""
        @self.app.route('/ric/v1/health/alive', methods=['GET'])
        def health_alive():
            return jsonify({"status": "alive"}), 200

        @self.app.route('/ric/v1/health/ready', methods=['GET'])
        def health_ready():
            return jsonify({"status": "ready"}), 200

    def _handle_message(self, summary: dict, sbuf):
        """Handle incoming RMR messages"""

        mtype = summary['message type']
        logger.debug(f"Received message type: {mtype}")

        try:
            if mtype == RIC_INDICATION:
                self._handle_indication(summary, sbuf)
            elif mtype == RIC_SUB_RESP:
                self._handle_subscription_response(summary, sbuf)
            elif mtype == A1_POLICY_REQ:
                self._handle_policy_request(summary, sbuf)
            else:
                logger.warning(f"Unhandled message type: {mtype}")

        except Exception as e:
            logger.error(f"Error handling message: {e}")

    def _handle_indication(self, summary: dict, sbuf):
        """Process E2 Indication messages"""

        # Parse E2SM-KPM indication
        try:
            payload = json.loads(summary['payload'])
        except:
            logger.error("Failed to parse indication payload")
            return

        # Extract UE metrics
        for ue_data in payload.get('ue_list', []):
            ue_metrics = UEMetrics(
                ue_id=ue_data['ue_id'],
                serving_cell=ue_data['serving_cell'],
                rsrp=ue_data['rsrp'],
                rsrq=ue_data['rsrq'],
                dl_throughput=ue_data['dl_throughput'],
                ul_throughput=ue_data['ul_throughput'],
                timestamp=time.time()
            )

            # Store metrics
            self.ue_metrics[ue_metrics.ue_id] = ue_metrics

            # Store in SDL for persistence
            self.sdl.set(
                self.namespace,
                {f"ue_metrics:{ue_metrics.ue_id}": json.dumps(ue_data)}
            )

            # Evaluate handover decision
            self._evaluate_handover(ue_metrics)

    def _evaluate_handover(self, metrics: UEMetrics):
        """Evaluate if handover is needed based on policy"""

        # Get active policy
        policy = self.policies.get('active', self.default_policy)

        if not policy.enabled:
            return

        # Check handover criteria
        needs_handover = False
        reason = ""

        if metrics.rsrp < policy.rsrp_threshold:
            needs_handover = True
            reason = f"Low RSRP: {metrics.rsrp} dBm"

        if metrics.dl_throughput < policy.throughput_threshold:
            needs_handover = True
            reason = f"Low throughput: {metrics.dl_throughput} Mbps"

        if needs_handover:
            logger.info(f"Triggering handover for UE {metrics.ue_id}: {reason}")

            # Get target cell from QoE Predictor
            target_cell = self._get_target_cell(metrics)

            if target_cell:
                # Send control request to RC xApp
                self._send_handover_command(metrics.ue_id, target_cell)

    def _get_target_cell(self, metrics: UEMetrics) -> Optional[str]:
        """Query QoE Predictor for best target cell"""

        # Send RMR message to QoE Predictor xApp
        request = {
            "ue_id": metrics.ue_id,
            "serving_cell": metrics.serving_cell,
            "timestamp": metrics.timestamp
        }

        # Message type for QoE prediction request
        QOE_PRED_REQ = 30000

        self._send_message(QOE_PRED_REQ, json.dumps(request))

        # For now, return a mock target cell
        # In production, this would parse the QoE Predictor response
        return "cell_02"

    def _send_handover_command(self, ue_id: str, target_cell: str):
        """Send handover command via RC xApp"""

        # Construct E2SM-RC control message
        control_msg = {
            "ue_id": ue_id,
            "target_cell": target_cell,
            "control_style": 3,  # UE-specific handover
            "action": "handover"
        }

        # Send to RC xApp
        RC_XAPP_REQ = 40000
        self._send_message(RC_XAPP_REQ, json.dumps(control_msg))
        logger.info(f"Handover command sent for UE {ue_id} to {target_cell}")

    def _handle_subscription_response(self, summary: dict, sbuf):
        """Handle E2 subscription response"""

        try:
            payload = json.loads(summary['payload'])
        except:
            logger.error("Failed to parse subscription response")
            return

        sub_id = payload.get('subscription_id')

        if payload.get('status') == 'success':
            logger.info(f"Subscription {sub_id} established successfully")
            self.subscriptions[sub_id] = payload
        else:
            logger.error(f"Subscription {sub_id} failed: {payload.get('reason')}")

    def _handle_policy_request(self, summary: dict, sbuf):
        """Handle A1 policy updates"""

        try:
            payload = json.loads(summary['payload'])
        except:
            logger.error("Failed to parse policy request")
            return

        policy_data = payload.get('policy', {})

        # Create new policy
        policy = HandoverPolicy(
            policy_id=payload.get('policy_id'),
            rsrp_threshold=policy_data.get('rsrp_threshold', -100.0),
            throughput_threshold=policy_data.get('throughput_threshold', 10.0),
            load_threshold=policy_data.get('load_threshold', 0.8),
            enabled=policy_data.get('enabled', True)
        )

        # Store policy
        self.policies[policy.policy_id] = policy
        self.sdl.set(
            self.namespace,
            {f"policy:{policy.policy_id}": json.dumps(policy_data)}
        )

        logger.info(f"Policy {policy.policy_id} updated")

        # Send acknowledgment
        self._send_policy_response(payload.get('policy_id'), 'success')

    def _send_policy_response(self, policy_id: str, status: str):
        """Send A1 policy response"""

        response = {
            "policy_id": policy_id,
            "status": status,
            "timestamp": time.time()
        }

        self._send_message(A1_POLICY_RESP, json.dumps(response))

    def _send_message(self, msg_type: int, payload: str):
        """Send RMR message"""
        if self.xapp:
            success = self.xapp.rmr_send(payload.encode(), msg_type)
            if not success:
                logger.error(f"Failed to send message type {msg_type}")

    def create_subscriptions(self):
        """Create E2 subscriptions for KPM metrics"""

        # E2SM-KPM subscription for UE metrics
        kpm_subscription = {
            "subscription_id": 1001,
            "ran_function_id": E2SM_KPM_ID,
            "action_type": "report",
            "report_style": 4,  # UE-level measurements
            "granularity_period": 1000,  # 1 second
            "measurements": [
                "DRB.UEThpDl",
                "DRB.UEThpUl",
                "RRU.PrbTotDl",
                "RRU.PrbUsedDl"
            ]
        }

        # Send subscription request
        self._send_message(RIC_SUB_REQ, json.dumps(kpm_subscription))
        logger.info("E2 subscription request sent")

    def _health_check_loop(self):
        """Periodic health check"""

        while self.running:
            time.sleep(30)

            # Clean old metrics
            current_time = time.time()
            expired_ues = []

            for ue_id, metrics in self.ue_metrics.items():
                if current_time - metrics.timestamp > 60:  # 1 minute timeout
                    expired_ues.append(ue_id)

            for ue_id in expired_ues:
                del self.ue_metrics[ue_id]
                logger.debug(f"Removed stale metrics for UE {ue_id}")

            # Log status
            logger.info(f"Active UEs: {len(self.ue_metrics)}, Policies: {len(self.policies)}")

    def start(self):
        """Start the xApp"""

        logger.info("Starting Traffic Steering xApp")
        self.running = True

        # Start Flask health check server in background thread
        flask_thread = Thread(target=lambda: self.app.run(host='0.0.0.0', port=8080))
        flask_thread.daemon = True
        flask_thread.start()

        # Initialize RMR xApp
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=4560,
                            use_fake_sdl=False)

        # Start health check thread
        health_thread = Thread(target=self._health_check_loop)
        health_thread.daemon = True
        health_thread.start()

        # Small delay to ensure RMR is ready
        time.sleep(2)

        # Create E2 subscriptions
        self.create_subscriptions()

        # Start RMR message loop
        self.xapp.run()

    def stop(self):
        """Stop the xApp"""
        logger.info("Stopping Traffic Steering xApp...")
        self.running = False
        if self.xapp:
            self.xapp.stop()
        logger.info("Traffic Steering xApp stopped")

def main():
    """Main entry point"""

    # Create and start xApp
    xapp = TrafficSteeringXapp()
    xapp.start()

if __name__ == "__main__":
    main()
