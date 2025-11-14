#!/usr/bin/env python3
"""
QoE Predictor xApp - Quality of Experience Prediction Application
O-RAN Release J compliant implementation
Version: 1.0.0
Author: 蔡秀吉 (thc1006)

IMPORTANT: This xApp uses the COMPOSITION pattern for RMR API integration,
NOT inheritance. This is the proven approach from Phase 3 Traffic Steering.
"""

import json
import time
import logging
import threading
import pickle
from typing import Dict, List, Any, Tuple
from datetime import datetime, timedelta
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.preprocessing import StandardScaler
import tensorflow as tf
from tensorflow import keras
from ricxappframe.xapp_frame import RMRXapp, rmr
from ricxappframe.mdclogger import Logger
from flask import Flask, request, jsonify
import redis
import joblib

# Configure logging
logger = Logger(name="QOE_PREDICTOR")
logger.set_level(logging.INFO)

# Flask app for REST API
app = Flask(__name__)

# E2SM Message Types
RIC_INDICATION = 12050
RIC_SUB_REQ = 12010
RIC_SUB_RESP = 12011
A1_POLICY_REQ = 20010
A1_POLICY_RESP = 20011

class QoEPredictor:
    """
    QoE Predictor xApp implementation
    Uses AI/ML models to predict user Quality of Experience
    """
    
    def __init__(self, config_path: str = "/app/config/config.json"):
        """Initialize QoE Predictor xApp"""
        self.config = self._load_config(config_path)
        self.xapp = None
        self.running = False
        self.models = {}
        self.scalers = {}
        self.feature_buffer = {}
        self.predictions_cache = {}
        
        # Initialize Redis connection
        self._init_redis()
        
        # Initialize ML models
        self._init_models()
        
        # QoE metrics definitions
        self.qoe_metrics = {
            "video_quality": {
                "features": ["throughput_dl", "latency", "jitter", "packet_loss", "rsrp", "rsrq"],
                "model_type": "deep_learning",
                "output_range": [1, 5]  # MOS score 1-5
            },
            "voice_quality": {
                "features": ["latency", "jitter", "packet_loss", "mos_lq"],
                "model_type": "random_forest",
                "output_range": [1, 5]
            },
            "web_browsing": {
                "features": ["throughput_dl", "latency", "dns_time", "tcp_connect_time"],
                "model_type": "gradient_boosting",
                "output_range": [0, 100]  # Satisfaction score 0-100
            },
            "gaming": {
                "features": ["latency", "jitter", "packet_loss", "throughput_dl", "throughput_ul"],
                "model_type": "deep_learning",
                "output_range": [0, 100]
            }
        }
        
        logger.info(f"QoE Predictor xApp initialized with config: {self.config}")
    
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
            "xapp_name": "qoe-predictor",
            "version": "1.0.0",
            "rmr_port": 4570,
            "http_port": 8090,
            "redis": {
                "host": "redis-service.ricplt",
                "port": 6379,
                "db": 1
            },
            "models": {
                "update_interval": 3600,  # seconds
                "batch_size": 32,
                "prediction_window": 10,  # seconds
                "confidence_threshold": 0.8
            },
            "features": {
                "window_size": 100,
                "aggregation": ["mean", "std", "min", "max", "percentile_95"]
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
    
    def _init_models(self):
        """Initialize ML models for QoE prediction"""
        try:
            # Video Quality Model - Deep Learning
            self.models['video_quality'] = self._create_video_model()
            self.scalers['video_quality'] = StandardScaler()
            
            # Voice Quality Model - Random Forest
            self.models['voice_quality'] = RandomForestRegressor(
                n_estimators=100,
                max_depth=10,
                min_samples_split=5,
                random_state=42
            )
            self.scalers['voice_quality'] = StandardScaler()
            
            # Web Browsing Model - Gradient Boosting
            self.models['web_browsing'] = GradientBoostingRegressor(
                n_estimators=100,
                learning_rate=0.1,
                max_depth=5,
                random_state=42
            )
            self.scalers['web_browsing'] = StandardScaler()
            
            # Gaming Model - Deep Learning
            self.models['gaming'] = self._create_gaming_model()
            self.scalers['gaming'] = StandardScaler()
            
            # Try to load pre-trained models
            self._load_pretrained_models()
            
            logger.info("ML models initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize models: {e}")
    
    def _create_video_model(self) -> keras.Model:
        """Create deep learning model for video QoE prediction"""
        model = keras.Sequential([
            keras.layers.Dense(128, activation='relu', input_shape=(6,)),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(64, activation='relu'),
            keras.layers.Dropout(0.2),
            keras.layers.Dense(32, activation='relu'),
            keras.layers.Dense(1, activation='sigmoid')
        ])
        
        model.compile(
            optimizer=keras.optimizers.Adam(learning_rate=0.001),
            loss='mse',
            metrics=['mae']
        )
        
        return model
    
    def _create_gaming_model(self) -> keras.Model:
        """Create deep learning model for gaming QoE prediction"""
        model = keras.Sequential([
            keras.layers.Dense(64, activation='relu', input_shape=(5,)),
            keras.layers.BatchNormalization(),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(32, activation='relu'),
            keras.layers.BatchNormalization(),
            keras.layers.Dropout(0.2),
            keras.layers.Dense(16, activation='relu'),
            keras.layers.Dense(1, activation='sigmoid')
        ])
        
        model.compile(
            optimizer=keras.optimizers.Adam(learning_rate=0.001),
            loss='mse',
            metrics=['mae']
        )
        
        return model
    
    def _load_pretrained_models(self):
        """Load pre-trained models if available"""
        try:
            # Try loading from files
            model_dir = "/app/models"
            
            # Load video quality model
            video_model_path = f"{model_dir}/video_quality_model.h5"
            if tf.io.gfile.exists(video_model_path):
                self.models['video_quality'] = keras.models.load_model(video_model_path)
                logger.info("Loaded pre-trained video quality model")
            
            # Load voice quality model
            voice_model_path = f"{model_dir}/voice_quality_model.pkl"
            try:
                self.models['voice_quality'] = joblib.load(voice_model_path)
                logger.info("Loaded pre-trained voice quality model")
            except:
                pass
            
            # Load scalers
            for metric in self.qoe_metrics:
                scaler_path = f"{model_dir}/{metric}_scaler.pkl"
                try:
                    self.scalers[metric] = joblib.load(scaler_path)
                    logger.info(f"Loaded scaler for {metric}")
                except:
                    pass
                    
        except Exception as e:
            logger.warning(f"Could not load pre-trained models: {e}")
    
    def start(self):
        """Start the xApp"""
        logger.info("Starting QoE Predictor xApp...")
        self.running = True

        # Start Flask API in separate thread
        api_thread = threading.Thread(target=self._start_api)
        api_thread.daemon = True
        api_thread.start()

        # Start prediction thread
        prediction_thread = threading.Thread(target=self._prediction_loop)
        prediction_thread.daemon = True
        prediction_thread.start()

        # Start model update thread
        update_thread = threading.Thread(target=self._model_update_loop)
        update_thread.daemon = True
        update_thread.start()

        # Small delay to ensure threads are ready
        time.sleep(2)

        # Initialize RMR xApp (CRITICAL: Use composition pattern, not inheritance)
        # This follows the proven pattern from Traffic Steering xApp
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=self.config['rmr_port'],
                            use_fake_sdl=False)

        logger.info("QoE Predictor xApp started successfully")

        # Run the xApp (blocking call)
        self.xapp.run()
    
    def _handle_message(self, xapp, summary, payload):
        """Handle incoming RMR messages"""
        msg_type = summary[rmr.RMR_MS_MSG_TYPE]
        
        if msg_type == RIC_INDICATION:
            self._handle_indication(payload)
        elif msg_type == A1_POLICY_REQ:
            self._handle_policy_request(summary, payload)
        else:
            logger.debug(f"Received message type: {msg_type}")
    
    def _handle_indication(self, payload):
        """Handle RIC Indication with network metrics"""
        try:
            indication = json.loads(payload)
            
            ue_id = indication.get('ue_id')
            cell_id = indication.get('cell_id')
            timestamp = indication.get('timestamp', datetime.now().isoformat())
            measurements = indication.get('measurements', [])
            
            # Extract features for QoE prediction
            features = self._extract_features(measurements)
            
            # Store features in buffer
            if ue_id not in self.feature_buffer:
                self.feature_buffer[ue_id] = []
            
            self.feature_buffer[ue_id].append({
                'timestamp': timestamp,
                'cell_id': cell_id,
                'features': features
            })
            
            # Keep only recent data
            cutoff_time = datetime.now() - timedelta(seconds=self.config['features']['window_size'])
            self.feature_buffer[ue_id] = [
                f for f in self.feature_buffer[ue_id]
                if datetime.fromisoformat(f['timestamp']) > cutoff_time
            ]
            
        except Exception as e:
            logger.error(f"Error handling indication: {e}")
    
    def _handle_policy_request(self, summary, payload):
        """Handle A1 policy request for QoE thresholds"""
        try:
            policy = json.loads(payload)
            policy_type = policy.get('policy_type')
            
            if policy_type == 'qoe_threshold':
                # Update QoE thresholds
                thresholds = policy.get('thresholds', {})
                self._update_thresholds(thresholds)
                
                # Send response
                response = {
                    'policy_id': policy.get('policy_id'),
                    'status': 'accepted',
                    'timestamp': datetime.now().isoformat()
                }
                
                self._send_message(A1_POLICY_RESP, json.dumps(response))
                logger.info(f"Updated QoE thresholds: {thresholds}")
                
        except Exception as e:
            logger.error(f"Error handling policy request: {e}")
    
    def _extract_features(self, measurements: List[Dict]) -> Dict:
        """Extract features from measurements for QoE prediction"""
        features = {}
        
        for measurement in measurements:
            name = measurement.get('name', '').lower()
            value = measurement.get('value', 0)
            
            # Map measurements to features
            if 'thpdl' in name or 'throughput_dl' in name:
                features['throughput_dl'] = value
            elif 'thpul' in name or 'throughput_ul' in name:
                features['throughput_ul'] = value
            elif 'delay' in name or 'latency' in name:
                features['latency'] = value
            elif 'jitter' in name:
                features['jitter'] = value
            elif 'loss' in name:
                features['packet_loss'] = value
            elif 'rsrp' in name:
                features['rsrp'] = value
            elif 'rsrq' in name:
                features['rsrq'] = value
            elif 'sinr' in name:
                features['sinr'] = value
        
        return features
    
    def _prediction_loop(self):
        """Main prediction loop"""
        while self.running:
            try:
                # Process each UE in buffer
                for ue_id, buffer in self.feature_buffer.items():
                    if len(buffer) >= 5:  # Minimum samples needed
                        # Prepare features for prediction
                        features_df = pd.DataFrame([b['features'] for b in buffer])
                        
                        # Generate predictions for each QoE metric
                        predictions = {}
                        
                        for metric, config in self.qoe_metrics.items():
                            try:
                                # Select relevant features
                                metric_features = config['features']
                                available_features = [f for f in metric_features if f in features_df.columns]
                                
                                if len(available_features) >= 3:  # Minimum features needed
                                    X = features_df[available_features].fillna(0)
                                    
                                    # Aggregate features
                                    X_agg = self._aggregate_features(X)
                                    
                                    # Scale features
                                    if metric in self.scalers:
                                        try:
                                            X_scaled = self.scalers[metric].transform([X_agg])
                                        except:
                                            # Fit scaler if not fitted
                                            X_scaled = self.scalers[metric].fit_transform([X_agg])
                                    else:
                                        X_scaled = [X_agg]
                                    
                                    # Make prediction
                                    model = self.models.get(metric)
                                    if model:
                                        if config['model_type'] == 'deep_learning':
                                            pred = model.predict(X_scaled, verbose=0)[0][0]
                                        else:
                                            pred = model.predict(X_scaled)[0]
                                        
                                        # Scale to output range
                                        output_range = config['output_range']
                                        pred_scaled = output_range[0] + pred * (output_range[1] - output_range[0])
                                        
                                        predictions[metric] = {
                                            'value': float(pred_scaled),
                                            'confidence': self._calculate_confidence(X),
                                            'timestamp': datetime.now().isoformat()
                                        }
                            
                            except Exception as e:
                                logger.error(f"Error predicting {metric}: {e}")
                        
                        # Store predictions
                        if predictions:
                            self.predictions_cache[ue_id] = predictions
                            
                            # Store in Redis
                            if self.redis_client:
                                key = f"qoe:prediction:{ue_id}"
                                self.redis_client.setex(key, 60, json.dumps(predictions))
                            
                            # Check for QoE degradation
                            self._check_qoe_degradation(ue_id, predictions)
                
                time.sleep(self.config['models']['prediction_window'])
                
            except Exception as e:
                logger.error(f"Error in prediction loop: {e}")
                time.sleep(5)
    
    def _aggregate_features(self, features_df: pd.DataFrame) -> np.ndarray:
        """Aggregate features over time window"""
        aggregated = []
        
        for col in features_df.columns:
            values = features_df[col].values
            aggregated.extend([
                np.mean(values),
                np.std(values) if len(values) > 1 else 0,
                np.min(values),
                np.max(values),
                np.percentile(values, 95) if len(values) > 1 else values[0]
            ])
        
        return np.array(aggregated)
    
    def _calculate_confidence(self, features_df: pd.DataFrame) -> float:
        """Calculate prediction confidence based on feature quality"""
        # Simple confidence calculation based on data completeness
        total_features = len(features_df.columns) * len(features_df)
        non_null = features_df.notna().sum().sum()
        
        confidence = non_null / total_features if total_features > 0 else 0
        
        # Adjust based on sample size
        sample_factor = min(len(features_df) / 10, 1.0)
        
        return confidence * sample_factor
    
    def _check_qoe_degradation(self, ue_id: str, predictions: Dict):
        """Check for QoE degradation and trigger actions"""
        try:
            # Define thresholds
            thresholds = {
                'video_quality': 3.0,  # MOS < 3 is poor
                'voice_quality': 3.5,
                'web_browsing': 60,
                'gaming': 70
            }
            
            degraded_services = []
            
            for service, prediction in predictions.items():
                if service in thresholds:
                    if prediction['value'] < thresholds[service]:
                        degraded_services.append({
                            'service': service,
                            'qoe_score': prediction['value'],
                            'threshold': thresholds[service],
                            'confidence': prediction['confidence']
                        })
            
            if degraded_services:
                # Generate optimization recommendation
                recommendation = self._generate_optimization(ue_id, degraded_services)
                
                # Store in Redis
                if self.redis_client:
                    key = f"qoe:degradation:{ue_id}"
                    self.redis_client.setex(key, 300, json.dumps({
                        'degraded_services': degraded_services,
                        'recommendation': recommendation,
                        'timestamp': datetime.now().isoformat()
                    }))
                
                logger.warning(f"QoE degradation detected for UE {ue_id}: {degraded_services}")
                
        except Exception as e:
            logger.error(f"Error checking QoE degradation: {e}")
    
    def _generate_optimization(self, ue_id: str, degraded_services: List[Dict]) -> Dict:
        """Generate optimization recommendations"""
        recommendations = {
            'ue_id': ue_id,
            'actions': []
        }
        
        for service in degraded_services:
            if service['service'] == 'video_quality':
                recommendations['actions'].append({
                    'type': 'resource_allocation',
                    'priority': 'high',
                    'parameters': {
                        'min_bandwidth': 5,  # Mbps
                        'qci': 6  # Video streaming QCI
                    }
                })
            elif service['service'] == 'voice_quality':
                recommendations['actions'].append({
                    'type': 'handover',
                    'priority': 'critical',
                    'parameters': {
                        'target_selection': 'best_signal',
                        'qci': 1  # Voice QCI
                    }
                })
            elif service['service'] == 'gaming':
                recommendations['actions'].append({
                    'type': 'latency_optimization',
                    'priority': 'high',
                    'parameters': {
                        'max_latency': 20,  # ms
                        'jitter_buffer': 'adaptive'
                    }
                })
        
        return recommendations
    
    def _model_update_loop(self):
        """Periodically update ML models with new data"""
        while self.running:
            try:
                time.sleep(self.config['models']['update_interval'])
                
                # Collect training data from Redis
                if self.redis_client:
                    # This would be implemented to fetch labeled data
                    # and retrain models incrementally
                    logger.info("Checking for model updates...")
                    
            except Exception as e:
                logger.error(f"Error in model update loop: {e}")
    
    def _update_thresholds(self, thresholds: Dict):
        """Update QoE thresholds from A1 policy"""
        # Store thresholds in Redis
        if self.redis_client:
            self.redis_client.set('qoe:thresholds', json.dumps(thresholds))
    
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
        
        @app.route('/predict/<ue_id>', methods=['GET'])
        def get_prediction(ue_id):
            """Get QoE prediction for a specific UE"""
            if ue_id in self.predictions_cache:
                return jsonify(self.predictions_cache[ue_id]), 200
            return jsonify({'error': 'No predictions available'}), 404
        
        @app.route('/metrics', methods=['GET'])
        def get_metrics():
            """Get aggregated QoE metrics"""
            metrics = {
                'total_predictions': len(self.predictions_cache),
                'active_ues': len(self.feature_buffer),
                'timestamp': datetime.now().isoformat()
            }
            return jsonify(metrics), 200
        
        app.run(host='0.0.0.0', port=self.config['http_port'])
    
    def stop(self):
        """Stop the xApp"""
        logger.info("Stopping QoE Predictor xApp...")
        self.running = False
        if self.xapp:
            self.xapp.stop()
        logger.info("QoE Predictor xApp stopped")


if __name__ == "__main__":
    # Create and start QoE Predictor xApp
    qoe_predictor = QoEPredictor()
    
    try:
        qoe_predictor.start()
    except KeyboardInterrupt:
        qoe_predictor.stop()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        qoe_predictor.stop()
