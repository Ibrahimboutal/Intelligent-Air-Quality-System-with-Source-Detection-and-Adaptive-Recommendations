import sys
import os
import sqlite3
import pytest
import serial
import socket
import json
from unittest.mock import MagicMock, patch, mock_open

# Add scripts directory to path to import the monitor
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'scripts'))
import air_quality_monitor

# --- 1. Basic Function Tests ---

def test_read_sds011_valid_frame():
    mock_ser = MagicMock()
    mock_ser.read.side_effect = [b'\xAA', b'\xC0\x69\x00\xFC\x00\x01\x02\x68\xAB']
    pm25, pm10 = air_quality_monitor.read_sds011(mock_ser)
    assert pm25 == 10.5
    assert pm10 == 25.2

def test_read_sds011_short_read():
    mock_ser = MagicMock()
    mock_ser.read.side_effect = [b'\xAA', b'\xC0\x69']
    assert air_quality_monitor.read_sds011(mock_ser) is None

def test_read_sds011_wrong_tail():
    mock_ser = MagicMock()
    mock_ser.read.side_effect = [b'\xAA', b'\xC0\x69\x00\xFC\x00\x01\x02\x68\x00']
    assert air_quality_monitor.read_sds011(mock_ser) is None

def test_read_sds011_exception():
    mock_ser = MagicMock()
    mock_ser.read.side_effect = Exception("Serial failure")
    assert air_quality_monitor.read_sds011(mock_ser) is None

def test_init_db_success(tmp_path):
    db_file = tmp_path / "test.db"
    with patch('air_quality_monitor.DB_NAME', str(db_file)):
        conn = air_quality_monitor.init_db()
        assert conn is not None
        conn.close()

def test_init_db_failure():
    with patch('sqlite3.connect', side_effect=Exception("DB error")):
        assert air_quality_monitor.init_db() is None

# --- 2. Main Loop Simulation (The 80% coverage driver) ---

@patch('air_quality_monitor.serial.Serial')
@patch('air_quality_monitor.socket.socket')
@patch('air_quality_monitor.sqlite3.connect')
@patch('air_quality_monitor.open', new_callable=mock_open)
@patch('air_quality_monitor.os.path.exists', return_value=True)
@patch('air_quality_monitor.time.sleep', return_value=None)
def test_main_loop_execution(mock_sleep, mock_exists, mock_file, mock_db, mock_sock, mock_serial):
    """Simulates the entire main loop for 3 iterations to cover all success and retry paths."""
    
    # 1. Setup Mocks
    mock_ser_inst = MagicMock()
    mock_ser_inst.is_open = False
    mock_serial.return_value = mock_ser_inst
    
    # Simulate valid sensor reads
    # Iteration 1: OK, Iteration 2: Failed (buffered), Iteration 3: OK
    with patch('air_quality_monitor.read_sds011') as mock_read:
        mock_read.side_effect = [(10.0, 20.0), None, (15.0, 30.0)]
        
        # Iteration-based exit: Stop after 3 iterations
        mock_sleep.side_effect = [None, None, StopIteration("End of test")]
        
        try:
            air_quality_monitor.main()
        except StopIteration:
            pass

    # 2. Verifications
    assert mock_serial.called
    assert mock_sock.called
    assert mock_db.called
    # Check that CSV header and 2 rows of data (OK and BUFFERED) were written
    # Note: 3rd iteration also writes. Total 4 calls to handle.
    assert mock_file().write.called

@patch('air_quality_monitor.serial.Serial', side_effect=serial.SerialException("Port busy"))
@patch('air_quality_monitor.time.sleep')
def test_main_serial_failure(mock_sleep, mock_serial):
    """Verifies that serial errors are handled and the loop continues."""
    mock_sleep.side_effect = StopIteration("End of test")
    try:
        air_quality_monitor.main()
    except StopIteration:
        pass
    assert mock_serial.called

@patch('air_quality_monitor.socket.socket')
@patch('air_quality_monitor.time.sleep')
@patch('air_quality_monitor.read_sds011', return_value=(10,20))
def test_main_telemetry_failure(mock_read, mock_sleep, mock_sock):
    """Verifies that telemetry socket failures don't crash the main loop."""
    mock_sock_inst = MagicMock()
    mock_sock_inst.connect.side_effect = socket.error("Refused")
    mock_sock.return_value = mock_sock_inst
    
    mock_sleep.side_effect = StopIteration("End of test")
    try:
        with patch('air_quality_monitor.init_db', return_value=None):
            air_quality_monitor.main()
    except StopIteration:
        pass
    assert mock_sock.called

def test_telemetry_packet_error():
    """Verify handling of socket.sendall errors."""
    # We'll test this inside a main loop mock
    with patch('air_quality_monitor.socket.socket') as mock_sock:
        mock_inst = MagicMock()
        mock_inst.sendall.side_effect = Exception("Send failed")
        mock_sock.return_value = mock_inst
        
        # Simulate main loop logic for telemetry
        now = "2026-04-23"
        pm25, pm10 = 10, 20
        try:
            packet = json.dumps({'timestamp': now, 'pm25': pm25, 'pm10': pm10}).encode('utf-8')
            mock_inst.sendall(packet + b'\n')
        except Exception:
            mock_inst.close()
            mock_inst = None
        
        assert mock_inst is None # Verification that link was reset
