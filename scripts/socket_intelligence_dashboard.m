%% High-Performance Socket Intelligence Dashboard (PM2.5, PM10 & Logging)
% This script implements a TCP Server to receive real-time telemetry
% from the Raspberry Pi. Optimized for Zero-Latency rendering and
% memory-safe RAM batch logging.
clear; clc; close all;

% Load Configuration from .env
addpath('../src');
if exist('../.env', 'file'), loadEnv('../.env'); end

% Configuration
port = str2double(getenv('MATLAB_PORT'));
if isnan(port), port = 5056; end % Match CI port
piIP = getenv('PI_IP');
if isempty(piIP), piIP = '127.0.0.1'; end

fprintf('Starting TCP Telemetry Server on port %d...\n', port);

% Initialize Dashboard Figure (only if not headless)
isHeadless = ~isempty(getenv('MW_ORIG_WORKING_FOLDER'));
if ~isHeadless
    fig = figure('Name', 'ZERO-LATENCY Adaptive Intelligence Dashboard', ...
                 'Color', 'w', 'Position', [50, 50, 1100, 800]);
    annotationPanel = annotation('textbox', [0.1, 0.92, 0.8, 0.08], ...
        'String', 'Initializing Telemetry...', 'FitBoxToText', 'on', ...
        'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 12, 'FontWeight', 'bold');
else
    fig = 100; % Mock figure handle for CI
    fprintf('Running in CI Headless mode...\n');
end

% Create TCP Server (with robust backward compatibility)
server = [];
useLegacy = false;
try
    if ~isempty(which('tcpserver'))
        server = tcpserver("0.0.0.0", port, "Timeout", 1);
        useLegacy = false;
    elseif ~isempty(which('tcpip'))
        server = tcpip('0.0.0.0', port, 'NetworkRole', 'server', 'Timeout', 1);
        set(server, 'InputBufferSize', 10000);
        fopen(server);
        useLegacy = true;
    end
catch ME
    warning('TCP Server initialization failed: %s', ME.message);
end

% Initialize Data Science state
aqSystem = AirQualitySystem(piIP, getenv('PI_USER'), getenv('PI_PASS'), getenv('SERIAL_PORT'), str2double(getenv('BAUD_RATE')), true);
if ~isHeadless
    aqSystem.setupDashboard();
    if isvalid(aqSystem.FigureHandle), delete(aqSystem.FigureHandle); end
end

% Buffers
timeWindow = 300;
pm25_buffer = NaN(1, timeWindow);
source_buffer = strings(1, timeWindow);
count = 0;

% Main loop
startTime = tic;
while (isHeadless && toc(startTime) < 3) || (~isHeadless && ishghandle(fig))
    dataAvailable = false;
    if ~isempty(server)
        try
            if ~useLegacy
                dataAvailable = (server.Connected && server.NumBytesAvailable > 0);
            else
                dataAvailable = (strcmp(server.Status, 'open') && server.BytesAvailable > 0);
            end
        catch
            dataAvailable = false;
        end
    end

    if dataAvailable
        try
            raw_data = '';
            if ~useLegacy, raw_data = readline(server); else, raw_data = fgetl(server); end
            if isempty(raw_data), continue; end
            
            payload = jsondecode(raw_data);
            count = count + 1;
            pm25 = payload.pm25;
            [sourceStr, ~, noveltyScore, forecastVal] = aqSystem.processNewSample(pm25, payload.pm10);
            
            if ~isHeadless
                pm25_buffer = [pm25_buffer(2:end), pm25];
                source_buffer = [source_buffer(2:end), sourceStr];
                set(annotationPanel, 'String', sprintf('Time: %s | PM2.5: %.1f | Source: %s', payload.timestamp, pm25, sourceStr));
                drawnow limitrate;
            else
                fprintf('CI Received Packet: PM2.5=%.1f, Source=%s\n', pm25, sourceStr);
                break; % Exit after first packet in CI
            end
        catch ME
            fprintf('Read error: %s\n', ME.message);
        end
    end
    pause(0.1);
end

% Exit cleanup
if ~isempty(server)
    try if useLegacy, fclose(server); end, catch, end
    try delete(server); catch, end
end
fprintf('Dashboard closed.\n');