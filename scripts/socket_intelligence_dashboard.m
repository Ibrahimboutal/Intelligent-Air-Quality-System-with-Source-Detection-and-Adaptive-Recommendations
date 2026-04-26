%% High-Performance Socket Intelligence Dashboard (PM2.5, PM10 & Logging)
% This script implements a TCP Server to receive real-time telemetry
% from the Raspberry Pi. Optimized for Zero-Latency rendering and
% memory-safe RAM batch logging.
clear; clc; close all;

% Load Configuration from .env
addpath('../src');
loadEnv('../.env');

% Configuration
port = str2double(getenv('MATLAB_PORT'));
if isnan(port), port = 5005; end
piIP = getenv('PI_IP');
if isempty(piIP), piIP = '127.0.0.1'; end

fprintf('Starting TCP Telemetry Server on port %d...\n', port);

% Initialize Dashboard Figure
fig = figure('Name', 'ZERO-LATENCY Adaptive Intelligence Dashboard', ...
             'Color', 'w', 'Position', [50, 50, 1100, 800]);

% Status Annotation Panel
annotationPanel = annotation('textbox', [0.1, 0.92, 0.8, 0.08], ...
    'String', 'Initializing Telemetry...', 'FitBoxToText', 'on', ...
    'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 12, 'FontWeight', 'bold');

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
    else
        warning('Instrument Control Toolbox missing. Socket telemetry disabled.');
    end
catch ME
    warning('TCP Server initialization failed: %s', ME.message);
end

% Initialize Data Science state
aqSystem = AirQualitySystem(piIP, getenv('PI_USER'), getenv('PI_PASS'), getenv('SERIAL_PORT'), str2double(getenv('BAUD_RATE')), true);
aqSystem.setupDashboard();
if isvalid(aqSystem.FigureHandle), delete(aqSystem.FigureHandle); end

% Buffers for visualization
timeWindow = 300;
pm25_buffer = NaN(1, timeWindow);
pm10_buffer = NaN(1, timeWindow);
source_buffer = strings(1, timeWindow);
count = 0;

% RAM Buffers
maxSamples = 5000;
session_PM25 = NaN(maxSamples, 1);
session_PM10 = NaN(maxSamples, 1);
session_Source = strings(maxSamples, 1);
session_Novelty = NaN(maxSamples, 1);
session_Timestamps = strings(maxSamples, 1);

% Pre-allocate Graphics
subplot(2,1,1);
hLine25 = plot(NaN(1, timeWindow), 'b', 'LineWidth', 1.5); hold on;
hLine10 = plot(NaN(1, timeWindow), 'Color', [0 0.5 0], 'LineWidth', 1.5);
hForecast = plot(timeWindow + 1, NaN, 'ro', 'MarkerFaceColor', 'r');
title('Zero-Latency Telemetry with Dampened Forecast');
ylabel('\mu g / m^3'); grid on;
legend([hLine25, hLine10, hForecast], {'PM2.5', 'PM10', 'PM2.5 Forecast'}, 'Location', 'northwest');
hold off;

subplot(2,1,2);
hScatter = scatter(1:timeWindow, NaN(1, timeWindow), 36, [0 0 1], 'filled');
title('Real-Time Dynamic Source Classification (PM2.5 Tracker)');
ylabel('\mu g / m^3'); xlabel('Samples (Sliding Window)');
grid on;

% Main loop
while ishghandle(fig)
    % Check for new data if server exists
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
            % Receive JSON packet
            if ~useLegacy
                raw_data = readline(server);
            else
                raw_data = fgetl(server);
            end
            payload = jsondecode(raw_data);
            
            count = count + 1;
            if count > maxSamples, break; end % Safety exit
            
            pm25 = payload.pm25;
            pm10 = payload.pm10;
            timestamp = payload.timestamp;
            
            % Push to Intelligence Engine
            aqSystem.PM25Data(count) = pm25;
            aqSystem.PM10Data(count) = pm10;
            aqSystem.TimeArray(count) = count;
            
            [sourceStr, ~, noveltyScore, forecastVal] = aqSystem.processNewSample(pm25, pm10);
            
            % Store in RAM
            session_PM25(count) = pm25;
            session_PM10(count) = pm10;
            session_Source(count) = sourceStr;
            session_Novelty(count) = noveltyScore;
            session_Timestamps(count) = timestamp;
            
            % Update Buffers
            pm25_buffer = [pm25_buffer(2:end), pm25];
            pm10_buffer = [pm10_buffer(2:end), pm10];
            source_buffer = [source_buffer(2:end), sourceStr];
            
            % Update Plots
            set(hLine25, 'YData', pm25_buffer);
            set(hLine10, 'YData', pm10_buffer);
            set(hForecast, 'XData', timeWindow + 1, 'YData', forecastVal);
            set(hScatter, 'YData', pm25_buffer);
            
            % Color mapping
            colors = zeros(timeWindow, 3);
            for k = 1:timeWindow
                switch source_buffer(k)
                    case "Traffic",    colors(k,:) = [1 0 0];
                    case "Dust",       colors(k,:) = [0.8 0.5 0.2];
                    case "Combustion", colors(k,:) = [0.2 0.2 0.2];
                    otherwise,         colors(k,:) = [0 0.8 0];
                end
            end
            set(hScatter, 'CData', colors);
            
            % Update UI
            set(annotationPanel, 'String', sprintf('Time: %s | PM2.5: %.1f | Source: %s', timestamp, pm25, sourceStr));
            drawnow limitrate;
            
        catch ME
            fprintf('Read error: %s\n', ME.message);
        end
    end
    pause(0.05);
end

% Exit cleanup
if ~isempty(server) && isvalid(server)
    if useLegacy, fclose(server); end
    delete(server);
end
fprintf('Dashboard closed.\n');