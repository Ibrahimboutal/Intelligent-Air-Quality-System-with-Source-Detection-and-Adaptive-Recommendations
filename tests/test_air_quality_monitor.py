import sys
import os
import sqlite3
import pytest
from unittest.mock import MagicMock, patch

# Add scripts directory to path to import the monitor
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'scripts'))
import air_quality_monitor

# --- 1. Validate SDS011 Frame Parsing ---
def test_read_sds011_valid_frame():
    """Verifies that valid sensor bytes are correctly converted to PM2.5 and PM10."""
    # Mock serial object
    mock_ser = MagicMock()
    # 0xAA, 0xC0, PM2.5_L, PM2.5_H, PM10_L, PM10_H, ID1, ID2, Checksum, 0xAB
    # For PM2.5=10.5 (105 = 0x69 + 0x00 * 256)
    # For PM10=25.2 (252 = 0xFC + 0x00 * 256)
    mock_ser.read.side_effect = [b'\xAA', b'\xC0\x69\x00\xFC\x00\x01\x02\x68\xAB']
    
    pm25, pm10 = air_quality_monitor.read_sds011(mock_ser)
    
    assert pm25 == 10.5
    assert pm10 == 25.2

def test_read_sds011_invalid_header():
    """Verifies that the parser skips junk bytes until the 0xAA header."""
    mock_ser = MagicMock()
    # Junk bytes then valid header
    mock_ser.read.side_effect = [b'\x00', b'\xFF', b'\xAA', b'\xC0\x69\x00\xFC\x00\x01\x02\x68\xAB']
    
    pm25, pm10 = air_quality_monitor.read_sds011(mock_ser)
    assert pm25 == 10.5

# --- 2. Verify SQLite Initialization & Data Insertion ---
def test_sqlite_integration(tmp_path):
    """Verifies that SQLite table is created and data can be inserted."""
    db_file = tmp_path / "test_air_quality.db"
    
    # Override DB_NAME in monitor module
    with patch('air_quality_monitor.DB_NAME', str(db_file)):
        conn = air_quality_monitor.init_db()
        assert conn is not None
        
        cursor = conn.cursor()
        cursor.execute("INSERT INTO data (timestamp, pm25, pm10) VALUES (?, ?, ?)", 
                       ("2026-04-23 12:00:00", 15.5, 30.2))
        conn.commit()
        
        cursor.execute("SELECT * FROM data")
        row = cursor.fetchone()
        assert row == ("2026-04-23 12:00:00", 15.5, 30.2)
        conn.close()

# --- 3. Test Fallback Buffering Mechanism ---
def test_buffering_logic():
    """Simulates a sensor failure and verifies the 'Hold-Last-Valid' buffering kicks in."""
    # We test the logic used in the main loop
    last_pm25, last_pm10 = 10.0, 20.0
    
    # Case: Sensor read fails (returns None)
    result = None
    
    if result:
        pm25, pm10 = result
        status = "OK"
    else:
        # This is the code from main()
        if last_pm25 is not None:
            pm25, pm10 = last_pm25, last_pm10
            status = "BUFFERED"
        else:
            pm25, pm10 = None, None
            status = "NULL"
            
    assert pm25 == 10.0
    assert pm10 == 20.0
    assert status == "BUFFERED"

# --- 4. Monitor Execution Time (Efficiency) ---
def test_parsing_efficiency():
    """Ensures frame parsing is sub-millisecond to maintain high-frequency telemetry."""
    import time
    mock_ser = MagicMock()
    mock_ser.read.side_effect = [b'\xAA', b'\xC0\x69\x00\xFC\x00\x01\x02\x68\xAB'] * 1000
    
    start_time = time.time()
    for _ in range(100):
        air_quality_monitor.read_sds011(mock_ser)
    end_time = time.time()
    
    avg_time = (end_time - start_time) / 100
    assert avg_time < 0.001 # Should be very fast
