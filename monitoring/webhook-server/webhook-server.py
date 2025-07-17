#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Webhook Server для системы алертинга ERNI-KI
Обработка уведомлений от Alertmanager и отправка в различные каналы
"""

import os
import sys
import json
import logging
import requests
import smtplib
import time
import hmac
import hashlib
import base64
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
from flask import Flask, request, jsonify, abort
from logging.handlers import RotatingFileHandler

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        RotatingFileHandler('/logs/webhook-server.log', maxBytes=10485760, backupCount=5),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('webhook-server')

# Инициализация Flask приложения
app = Flask(__name__)

# Конфигурация из переменных окружения
WEBHOOK_SECRET = os.environ.get('WEBHOOK_SECRET', 'webhook-secret')
DISCORD_WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK_URL', '')
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '')
SMTP_SERVER = os.environ.get('SMTP_SERVER', 'localhost')
SMTP_PORT = int(os.environ.get('SMTP_PORT', '25'))
SMTP_USERNAME = os.environ.get('SMTP_USERNAME', '')
SMTP_PASSWORD = os.environ.get('SMTP_PASSWORD', '')
SMTP_FROM = os.environ.get('SMTP_FROM', 'alerts@erni-ki.local')
ADMIN_EMAIL = os.environ.get('ADMIN_EMAIL', 'admin@erni-ki.local')
ENABLE_EMAIL = os.environ.get('ENABLE_EMAIL', 'false').lower() == 'true'
ENABLE_DISCORD = os.environ.get('ENABLE_DISCORD', 'false').lower() == 'true'
ENABLE_TELEGRAM = os.environ.get('ENABLE_TELEGRAM', 'false').lower() == 'true'
ENABLE_SLACK = os.environ.get('ENABLE_SLACK', 'false').lower() == 'true'
SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL', '')

# Цвета для различных уровней алертов
COLORS = {
    'critical': 0xFF0000,  # Красный
    'warning': 0xFFAA00,   # Оранжевый
    'info': 0x00AAFF,      # Синий
    'resolved': 0x00FF00,  # Зеленый
    'default': 0x888888    # Серый
}

# Иконки для различных категорий
ICONS = {
    'infrastructure': '🏗️',
    'security': '🔒',
    'ai': '🤖',
    'database': '💾',
    'cache': '⚡',
    'proxy': '🔄',
    'network': '🌐',
    'performance': '⚡',
    'default': '🔔'
}

# Проверка аутентификации
def verify_auth(auth_header):
    if not auth_header:
        return False
    
    try:
        auth_type, auth_value = auth_header.split(' ', 1)
        if auth_type.lower() != 'bearer':
            return False
        
        return auth_value == WEBHOOK_SECRET
    except Exception as e:
        logger.error(f"Ошибка аутентификации: {e}")
        return False

# Отправка уведомления в Discord
def send_discord_notification(alert_data):
    if not ENABLE_DISCORD or not DISCORD_WEBHOOK_URL:
        logger.info("Discord уведомления отключены или не настроены")
        return False
    
    try:
        # Получение данных алерта
        alerts = alert_data.get('alerts', [])
        if not alerts:
            logger.warning("Нет алертов для отправки в Discord")
            return False
        
        # Подготовка эмбедов для Discord
        embeds = []
        for alert in alerts:
            status = alert.get('status', 'firing')
            labels = alert.get('labels', {})
            annotations = alert.get('annotations', {})
            
            severity = labels.get('severity', 'default')
            category = labels.get('category', 'default')
            service = labels.get('service', 'unknown')
            
            # Определение цвета и иконки
            color = COLORS.get(severity, COLORS['default'])
            icon = ICONS.get(category, ICONS['default'])
            
            # Создание эмбеда
            embed = {
                "title": f"{icon} {annotations.get('summary', 'Алерт без заголовка')}",
                "description": annotations.get('description', 'Нет описания'),
                "color": color,
                "fields": [
                    {
                        "name": "Сервис",
                        "value": service,
                        "inline": True
                    },
                    {
                        "name": "Категория",
                        "value": category,
                        "inline": True
                    },
                    {
                        "name": "Важность",
                        "value": severity,
                        "inline": True
                    },
                    {
                        "name": "Статус",
                        "value": "✅ Исправлен" if status == "resolved" else "🔥 Активен",
                        "inline": True
                    }
                ],
                "timestamp": datetime.utcnow().isoformat()
            }
            
            # Добавление дополнительных полей
            if 'instance' in labels:
                embed["fields"].append({
                    "name": "Инстанс",
                    "value": labels['instance'],
                    "inline": True
                })
                
            if 'job' in labels:
                embed["fields"].append({
                    "name": "Job",
                    "value": labels['job'],
                    "inline": True
                })
            
            embeds.append(embed)
        
        # Подготовка данных для отправки
        payload = {
            "username": "ERNI-KI Monitoring",
            "avatar_url": "https://i.imgur.com/4M34hi2.png",
            "content": f"**{len(alerts)}** новых алертов" if status == "firing" else "Алерты исправлены",
            "embeds": embeds
        }
        
        # Отправка запроса
        response = requests.post(
            DISCORD_WEBHOOK_URL,
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 204:
            logger.info(f"Discord уведомление успешно отправлено: {len(alerts)} алертов")
            return True
        else:
            logger.error(f"Ошибка отправки Discord уведомления: {response.status_code} {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"Ошибка при отправке Discord уведомления: {e}")
        return False

# Отправка уведомления в Telegram
def send_telegram_notification(alert_data):
    if not ENABLE_TELEGRAM or not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.info("Telegram уведомления отключены или не настроены")
        return False
    
    try:
        # Получение данных алерта
        alerts = alert_data.get('alerts', [])
        if not alerts:
            logger.warning("Нет алертов для отправки в Telegram")
            return False
        
        # Формирование сообщения
        message = "*ERNI-KI Monitoring Alert*\n\n"
        
        for alert in alerts:
            status = alert.get('status', 'firing')
            labels = alert.get('labels', {})
            annotations = alert.get('annotations', {})
            
            severity = labels.get('severity', 'default')
            category = labels.get('category', 'default')
            service = labels.get('service', 'unknown')
            
            # Определение иконки
            icon = ICONS.get(category, ICONS['default'])
            status_icon = "✅" if status == "resolved" else "🔥"
            
            # Добавление информации об алерте
            message += f"{icon} *{annotations.get('summary', 'Алерт без заголовка')}*\n"
            message += f"_{annotations.get('description', 'Нет описания')}_\n\n"
            message += f"*Сервис:* {service}\n"
            message += f"*Категория:* {category}\n"
            message += f"*Важность:* {severity}\n"
            message += f"*Статус:* {status_icon} {status}\n"
            
            if 'instance' in labels:
                message += f"*Инстанс:* {labels['instance']}\n"
                
            if 'job' in labels:
                message += f"*Job:* {labels['job']}\n"
                
            message += "\n---\n\n"
        
        # Отправка запроса
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        payload = {
            "chat_id": TELEGRAM_CHAT_ID,
            "text": message,
            "parse_mode": "Markdown"
        }
        
        response = requests.post(url, json=payload)
        
        if response.status_code == 200:
            logger.info(f"Telegram уведомление успешно отправлено: {len(alerts)} алертов")
            return True
        else:
            logger.error(f"Ошибка отправки Telegram уведомления: {response.status_code} {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"Ошибка при отправке Telegram уведомления: {e}")
        return False

# Отправка уведомления по email
def send_email_notification(alert_data):
    if not ENABLE_EMAIL:
        logger.info("Email уведомления отключены")
        return False
    
    try:
        # Получение данных алерта
        alerts = alert_data.get('alerts', [])
        if not alerts:
            logger.warning("Нет алертов для отправки по email")
            return False
        
        # Определение получателя
        recipient = ADMIN_EMAIL
        
        # Создание сообщения
        msg = MIMEMultipart('alternative')
        msg['Subject'] = f"ERNI-KI Alert: {len(alerts)} новых алертов"
        msg['From'] = SMTP_FROM
        msg['To'] = recipient
        
        # Формирование HTML и текстового содержимого
        text_content = "ERNI-KI Monitoring Alert\n\n"
        html_content = """
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; }
                .alert { margin-bottom: 20px; padding: 10px; border-radius: 5px; }
                .critical { background-color: #ffdddd; border-left: 5px solid #ff0000; }
                .warning { background-color: #ffffdd; border-left: 5px solid #ffaa00; }
                .info { background-color: #ddffff; border-left: 5px solid #00aaff; }
                .resolved { background-color: #ddffdd; border-left: 5px solid #00ff00; }
                .default { background-color: #eeeeee; border-left: 5px solid #888888; }
                h2 { margin-top: 0; }
                .details { margin-top: 10px; }
                .label { font-weight: bold; }
            </style>
        </head>
        <body>
            <h1>ERNI-KI Monitoring Alert</h1>
        """
        
        for alert in alerts:
            status = alert.get('status', 'firing')
            labels = alert.get('labels', {})
            annotations = alert.get('annotations', {})
            
            severity = labels.get('severity', 'default')
            category = labels.get('category', 'default')
            service = labels.get('service', 'unknown')
            
            # Определение иконки
            icon = ICONS.get(category, ICONS['default'])
            status_icon = "✅" if status == "resolved" else "🔥"
            
            # Текстовое содержимое
            text_content += f"{icon} {annotations.get('summary', 'Алерт без заголовка')}\n"
            text_content += f"{annotations.get('description', 'Нет описания')}\n\n"
            text_content += f"Сервис: {service}\n"
            text_content += f"Категория: {category}\n"
            text_content += f"Важность: {severity}\n"
            text_content += f"Статус: {status_icon} {status}\n"
            
            if 'instance' in labels:
                text_content += f"Инстанс: {labels['instance']}\n"
                
            if 'job' in labels:
                text_content += f"Job: {labels['job']}\n"
                
            text_content += "\n---\n\n"
            
            # HTML содержимое
            html_content += f"""
            <div class="alert {severity}">
                <h2>{icon} {annotations.get('summary', 'Алерт без заголовка')}</h2>
                <p>{annotations.get('description', 'Нет описания')}</p>
                <div class="details">
                    <p><span class="label">Сервис:</span> {service}</p>
                    <p><span class="label">Категория:</span> {category}</p>
                    <p><span class="label">Важность:</span> {severity}</p>
                    <p><span class="label">Статус:</span> {status_icon} {status}</p>
            """
            
            if 'instance' in labels:
                html_content += f'<p><span class="label">Инстанс:</span> {labels["instance"]}</p>'
                
            if 'job' in labels:
                html_content += f'<p><span class="label">Job:</span> {labels["job"]}</p>'
                
            html_content += """
                </div>
            </div>
            """
        
        html_content += """
        </body>
        </html>
        """
        
        # Добавление содержимого в сообщение
        part1 = MIMEText(text_content, 'plain')
        part2 = MIMEText(html_content, 'html')
        msg.attach(part1)
        msg.attach(part2)
        
        # Отправка email
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            if SMTP_USERNAME and SMTP_PASSWORD:
                server.starttls()
                server.login(SMTP_USERNAME, SMTP_PASSWORD)
            server.send_message(msg)
            
        logger.info(f"Email уведомление успешно отправлено на {recipient}: {len(alerts)} алертов")
        return True
        
    except Exception as e:
        logger.error(f"Ошибка при отправке email уведомления: {e}")
        return False

# Отправка уведомления в Slack
def send_slack_notification(alert_data):
    if not ENABLE_SLACK or not SLACK_WEBHOOK_URL:
        logger.info("Slack уведомления отключены или не настроены")
        return False
    
    try:
        # Получение данных алерта
        alerts = alert_data.get('alerts', [])
        if not alerts:
            logger.warning("Нет алертов для отправки в Slack")
            return False
        
        # Подготовка блоков для Slack
        blocks = [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"ERNI-KI Monitoring Alert: {len(alerts)} алертов",
                    "emoji": True
                }
            },
            {
                "type": "divider"
            }
        ]
        
        for alert in alerts:
            status = alert.get('status', 'firing')
            labels = alert.get('labels', {})
            annotations = alert.get('annotations', {})
            
            severity = labels.get('severity', 'default')
            category = labels.get('category', 'default')
            service = labels.get('service', 'unknown')
            
            # Определение иконки
            icon = ICONS.get(category, ICONS['default'])
            status_icon = "✅" if status == "resolved" else "🔥"
            
            # Добавление секции для алерта
            blocks.append({
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*{icon} {annotations.get('summary', 'Алерт без заголовка')}*\n{annotations.get('description', 'Нет описания')}"
                }
            })
            
            # Добавление полей
            fields = [
                {
                    "type": "mrkdwn",
                    "text": f"*Сервис:*\n{service}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*Категория:*\n{category}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*Важность:*\n{severity}"
                },
                {
                    "type": "mrkdwn",
                    "text": f"*Статус:*\n{status_icon} {status}"
                }
            ]
            
            if 'instance' in labels:
                fields.append({
                    "type": "mrkdwn",
                    "text": f"*Инстанс:*\n{labels['instance']}"
                })
                
            if 'job' in labels:
                fields.append({
                    "type": "mrkdwn",
                    "text": f"*Job:*\n{labels['job']}"
                })
            
            blocks.append({
                "type": "section",
                "fields": fields
            })
            
            blocks.append({
                "type": "divider"
            })
        
        # Подготовка данных для отправки
        payload = {
            "blocks": blocks
        }
        
        # Отправка запроса
        response = requests.post(
            SLACK_WEBHOOK_URL,
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code == 200:
            logger.info(f"Slack уведомление успешно отправлено: {len(alerts)} алертов")
            return True
        else:
            logger.error(f"Ошибка отправки Slack уведомления: {response.status_code} {response.text}")
            return False
            
    except Exception as e:
        logger.error(f"Ошибка при отправке Slack уведомления: {e}")
        return False

# Маршрут для проверки работоспособности
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "ok",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0"
    })

# Маршрут для приема алертов от Alertmanager
@app.route('/webhook', methods=['POST'])
def webhook():
    # Проверка аутентификации
    auth_header = request.headers.get('Authorization')
    if not verify_auth(auth_header):
        logger.warning("Неавторизованный запрос к webhook")
        abort(401)
    
    # Получение данных
    try:
        alert_data = request.json
        logger.info(f"Получен webhook: {json.dumps(alert_data)[:200]}...")
        
        # Отправка уведомлений в различные каналы
        discord_result = send_discord_notification(alert_data)
        telegram_result = send_telegram_notification(alert_data)
        email_result = send_email_notification(alert_data)
        slack_result = send_slack_notification(alert_data)
        
        return jsonify({
            "status": "success",
            "timestamp": datetime.utcnow().isoformat(),
            "notifications": {
                "discord": discord_result,
                "telegram": telegram_result,
                "email": email_result,
                "slack": slack_result
            }
        })
        
    except Exception as e:
        logger.error(f"Ошибка обработки webhook: {e}")
        return jsonify({
            "status": "error",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }), 500

# Маршрут для приема критических логов от Fluent Bit
@app.route('/webhook/critical-logs', methods=['POST'])
def critical_logs_webhook():
    # Проверка аутентификации
    auth_header = request.headers.get('Authorization')
    if not verify_auth(auth_header):
        logger.warning("Неавторизованный запрос к webhook критических логов")
        abort(401)
    
    # Получение данных
    try:
        log_data = request.json
        logger.info(f"Получен webhook критических логов: {json.dumps(log_data)[:200]}...")
        
        # Преобразование формата логов в формат алертов для переиспользования функций
        alert_data = {
            "alerts": [
                {
                    "status": "firing",
                    "labels": {
                        "severity": "critical",
                        "category": log_data.get("service_category", "unknown"),
                        "service": log_data.get("service", "unknown"),
                        "instance": log_data.get("container_short_id", "unknown")
                    },
                    "annotations": {
                        "summary": f"Критическая ошибка в логах {log_data.get('service', 'unknown')}",
                        "description": log_data.get("log", log_data.get("message", "Неизвестная ошибка"))
                    }
                }
            ]
        }
        
        # Отправка уведомлений в различные каналы
        discord_result = send_discord_notification(alert_data)
        telegram_result = send_telegram_notification(alert_data)
        email_result = send_email_notification(alert_data)
        slack_result = send_slack_notification(alert_data)
        
        return jsonify({
            "status": "success",
            "timestamp": datetime.utcnow().isoformat(),
            "notifications": {
                "discord": discord_result,
                "telegram": telegram_result,
                "email": email_result,
                "slack": slack_result
            }
        })
        
    except Exception as e:
        logger.error(f"Ошибка обработки webhook критических логов: {e}")
        return jsonify({
            "status": "error",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }), 500

# Запуск приложения
if __name__ == '__main__':
    logger.info("Запуск webhook-сервера для ERNI-KI")
    app.run(host='0.0.0.0', port=9093)
