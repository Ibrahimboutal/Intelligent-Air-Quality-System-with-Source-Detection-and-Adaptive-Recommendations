% -------------------------------------------------------------------------
% Main execution script for the Intelligent Air Quality System
% 
% This script demonstrates how to initialize and run the system.
% To test without hardware, set 'simulationMode = true'.
% -------------------------------------------------------------------------

clc; clear; close all;
addpath('src'); % Add the source directory to the MATLAB path

%% 1. Configuration
% Set this to false when you have your Raspberry Pi and SDS011 connected
simulationMode = true; 
useKalman = true; % Enable Bayesian Signal Denoising (Phase 1)

% Load credentials from .env file securely
loadEnv('.env');

if simulationMode
    disp('Simulation Mode ON: Bypassing hardware credential checks.');
    pi_ip = '127.0.0.1';
    pi_user = 'mock_user';
    pi_pass = 'mock_pass';
    serial_port = 'COM1';
    baud_rate = 9600;
else
    pi_ip = getenv('PI_IP');
    assert(~isempty(pi_ip), 'PI_IP must be set in .env');
    
    pi_user = getenv('PI_USER');
    assert(~isempty(pi_user), 'PI_USER must be set in .env');
    
    pi_pass = getenv('PI_PASS');
    assert(~isempty(pi_pass), 'PI_PASS must be set in .env');
    
    serial_port = getenv('SERIAL_PORT');
    assert(~isempty(serial_port), 'SERIAL_PORT must be set in .env');
    
    baud_str = getenv('BAUD_RATE');
    assert(~isempty(baud_str), 'BAUD_RATE must be set in .env');
    baud_rate = str2double(baud_str);
end

%% 2. Initialize System
disp('Initializing Intelligent Air Quality System...');
aqSystem = AirQualitySystem(pi_ip, pi_user, pi_pass, serial_port, baud_rate, simulationMode, useKalman);

% Safety: Guarantee hardware release on interrupt (Ctrl+C)
cleanupHardware = onCleanup(@() delete(aqSystem));

% Connect to the hardware (or setup simulation)
aqSystem.connect();

%% 3. Start Monitoring
num_samples = 1500; % Number of seconds to run
aqSystem.run(num_samples);

%% 4. Advanced Robust Analysis (FSDA)
% Performs post-processing on the collected data to find hidden anomalies.
aqSystem.runFSDAAnalysis();

disp('Script finished.');
