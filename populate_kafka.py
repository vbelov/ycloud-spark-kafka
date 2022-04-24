import os
import json
import time
import logging
from confluent_kafka import Producer


logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s :: %(levelname)s :: %(message)s')


def delivery_callback(err, msg):
    """Log errors"""
    if not err:
        return
    logging.error(f'Message failed delivery: {err}')


def main():
    producer = Producer({
        'bootstrap.servers': os.environ['BOOTSTRAP_SERVERS'],
        'security.protocol': 'SASL_SSL',
        'sasl.mechanism': 'SCRAM-SHA-512',
        'sasl.password': os.environ['ADMIN_PASSWORD'],
        'sasl.username': 'admin',
        'ssl.ca.location': 'CA.pem',
    })

    count = 0
    last_log_time = time.time()
    event = {}
    while True:
        try:
            for _ in range(10):
                event['serial'] = count
                value = json.dumps(event).encode('utf-8')
                producer.produce('topic1', value, on_delivery=delivery_callback)
                count = count + 1
            producer.flush()
            time.sleep(1.0)
        except Exception as exc:
            logging.warning('Failed to produce events', exc)
        if int(time.time() - last_log_time) > 1:
            last_log_time = time.time()
            logging.info(f'Produced {count} events')


if __name__ == '__main__':
    main()
