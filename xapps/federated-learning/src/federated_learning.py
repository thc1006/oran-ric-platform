#!/usr/bin/env python3
"""
Federated Learning xApp - Distributed ML Training Application
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
import hashlib
import pickle
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass
import numpy as np
import tensorflow as tf
from tensorflow import keras
import torch
import torch.nn as nn
from ricxappframe.xapp_frame import RMRXapp, rmr
from ricxappframe.mdclogger import Logger
from flask import Flask, request, jsonify
import redis
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import serialization

# Configure logging
logger = Logger(name="FEDERATED_LEARNING")
logger.set_level(logging.INFO)

# Flask app for REST API  
app = Flask(__name__)

# Message Types for Federated Learning
FL_INIT_REQ = 30001
FL_INIT_RESP = 30002
FL_MODEL_REQ = 30003
FL_MODEL_RESP = 30004
FL_GRADIENT_SEND = 30005
FL_GRADIENT_ACK = 30006
FL_AGG_MODEL_SEND = 30007
FL_AGG_MODEL_ACK = 30008
FL_TRAINING_STATUS = 30009
RIC_INDICATION = 12050

@dataclass
class FLModel:
    """Federated Learning Model"""
    model_id: str
    model_type: str
    version: int
    architecture: Dict
    parameters: np.ndarray
    timestamp: str
    round_number: int
    participants: List[str]
    accuracy: Optional[float] = None

@dataclass
class FLClient:
    """Federated Learning Client"""
    client_id: str
    cell_id: str
    status: str
    model_version: int
    last_update: str
    data_samples: int
    local_accuracy: Optional[float] = None

class FederatedLearning:
    """
    Federated Learning xApp implementation
    Coordinates distributed ML training across RAN nodes
    """
    
    def __init__(self, config_path: str = "/app/config/config.json"):
        """Initialize Federated Learning xApp"""
        self.config = self._load_config(config_path)
        self.xapp = None
        self.running = False
        
        # FL State
        self.current_round = 0
        self.global_model = None
        self.local_models = {}
        self.clients = {}
        self.gradients_buffer = {}
        self.training_history = []
        
        # Security
        self.private_key = None
        self.public_keys = {}
        
        # Initialize Redis
        self._init_redis()
        
        # Initialize models
        self._init_fl_models()
        
        # Metrics
        self.metrics = {
            'rounds_completed': 0,
            'total_clients': 0,
            'active_clients': 0,
            'global_accuracy': 0.0,
            'convergence_rate': 0.0,
            'communication_rounds': 0,
            'total_data_processed': 0
        }
        
        logger.info(f"Federated Learning xApp initialized with config: {self.config}")
    
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
            "xapp_name": "federated-learning",
            "version": "1.0.0",
            "rmr_port": 4590,
            "http_port": 8110,
            "redis": {
                "host": "redis-service.ricplt",
                "port": 6379,
                "db": 3
            },
            "fl_config": {
                "min_clients": 3,
                "max_clients": 100,
                "rounds": 100,
                "local_epochs": 5,
                "batch_size": 32,
                "learning_rate": 0.01,
                "aggregation_method": "fedavg",
                "differential_privacy": {
                    "enabled": True,
                    "epsilon": 1.0,
                    "delta": 1e-5,
                    "clip_norm": 1.0
                },
                "secure_aggregation": True,
                "model_compression": {
                    "enabled": True,
                    "method": "quantization",
                    "bits": 8
                }
            },
            "models": {
                "network_optimization": {
                    "type": "tensorflow",
                    "architecture": "cnn",
                    "input_shape": [100, 20],
                    "output_classes": 5
                },
                "anomaly_detection": {
                    "type": "pytorch",
                    "architecture": "autoencoder",
                    "latent_dim": 32
                },
                "traffic_prediction": {
                    "type": "tensorflow",
                    "architecture": "lstm",
                    "sequence_length": 24,
                    "features": 10
                }
            },
            "security": {
                "encryption": True,
                "authentication": True,
                "key_size": 2048
            }
        }
    
    def _init_redis(self):
        """Initialize Redis connection"""
        try:
            self.redis_client = redis.Redis(
                host=self.config['redis']['host'],
                port=self.config['redis']['port'],
                db=self.config['redis']['db'],
                decode_responses=False  # Binary data for models
            )
            self.redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            self.redis_client = None
    
    def _init_fl_models(self):
        """Initialize federated learning models"""
        try:
            # Initialize security keys
            if self.config['security']['encryption']:
                self.private_key = rsa.generate_private_key(
                    public_exponent=65537,
                    key_size=self.config['security']['key_size']
                )
            
            # Initialize global models
            self.models = {}
            
            # Network Optimization Model
            if 'network_optimization' in self.config['models']:
                self.models['network_optimization'] = self._create_network_model()
            
            # Anomaly Detection Model
            if 'anomaly_detection' in self.config['models']:
                self.models['anomaly_detection'] = self._create_anomaly_model()
            
            # Traffic Prediction Model
            if 'traffic_prediction' in self.config['models']:
                self.models['traffic_prediction'] = self._create_traffic_model()
            
            logger.info("Federated learning models initialized")
            
        except Exception as e:
            logger.error(f"Failed to initialize FL models: {e}")
    
    def _create_network_model(self) -> keras.Model:
        """Create network optimization model"""
        config = self.config['models']['network_optimization']
        
        model = keras.Sequential([
            keras.layers.Input(shape=config['input_shape']),
            keras.layers.Conv1D(64, 3, activation='relu'),
            keras.layers.MaxPooling1D(2),
            keras.layers.Conv1D(128, 3, activation='relu'),
            keras.layers.GlobalMaxPooling1D(),
            keras.layers.Dense(64, activation='relu'),
            keras.layers.Dropout(0.3),
            keras.layers.Dense(config['output_classes'], activation='softmax')
        ])
        
        model.compile(
            optimizer=keras.optimizers.Adam(
                learning_rate=self.config['fl_config']['learning_rate']
            ),
            loss='categorical_crossentropy',
            metrics=['accuracy']
        )
        
        return model
    
    def _create_anomaly_model(self) -> nn.Module:
        """Create anomaly detection autoencoder"""
        class Autoencoder(nn.Module):
            def __init__(self, input_dim=100, latent_dim=32):
                super(Autoencoder, self).__init__()
                # Encoder
                self.encoder = nn.Sequential(
                    nn.Linear(input_dim, 64),
                    nn.ReLU(),
                    nn.Linear(64, latent_dim),
                    nn.ReLU()
                )
                # Decoder
                self.decoder = nn.Sequential(
                    nn.Linear(latent_dim, 64),
                    nn.ReLU(),
                    nn.Linear(64, input_dim),
                    nn.Sigmoid()
                )
            
            def forward(self, x):
                encoded = self.encoder(x)
                decoded = self.decoder(encoded)
                return decoded
        
        config = self.config['models']['anomaly_detection']
        return Autoencoder(latent_dim=config['latent_dim'])
    
    def _create_traffic_model(self) -> keras.Model:
        """Create traffic prediction LSTM model"""
        config = self.config['models']['traffic_prediction']
        
        model = keras.Sequential([
            keras.layers.LSTM(128, return_sequences=True, 
                            input_shape=(config['sequence_length'], config['features'])),
            keras.layers.Dropout(0.2),
            keras.layers.LSTM(64, return_sequences=True),
            keras.layers.Dropout(0.2),
            keras.layers.LSTM(32),
            keras.layers.Dense(config['features'])
        ])
        
        model.compile(
            optimizer=keras.optimizers.Adam(
                learning_rate=self.config['fl_config']['learning_rate']
            ),
            loss='mse',
            metrics=['mae']
        )
        
        return model
    
    def start(self):
        """Start the xApp"""
        logger.info("Starting Federated Learning xApp...")
        self.running = True

        # Start Flask API
        api_thread = threading.Thread(target=self._start_api)
        api_thread.daemon = True
        api_thread.start()

        # Start FL coordinator thread
        coordinator_thread = threading.Thread(target=self._fl_coordinator)
        coordinator_thread.daemon = True
        coordinator_thread.start()

        # Start aggregator thread
        aggregator_thread = threading.Thread(target=self._model_aggregator)
        aggregator_thread.daemon = True
        aggregator_thread.start()

        # Start monitoring thread
        monitor_thread = threading.Thread(target=self._monitor_training)
        monitor_thread.daemon = True
        monitor_thread.start()

        # Small delay to ensure threads are ready
        time.sleep(2)

        # Initialize RMR xApp (CRITICAL: Use composition pattern, not inheritance)
        # This follows the proven pattern from Traffic Steering xApp
        self.xapp = RMRXapp(self._handle_message,
                            rmr_port=self.config['rmr_port'],
                            use_fake_sdl=False)

        logger.info("Federated Learning xApp started successfully")

        # Run the xApp (blocking call)
        self.xapp.run()
    
    def _handle_message(self, xapp, summary, payload):
        """Handle incoming RMR messages"""
        msg_type = summary[rmr.RMR_MS_MSG_TYPE]
        
        if msg_type == FL_INIT_RESP:
            self._handle_init_response(payload)
        elif msg_type == FL_MODEL_RESP:
            self._handle_model_response(payload)
        elif msg_type == FL_GRADIENT_SEND:
            self._handle_gradient_update(payload)
        elif msg_type == FL_AGG_MODEL_ACK:
            self._handle_aggregation_ack(payload)
        elif msg_type == FL_TRAINING_STATUS:
            self._handle_training_status(payload)
        elif msg_type == RIC_INDICATION:
            self._handle_indication(payload)
        else:
            logger.debug(f"Received message type: {msg_type}")
    
    def _handle_init_response(self, payload):
        """Handle FL initialization response from client"""
        try:
            response = json.loads(payload)
            client_id = response.get('client_id')
            cell_id = response.get('cell_id')
            data_samples = response.get('data_samples', 0)
            public_key = response.get('public_key')
            
            # Register client
            self.clients[client_id] = FLClient(
                client_id=client_id,
                cell_id=cell_id,
                status='ready',
                model_version=0,
                last_update=datetime.now().isoformat(),
                data_samples=data_samples
            )
            
            # Store public key if using secure aggregation
            if public_key and self.config['fl_config']['secure_aggregation']:
                self.public_keys[client_id] = public_key
            
            self.metrics['total_clients'] += 1
            self.metrics['active_clients'] += 1
            
            logger.info(f"FL client registered: {client_id} with {data_samples} samples")
            
        except Exception as e:
            logger.error(f"Error handling init response: {e}")
    
    def _handle_model_response(self, payload):
        """Handle model update response from client"""
        try:
            # Deserialize model update
            update = pickle.loads(payload)
            client_id = update.get('client_id')
            model_type = update.get('model_type')
            round_number = update.get('round')
            
            # Verify round number
            if round_number != self.current_round:
                logger.warning(f"Received update for wrong round from {client_id}")
                return
            
            # Store local model update
            if client_id not in self.local_models:
                self.local_models[client_id] = {}
            
            self.local_models[client_id][model_type] = {
                'weights': update.get('weights'),
                'metrics': update.get('metrics'),
                'timestamp': datetime.now().isoformat()
            }
            
            # Update client status
            if client_id in self.clients:
                self.clients[client_id].status = 'updated'
                self.clients[client_id].model_version = round_number
                self.clients[client_id].local_accuracy = update.get('metrics', {}).get('accuracy')
            
            logger.info(f"Received model update from {client_id} for round {round_number}")
            
        except Exception as e:
            logger.error(f"Error handling model response: {e}")
    
    def _handle_gradient_update(self, payload):
        """Handle gradient update for secure aggregation"""
        try:
            if self.config['fl_config']['secure_aggregation']:
                # Decrypt gradient if encrypted
                gradient_data = self._decrypt_gradient(payload)
            else:
                gradient_data = pickle.loads(payload)
            
            client_id = gradient_data.get('client_id')
            gradients = gradient_data.get('gradients')
            
            # Apply differential privacy if enabled
            if self.config['fl_config']['differential_privacy']['enabled']:
                gradients = self._apply_differential_privacy(gradients)
            
            # Store gradients
            if self.current_round not in self.gradients_buffer:
                self.gradients_buffer[self.current_round] = {}
            
            self.gradients_buffer[self.current_round][client_id] = gradients
            
            # Send acknowledgment
            ack = {
                'client_id': client_id,
                'round': self.current_round,
                'status': 'received'
            }
            self._send_message(FL_GRADIENT_ACK, json.dumps(ack))
            
        except Exception as e:
            logger.error(f"Error handling gradient update: {e}")
    
    def _handle_aggregation_ack(self, payload):
        """Handle acknowledgment of aggregated model"""
        try:
            ack = json.loads(payload)
            client_id = ack.get('client_id')
            
            if client_id in self.clients:
                self.clients[client_id].status = 'synchronized'
                self.clients[client_id].model_version = self.current_round
            
        except Exception as e:
            logger.error(f"Error handling aggregation ack: {e}")
    
    def _handle_training_status(self, payload):
        """Handle training status update from client"""
        try:
            status = json.loads(payload)
            client_id = status.get('client_id')
            
            if client_id in self.clients:
                self.clients[client_id].status = status.get('status')
                self.clients[client_id].last_update = datetime.now().isoformat()
            
            # Log training metrics
            metrics = status.get('metrics', {})
            if metrics:
                logger.info(f"Client {client_id} metrics: {metrics}")
            
        except Exception as e:
            logger.error(f"Error handling training status: {e}")
    
    def _handle_indication(self, payload):
        """Handle RIC indication with training data"""
        try:
            indication = json.loads(payload)
            # Process network metrics for model training
            # This would be used to trigger FL rounds based on data availability
            
        except Exception as e:
            logger.error(f"Error handling indication: {e}")
    
    def _fl_coordinator(self):
        """Main federated learning coordination loop"""
        while self.running:
            try:
                # Check if enough clients are available
                active_clients = [c for c in self.clients.values() 
                                if c.status in ['ready', 'synchronized']]
                
                if len(active_clients) >= self.config['fl_config']['min_clients']:
                    # Start new FL round
                    self.current_round += 1
                    logger.info(f"Starting FL round {self.current_round}")
                    
                    # Select clients for this round
                    selected_clients = self._select_clients(active_clients)
                    
                    # Send global model to selected clients
                    for client in selected_clients:
                        self._send_global_model(client.client_id)
                    
                    # Wait for updates
                    time.sleep(30)  # Configurable timeout
                    
                    # Trigger aggregation
                    self._trigger_aggregation()
                    
                    self.metrics['rounds_completed'] += 1
                    self.metrics['communication_rounds'] += len(selected_clients)
                
                time.sleep(10)  # Check interval
                
            except Exception as e:
                logger.error(f"Error in FL coordinator: {e}")
                time.sleep(10)
    
    def _select_clients(self, available_clients: List[FLClient]) -> List[FLClient]:
        """Select clients for FL round"""
        # Implement client selection strategy
        # Could be random, based on data quality, or other criteria
        
        max_clients = min(
            len(available_clients),
            self.config['fl_config']['max_clients']
        )
        
        # Simple random selection for now
        import random
        selected = random.sample(available_clients, 
                               min(max_clients, len(available_clients)))
        
        logger.info(f"Selected {len(selected)} clients for round {self.current_round}")
        return selected
    
    def _send_global_model(self, client_id: str):
        """Send global model to client for local training"""
        try:
            for model_type, model in self.models.items():
                # Serialize model
                if isinstance(model, keras.Model):
                    weights = model.get_weights()
                elif isinstance(model, nn.Module):
                    weights = model.state_dict()
                else:
                    weights = None
                
                if weights:
                    model_data = {
                        'model_type': model_type,
                        'round': self.current_round,
                        'weights': weights,
                        'config': self.config['fl_config']
                    }
                    
                    # Send to client
                    self._send_message(FL_MODEL_REQ, pickle.dumps(model_data))
                    logger.debug(f"Sent {model_type} model to {client_id}")
            
        except Exception as e:
            logger.error(f"Error sending global model: {e}")
    
    def _model_aggregator(self):
        """Aggregate local models into global model"""
        while self.running:
            try:
                # Wait for aggregation trigger
                time.sleep(1)
                
                if hasattr(self, '_aggregation_triggered') and self._aggregation_triggered:
                    self._aggregation_triggered = False
                    
                    # Perform aggregation for each model type
                    for model_type in self.models.keys():
                        aggregated_weights = self._aggregate_models(model_type)
                        
                        if aggregated_weights:
                            # Update global model
                            self._update_global_model(model_type, aggregated_weights)
                            
                            # Evaluate global model
                            accuracy = self._evaluate_global_model(model_type)
                            self.metrics['global_accuracy'] = accuracy
                            
                            # Broadcast updated model
                            self._broadcast_aggregated_model(model_type)
                            
                            logger.info(f"Aggregation complete for {model_type}, accuracy: {accuracy}")
                
            except Exception as e:
                logger.error(f"Error in model aggregator: {e}")
                time.sleep(5)
    
    def _aggregate_models(self, model_type: str) -> Optional[Any]:
        """Aggregate local model updates"""
        try:
            method = self.config['fl_config']['aggregation_method']
            
            if method == 'fedavg':
                return self._federated_averaging(model_type)
            elif method == 'fedprox':
                return self._federated_proximal(model_type)
            elif method == 'scaffold':
                return self._scaffold_aggregation(model_type)
            else:
                logger.error(f"Unknown aggregation method: {method}")
                return None
                
        except Exception as e:
            logger.error(f"Error aggregating models: {e}")
            return None
    
    def _federated_averaging(self, model_type: str) -> Optional[Any]:
        """FedAvg aggregation algorithm"""
        try:
            # Collect weights from all clients
            client_weights = []
            client_samples = []
            
            for client_id, models in self.local_models.items():
                if model_type in models:
                    client_weights.append(models[model_type]['weights'])
                    if client_id in self.clients:
                        client_samples.append(self.clients[client_id].data_samples)
                    else:
                        client_samples.append(1)
            
            if not client_weights:
                return None
            
            # Calculate weighted average
            total_samples = sum(client_samples)
            avg_weights = None
            
            if isinstance(client_weights[0], list):  # Keras weights
                avg_weights = []
                for i in range(len(client_weights[0])):
                    weighted_sum = sum(
                        w[i] * s / total_samples 
                        for w, s in zip(client_weights, client_samples)
                    )
                    avg_weights.append(weighted_sum)
            elif isinstance(client_weights[0], dict):  # PyTorch state_dict
                avg_weights = {}
                for key in client_weights[0].keys():
                    weighted_sum = sum(
                        w[key] * s / total_samples
                        for w, s in zip(client_weights, client_samples)
                    )
                    avg_weights[key] = weighted_sum
            
            return avg_weights
            
        except Exception as e:
            logger.error(f"Error in federated averaging: {e}")
            return None
    
    def _federated_proximal(self, model_type: str) -> Optional[Any]:
        """FedProx aggregation with proximal term"""
        # Implementation of FedProx algorithm
        # Similar to FedAvg but with proximal regularization
        return self._federated_averaging(model_type)  # Simplified for now
    
    def _scaffold_aggregation(self, model_type: str) -> Optional[Any]:
        """SCAFFOLD aggregation with control variates"""
        # Implementation of SCAFFOLD algorithm
        # Uses control variates to reduce client drift
        return self._federated_averaging(model_type)  # Simplified for now
    
    def _update_global_model(self, model_type: str, weights: Any):
        """Update global model with aggregated weights"""
        try:
            model = self.models.get(model_type)
            
            if isinstance(model, keras.Model):
                model.set_weights(weights)
            elif isinstance(model, nn.Module):
                model.load_state_dict(weights)
            
            # Store in Redis
            if self.redis_client:
                key = f"fl:model:{model_type}:round_{self.current_round}"
                self.redis_client.setex(key, 86400, pickle.dumps(weights))
            
        except Exception as e:
            logger.error(f"Error updating global model: {e}")
    
    def _evaluate_global_model(self, model_type: str) -> float:
        """Evaluate global model performance"""
        # This would use a validation dataset
        # For now, return average of client accuracies
        accuracies = []
        for client_id, models in self.local_models.items():
            if model_type in models:
                metrics = models[model_type].get('metrics', {})
                if 'accuracy' in metrics:
                    accuracies.append(metrics['accuracy'])
        
        return np.mean(accuracies) if accuracies else 0.0
    
    def _broadcast_aggregated_model(self, model_type: str):
        """Broadcast aggregated model to all clients"""
        try:
            model = self.models.get(model_type)
            
            if model:
                # Get model weights
                if isinstance(model, keras.Model):
                    weights = model.get_weights()
                elif isinstance(model, nn.Module):
                    weights = model.state_dict()
                else:
                    return
                
                # Compress if enabled
                if self.config['fl_config']['model_compression']['enabled']:
                    weights = self._compress_model(weights)
                
                # Create broadcast message
                broadcast_data = {
                    'model_type': model_type,
                    'round': self.current_round,
                    'weights': weights,
                    'timestamp': datetime.now().isoformat()
                }
                
                # Send to all active clients
                self._send_message(FL_AGG_MODEL_SEND, pickle.dumps(broadcast_data))
                logger.info(f"Broadcasted aggregated {model_type} model")
            
        except Exception as e:
            logger.error(f"Error broadcasting model: {e}")
    
    def _compress_model(self, weights: Any) -> Any:
        """Compress model weights for efficient transmission"""
        method = self.config['fl_config']['model_compression']['method']
        
        if method == 'quantization':
            bits = self.config['fl_config']['model_compression']['bits']
            # Implement quantization
            # For simplicity, returning original weights
            return weights
        elif method == 'pruning':
            # Implement pruning
            return weights
        else:
            return weights
    
    def _apply_differential_privacy(self, gradients: Any) -> Any:
        """Apply differential privacy to gradients"""
        try:
            epsilon = self.config['fl_config']['differential_privacy']['epsilon']
            delta = self.config['fl_config']['differential_privacy']['delta']
            clip_norm = self.config['fl_config']['differential_privacy']['clip_norm']
            
            # Clip gradients
            if isinstance(gradients, np.ndarray):
                norm = np.linalg.norm(gradients)
                if norm > clip_norm:
                    gradients = gradients * (clip_norm / norm)
                
                # Add noise
                noise_scale = clip_norm * np.sqrt(2 * np.log(1.25 / delta)) / epsilon
                noise = np.random.normal(0, noise_scale, gradients.shape)
                gradients += noise
            
            return gradients
            
        except Exception as e:
            logger.error(f"Error applying differential privacy: {e}")
            return gradients
    
    def _decrypt_gradient(self, encrypted_payload: bytes) -> Dict:
        """Decrypt gradient using private key"""
        try:
            if self.private_key:
                # Implement decryption logic
                # For now, just deserialize
                return pickle.loads(encrypted_payload)
            else:
                return pickle.loads(encrypted_payload)
        except Exception as e:
            logger.error(f"Error decrypting gradient: {e}")
            return {}
    
    def _trigger_aggregation(self):
        """Trigger model aggregation"""
        self._aggregation_triggered = True
    
    def _monitor_training(self):
        """Monitor FL training progress"""
        while self.running:
            try:
                # Calculate convergence metrics
                if len(self.training_history) > 1:
                    recent_accuracies = [h['accuracy'] for h in self.training_history[-10:]]
                    if len(recent_accuracies) > 1:
                        improvement = recent_accuracies[-1] - recent_accuracies[0]
                        self.metrics['convergence_rate'] = improvement / len(recent_accuracies)
                
                # Store training snapshot
                snapshot = {
                    'round': self.current_round,
                    'accuracy': self.metrics['global_accuracy'],
                    'active_clients': self.metrics['active_clients'],
                    'timestamp': datetime.now().isoformat()
                }
                self.training_history.append(snapshot)
                
                # Store in Redis
                if self.redis_client:
                    key = f"fl:history:{self.current_round}"
                    self.redis_client.setex(key, 86400, json.dumps(snapshot))
                
                time.sleep(30)  # Monitoring interval
                
            except Exception as e:
                logger.error(f"Error in training monitor: {e}")
                time.sleep(30)
    
    def _send_message(self, msg_type: int, payload: bytes):
        """Send RMR message"""
        if self.xapp:
            if isinstance(payload, str):
                payload = payload.encode()
            success = self.xapp.rmr_send(payload, msg_type)
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
        
        @app.route('/fl/status', methods=['GET'])
        def get_fl_status():
            """Get federated learning status"""
            status = {
                'current_round': self.current_round,
                'clients': len(self.clients),
                'active_clients': len([c for c in self.clients.values() 
                                      if c.status == 'ready']),
                'metrics': self.metrics,
                'models': list(self.models.keys())
            }
            return jsonify(status), 200
        
        @app.route('/fl/clients', methods=['GET'])
        def get_clients():
            """Get list of FL clients"""
            clients_info = [
                {
                    'client_id': c.client_id,
                    'cell_id': c.cell_id,
                    'status': c.status,
                    'model_version': c.model_version,
                    'data_samples': c.data_samples,
                    'local_accuracy': c.local_accuracy
                }
                for c in self.clients.values()
            ]
            return jsonify(clients_info), 200
        
        @app.route('/fl/start', methods=['POST'])
        def start_fl_round():
            """Manually start FL round"""
            self._trigger_aggregation()
            return jsonify({'status': 'FL round triggered'}), 200
        
        @app.route('/fl/history', methods=['GET'])
        def get_training_history():
            """Get FL training history"""
            return jsonify(self.training_history[-100:]), 200  # Last 100 rounds
        
        @app.route('/metrics', methods=['GET'])
        def get_metrics():
            """Get FL metrics"""
            return jsonify(self.metrics), 200
        
        app.run(host='0.0.0.0', port=self.config['http_port'])
    
    def stop(self):
        """Stop the xApp"""
        logger.info("Stopping Federated Learning xApp...")
        self.running = False
        if self.xapp:
            self.xapp.stop()
        logger.info("Federated Learning xApp stopped")


if __name__ == "__main__":
    # Create and start Federated Learning xApp
    fl_xapp = FederatedLearning()
    
    try:
        fl_xapp.start()
    except KeyboardInterrupt:
        fl_xapp.stop()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        fl_xapp.stop()
