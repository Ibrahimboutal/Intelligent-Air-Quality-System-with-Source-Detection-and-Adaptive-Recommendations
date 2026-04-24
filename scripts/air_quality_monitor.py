import serial
import time
import datetime
import os
import csv
import logging
import sqlite3
import socket
import json

# --- Configuration ---
SERIAL_PORT = os.getenv('SERIAL_PORT', '/dev/ttyUSB0')
BAUD_RATE = int(os.getenv('BAUD_RATE', 9600))
LOG_DIR = 'logs'
ERROR_LOG = 'error.log'
DATA_FILE_PREFIX = 'AQI_Log'
DB_NAME = 'air_quality.db'
BATCH_SIZE = 60  # Commit to DB every 60 seconds to protect SD card

# TCP Telemetry Configuration (Fix: Load from Environment)
MATLAB_IP = os.getenv('MATLAB_IP', '127.0.0.1')
MATLAB_PORT = int(os.getenv('MATLAB_PORT', 5005))
USE_SSL = os.getenv('USE_SSL', 'false').lower() == 'true'
SSL_CERT_PATH = os.getenv('SSL_CERT_PATH', '')

# Setup error logging
logging.basicConfig(
    filename=ERROR_LOG,
    level=logging.ERROR,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def init_db():
    """Initializes the SQLite database and creates the table if it doesn't exist."""
    try:
        conn = sqlite3.connect(DB_NAME)
        cursor = conn.cursor()
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS data (
            timestamp TEXT,
            pm25 REAL,
            pm10 REAL
        )
        ''')
        conn.commit()
        return conn
    except Exception as e:
        logging.error(f"Failed to initialize database: {e}")
        return None

def read_sds011(ser):
    """
    Reads a single frame from the SDS011 sensor.
    Frame format: 0xAA, 0xC0, PM2.5_Low, PM2.5_High, PM10_Low, PM10_High, ID1, ID2, Checksum, 0xAB
    """
    try:
        # Wait for header 0xAA with safety limit
        max_bytes_to_read = 100
        bytes_read = 0
        while bytes_read < max_bytes_to_read:
            b = ser.read(1)
            if not b:
                return None
            if ord(b) == 0xAA:
                break
            bytes_read += 1
        else:
            return None # Failed to find header within limits
        
        # Read the rest of the 10-byte frame
        data = ser.read(9)
        if len(data) < 9:
            return None
            
        # Verify tail
        if data[8] != 0xAB:
            return None
            
        # Parse PM values
        pm25 = ((data[2] * 256) + data[1]) / 10.0
        pm10 = ((data[4] * 256) + data[3]) / 10.0
        
        return pm25, pm10
        
    except Exception as e:
        logging.error(f"Error reading from sensor: {e}")
        return None

def main():
    print("Starting Intelligent Air Quality Monitor (Telemetry Mode)...")
    
    # Ensure log directory exists
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
        
    # Initialize Database
    db_conn = init_db()
    if db_conn:
        print(f"SQLite Database {DB_NAME} initialized.")
    
    # Create a new log file for this session (CSV)
    timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    log_file = os.path.join(LOG_DIR, f"{DATA_FILE_PREFIX}_{timestamp}.csv")
    
    print(f"Logging data locally to {log_file}")
    
    # Initialize CSV
    with open(log_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Timestamp', 'PM25', 'PM10'])

    ser = None
    sock = None
    
    # Data Buffering
    last_pm25 = None
    last_pm10 = None
    db_buffer = [] # In-memory queue for batch inserts
    
    while True:
        try:
            # 1. Hardware Connection
            if ser is None or not ser.is_open:
                print(f"Connecting to SDS011 on {SERIAL_PORT}...")
                ser = serial.Serial(SERIAL_PORT, baudrate=BAUD_RATE, timeout=2)
            
            # 2. Telemetry Connection (Fix: Socket client for real-time push)
            if sock is None:
                try:
                    print(f"Attempting Telemetry link to MATLAB at {MATLAB_IP}:{MATLAB_PORT} (SSL: {USE_SSL})...")
                    base_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    base_sock.settimeout(2)
                    
                    if USE_SSL:
                        import ssl
                        context = ssl.create_default_context()
                        if SSL_CERT_PATH:
                            context.load_verify_locations(SSL_CERT_PATH)
                        sock = context.wrap_socket(base_sock, server_hostname=MATLAB_IP)
                    else:
                        sock = base_sock
                        
                    sock.connect((MATLAB_IP, MATLAB_PORT))
                    print("Telemetry link established.")
                except Exception as e:
                    logging.error(f"Telemetry link failed: {e}")
                    sock = None # Retry in next loop
            
            # 3. Data Acquisition
            result = read_sds011(ser)
            now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            if result:
                pm25, pm10 = result
                last_pm25, last_pm10 = pm25, pm10
                status = "OK"
            else:
                if last_pm25 is not None:
                    pm25, pm10 = last_pm25, last_pm10
                    status = "BUFFERED"
                else:
                    pm25, pm10 = None, None
                    status = "NULL"

            if pm25 is not None:
                print(f"[{now}] PM2.5: {pm25} | PM10: {pm10} | Status: {status}")
                
                # --- Persistent Local Logging ---
                with open(log_file, 'a', newline='') as f:
                    writer = csv.writer(f)
                    writer.writerow([now, pm25, pm10])
                
                if db_conn:
                    try:
                        db_buffer.append((now, pm25, pm10))
                        
                        # Batch Commit (O(1) amortized I/O)
                        if len(db_buffer) >= BATCH_SIZE:
                            cursor = db_conn.cursor()
                            cursor.executemany('INSERT INTO data (timestamp, pm25, pm10) VALUES (?, ?, ?)', db_buffer)
                            db_conn.commit()
                            db_buffer = [] # Clear buffer
                            print(f"[{now}] Batch committed to SQLite (%d records)." % BATCH_SIZE)
                    except Exception as e:
                        logging.error(f"Database batch error: {e}")
                
                # --- Real-Time Telemetry Push ---
                if sock:
                    try:
                        packet = json.dumps({'timestamp': now, 'pm25': pm25, 'pm10': pm10}).encode('utf-8')
                        sock.sendall(packet + b'\n')
                    except Exception as e:
                        print(f"Telemetry link lost: {e}")
                        sock.close()
                        sock = None
            
            time.sleep(1) # Sample every second
            
        except serial.SerialException as e:
            logging.error(f"Serial connection error: {e}")
            if ser: ser.close()
            ser = None
            time.sleep(5)
            
        except Exception as e:
            logging.error(f"Unexpected error: {e}")
            time.sleep(1)

if __name__ == "__main__":
    main()
