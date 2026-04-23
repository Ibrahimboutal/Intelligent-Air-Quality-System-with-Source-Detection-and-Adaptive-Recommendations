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

pi_ip = '192.168.43.16';
pi_user = 'admin';
pi_pass = 'thingspeak';
serial_port = '/dev/ttyUSB0';

%% 2. Initialize System
disp('Initializing Intelligent Air Quality System...');
aqSystem = AirQualitySystem(pi_ip, pi_user, pi_pass, serial_port, simulationMode);

% Connect to the hardware (or setup simulation)
aqSystem.connect();

%% 3. Start Monitoring
num_samples = 100; % Number of seconds to run
aqSystem.run(num_samples);

disp('Script finished.');
