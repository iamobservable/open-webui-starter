#!/usr/bin/env python3
"""
ERNI-KI Webhook Receiver для обработки алертов
Обрабатывает уведомления от Alertmanager и отправляет их в различные каналы
"""

import json
import logging
import os
import requests
from datetime import datetime
from flask import Flask, request, jsonify
from typing import Dict, List, Any

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Конфигурация из переменных окружения
DISCORD_WEBHOOK_URL = os.getenv('DISCORD_WEBHOOK_URL', '')
SLACK_WEBHOOK_URL = os.getenv('SLACK_WEBHOOK_URL', '')
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID', '')

class AlertProcessor:
    """Обработчик алертов с поддержкой различных каналов уведомлений"""

    def __init__(self):
        self.severity_colors = {
            'critical': 0xFF0000,  # Красный
            'warning': 0xFFA500,   # Оранжевый
            'info': 0x0099FF       # Синий
        }

        self.severity_emojis = {
            'critical': '🚨',
            'warning': '⚠️',
            'info': 'ℹ️'
        }

    def process_alerts(self, alerts_data: Dict[str, Any]) -> Dict[str, Any]:
        """Обработка входящих алертов"""
        try:
            alerts = alerts_data.get('alerts', [])
            group_labels = alerts_data.get('groupLabels', {})

            logger.info(f"Processing {len(alerts)} alerts")

            results = {
                'processed': 0,
                'errors': [],
                'notifications_sent': []
            }

            for alert in alerts:
                try:
                    self._process_single_alert(alert, group_labels)
                    results['processed'] += 1
                except Exception as e:
                    logger.error(f"Error processing alert: {e}")
                    results['errors'].append(str(e))

            return results

        except Exception as e:
            logger.error(f"Error processing alerts: {e}")
            return {'error': str(e)}

    def _process_single_alert(self, alert: Dict[str, Any], group_labels: Dict[str, Any]):
        """Обработка одного алерта"""
        labels = alert.get('labels', {})
        annotations = alert.get('annotations', {})
        status = alert.get('status', 'unknown')

        # Определение серьезности
        severity = labels.get('severity', 'info')
        service = labels.get('service', 'unknown')
        category = labels.get('category', 'general')

        # Создание сообщения
        message_data = {
            'alert_name': labels.get('alertname', 'Unknown Alert'),
            'severity': severity,
            'service': service,
            'category': category,
            'status': status,
            'summary': annotations.get('summary', 'No summary available'),
            'description': annotations.get('description', 'No description available'),
            'instance': labels.get('instance', 'unknown'),
            'timestamp': datetime.now().isoformat(),
            'group_labels': group_labels
        }

        # Отправка уведомлений
        if DISCORD_WEBHOOK_URL:
            self._send_discord_notification(message_data)

        if SLACK_WEBHOOK_URL:
            self._send_slack_notification(message_data)

        if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
            self._send_telegram_notification(message_data)

    def _send_discord_notification(self, message_data: Dict[str, Any]):
        """Отправка уведомления в Discord"""
        try:
            severity = message_data['severity']
            emoji = self.severity_emojis.get(severity, 'ℹ️')
            color = self.severity_colors.get(severity, 0x0099FF)

            embed = {
                "title": f"{emoji} {message_data['alert_name']}",
                "description": message_data['summary'],
                "color": color,
                "fields": [
                    {
                        "name": "🔧 Service / Сервис",
                        "value": message_data['service'],
                        "inline": True
                    },
                    {
                        "name": "📊 Category / Категория",
                        "value": message_data['category'],
                        "inline": True
                    },
                    {
                        "name": "🎯 Instance / Экземпляр",
                        "value": message_data['instance'],
                        "inline": True
                    },
                    {
                        "name": "📝 Description / Описание",
                        "value": message_data['description'],
                        "inline": False
                    }
                ],
                "timestamp": message_data['timestamp'],
                "footer": {
                    "text": f"ERNI-KI Monitoring • Status: {message_data['status']}"
                }
            }

            payload = {
                "embeds": [embed],
                "username": "ERNI-KI Monitor"
            }

            response = requests.post(DISCORD_WEBHOOK_URL, json=payload, timeout=10)
            response.raise_for_status()

            logger.info(f"Discord notification sent for {message_data['alert_name']}")

        except Exception as e:
            logger.error(f"Failed to send Discord notification: {e}")

    def _send_slack_notification(self, message_data: Dict[str, Any]):
        """Отправка уведомления в Slack"""
        try:
            severity = message_data['severity']
            emoji = self.severity_emojis.get(severity, 'ℹ️')

            color_map = {
                'critical': 'danger',
                'warning': 'warning',
                'info': 'good'
            }
            color = color_map.get(severity, 'good')

            attachment = {
                "color": color,
                "title": f"{emoji} {message_data['alert_name']}",
                "text": message_data['summary'],
                "fields": [
                    {
                        "title": "Service",
                        "value": message_data['service'],
                        "short": True
                    },
                    {
                        "title": "Instance",
                        "value": message_data['instance'],
                        "short": True
                    },
                    {
                        "title": "Description",
                        "value": message_data['description'],
                        "short": False
                    }
                ],
                "footer": "ERNI-KI Monitoring",
                "ts": int(datetime.now().timestamp())
            }

            payload = {
                "attachments": [attachment],
                "username": "ERNI-KI Monitor"
            }

            response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=10)
            response.raise_for_status()

            logger.info(f"Slack notification sent for {message_data['alert_name']}")

        except Exception as e:
            logger.error(f"Failed to send Slack notification: {e}")

    def _send_telegram_notification(self, message_data: Dict[str, Any]):
        """Отправка уведомления в Telegram"""
        try:
            severity = message_data['severity']
            emoji = self.severity_emojis.get(severity, 'ℹ️')

            text = f"""
{emoji} *{message_data['alert_name']}*

📝 *Summary:* {message_data['summary']}
🔧 *Service:* {message_data['service']}
📊 *Category:* {message_data['category']}
🎯 *Instance:* {message_data['instance']}
⏰ *Time:* {message_data['timestamp']}

📄 *Description:*
{message_data['description']}

🔗 *Status:* {message_data['status']}
            """.strip()

            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            payload = {
                "chat_id": TELEGRAM_CHAT_ID,
                "text": text,
                "parse_mode": "Markdown"
            }

            response = requests.post(url, json=payload, timeout=10)
            response.raise_for_status()

            logger.info(f"Telegram notification sent for {message_data['alert_name']}")

        except Exception as e:
            logger.error(f"Failed to send Telegram notification: {e}")

# Инициализация процессора алертов
alert_processor = AlertProcessor()

@app.route('/webhook/critical', methods=['POST'])
def handle_critical_webhook():
    """Обработка критических алертов"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400

        logger.info("Received critical alert webhook")
        result = alert_processor.process_alerts(data)

        return jsonify({
            'status': 'success',
            'message': 'Critical alerts processed',
            'result': result
        })

    except Exception as e:
        logger.error(f"Error handling critical webhook: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/webhook/warning', methods=['POST'])
def handle_warning_webhook():
    """Обработка предупреждающих алертов"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400

        logger.info("Received warning alert webhook")
        result = alert_processor.process_alerts(data)

        return jsonify({
            'status': 'success',
            'message': 'Warning alerts processed',
            'result': result
        })

    except Exception as e:
        logger.error(f"Error handling warning webhook: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'erni-ki-webhook-receiver',
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    logger.info("Starting ERNI-KI Webhook Receiver")
    app.run(host='0.0.0.0', port=9093, debug=False)
