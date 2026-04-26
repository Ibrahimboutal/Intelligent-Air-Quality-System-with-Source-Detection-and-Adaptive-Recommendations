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
fprintf('Waiting for connection from Raspberry Pi...\n');

% Initialize Dashboard Figure
fig = figure('Name', 'ZERO-LATENCY Adaptive Intelligence Dashboard', ...
             'Color', 'w', 'Position', [50, 50, 1100, 800]);

% Status Annotation Panel
annotationPanel = annotation('textbox', [0.1, 0.92, 0.8, 0.08], ...
    'String', 'Initializing Telemetry...', 'FitBoxToText', 'on', ...
    'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 12, 'FontWeight', 'bold');

% Create TCP Server (with backward compatibility)
useLegacy = isempty(which('tcpserver'));
if ~useLegacy
    server = tcpserver("0.0.0.0", port, "Timeout", 1);
else
    % Legacy fallback for older MATLAB versions in CI
    server = tcpip('0.0.0.0', port, 'NetworkRole', 'server', 'Timeout', 1);
    set(server, 'InputBufferSize', 10000);
    fopen(server);
end

% Initialize Data Science state
aqSystem = AirQualitySystem(piIP, getenv('PI_USER'), getenv('PI_PASS'), getenv('SERIAL_PORT'), str2double(getenv('BAUD_RATE')), true);
aqSystem.setupDashboard();
delete(aqSystem.FigureHandle); % Close the internal dashboard

% Buffers for visualization
timeWindow = 300; % Show last 300 samples
pm25_buffer = NaN(1, timeWindow);
pm10_buffer = NaN(1, timeWindow);
source_buffer = strings(1, timeWindow);
count = 0;

% --- 1. PRE-ALLOCATE SESSION LOGS (RAM ONLY) ---
maxExpectedSamples = 100000; % Adjust based on expected session length
session_PM25 = NaN(maxExpectedSamples, 1);
session_PM10 = NaN(maxExpectedSamples, 1);
session_Source = strings(maxExpectedSamples, 1);
session_Novelty = NaN(maxExpectedSamples, 1);
session_Timestamps = strings(maxExpectedSamples, 1);

% --- PRE-ALLOCATE GRAPHICS FOR MAXIMUM PERFORMANCE ---
subplot(2,1,1);
hLine25 = plot(NaN(1, timeWindow), 'b', 'LineWidth', 1.5); hold on;
hLine10 = plot(NaN(1, timeWindow), 'Color', [0 0.5 0], 'LineWidth', 1.5); % Dark Green for PM10
hForecast = plot(timeWindow + 1, NaN, 'ro', 'MarkerFaceColor', 'r');
title('Zero-Latency Telemetry with Dampened Forecast');
ylabel('\mu g / m^3'); grid on;
legend([hLine25, hLine10, hForecast], {'PM2.5', 'PM10', 'PM2.5 Forecast'}, 'Location', 'northwest');
hold off;

subplot(2,1,2);
% Pre-allocate a standard scatter plot to avoid gscatter recreation overhead
hScatter = scatter(1:timeWindow, NaN(1, timeWindow), 36, [0 0 1], 'filled');
title('Real-Time Dynamic Source Classification (PM2.5 Tracker)');
ylabel('\mu g / m^3'); xlabel('Samples (Sliding Window)');
grid on;

% Main loop
while ishghandle(fig)
    % Check for new data
    numBytes = 0;
    connected = false;
    if ~useLegacy
        numBytes = server.NumBytesAvailable;
        connected = server.Connected;
    else
        numBytes = server.BytesAvailable;
        connected = strcmp(server.Status, 'open');
    end

    if connected && numBytes > 0
        % Security Check: Restrict to expected subnet / Pi IP
        clientAddress = '';
        if ~useLegacy
            clientAddress = server.ClientAddress;
        else
            % For legacy tcpip, we skip address validation in this simplified fallback
            clientAddress = '127.0.0.1'; 
        end

        if ~isempty(piIP) && ~strcmp(clientAddress, piIP) && ~strcmp(clientAddress, '127.0.0.1')
            fprintf('SECURITY WARNING: Unauthorized connection attempt from %s. Ignoring.\n', clientAddress);
            if ~useLegacy
                read(server, server.NumBytesAvailable, "uint8"); 
            else
                fread(server, server.BytesAvailable);
            end
            pause(0.1);
            continue;
        end
        
        try
            % Receive JSON packet
            if ~useLegacy
                raw_data = readline(server);
            else
                raw_data = fgetl(server);
            end
            payload = jsondecode(raw_data);
            
            count = count + 1;
            pm25 = payload.pm25;
            pm10 = payload.pm10;
            timestamp = payload.timestamp;
            
            % Push to Intelligence Engine
            aqSystem.PM25Data(count) = pm25;
            aqSystem.PM10Data(count) = pm10;
            aqSystem.TimeArray(count) = count;
            
            % Process through Kalman and ML layers
            [sourceStr, advice, noveltyScore, forecastVal] = aqSystem.processNewSample(pm25, pm10);
            
            % Store in RAM Buffer
            session_PM25(count) = pm25;
            session_PM10(count) = pm10;
            session_Source(count) = sourceStr;
            session_Novelty(count) = noveltyScore;
            session_Timestamps(count) = timestamp;
            
            % Update Sliding Buffers
            pm25_buffer = [pm25_buffer(2:end), pm25];
            pm10_buffer = [pm10_buffer(2:end), pm10];
            source_buffer = [source_buffer(2:end), sourceStr];
            
            % --- ZERO-LATENCY RENDERING ---
            set(hLine25, 'YData', pm25_buffer);
            set(hLine10, 'YData', pm10_buffer);
            set(hForecast, 'XData', timeWindow + 1, 'YData', forecastVal);
            set(hScatter, 'YData', pm25_buffer);
            
            % Map sources to colors for the scatter
            colors = zeros(timeWindow, 3);
            for k = 1:timeWindow
                switch source_buffer(k)
                    case "Traffic",    colors(k,:) = [1 0 0]; % Red
                    case "Dust",       colors(k,:) = [0.8 0.5 0.2]; % Brown
                    case "Combustion", colors(k,:) = [0.2 0.2 0.2]; % Gray
                    otherwise,         colors(k,:) = [0 0.8 0]; % Green (Clean)
                end
            end
            set(hScatter, 'CData', colors);
            
            % Update Status UI
            statusStr = sprintf('Time: %s | PM2.5: %.1f | PM10: %.1f | Source: %s | Novelty: %.2f', ...
                timestamp, pm25, pm10, sourceStr, noveltyScore);
            set(annotationPanel, 'String', statusStr);
            if noveltyScore > 0.5, set(annotationPanel, 'BackgroundColor', [1 0.8 0.8]);
            else, set(annotationPanel, 'BackgroundColor', [0.95 0.95 0.95]); end
            
            drawnow limitrate;
            
        catch ME
            fprintf('Processing error: %s\n', ME.message);
        end
    end
    pause(0.01);
end

% --- 2. FLUSH RAM LOGS TO DISK ON EXIT ---
fprintf('\nDashboard closed. Flushing session logs to disk...\n');
validIdx = ~isnan(session_PM25(1:count));
if any(validIdx)
    finalTable = table(session_Timestamps(validIdx), session_PM25(validIdx), ...
                       session_PM10(validIdx), session_Source(validIdx), ...
                       session_Novelty(validIdx), ...
                       'VariableNames', {'Timestamp', 'PM25', 'PM10', 'Source', 'NoveltyScore'});
    logName = sprintf('../logs/Socket_Session_%s.csv', datestr(now, 'yyyymmdd_HHMMSS'));
    writetable(finalTable, logName);
    fprintf('Session log saved: %s\n', logName);
end

if exist('server', 'var')
    if ~useLegacy
        delete(server);
    else
        fclose(server);
        delete(server);
    end
end