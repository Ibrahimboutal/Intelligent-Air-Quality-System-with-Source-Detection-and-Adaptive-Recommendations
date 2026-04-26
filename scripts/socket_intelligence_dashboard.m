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

% Create TCP Server 
server = tcpserver("0.0.0.0", port, "Timeout", 1);

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
log_timestamps = strings(maxExpectedSamples, 1);
log_pm25 = NaN(maxExpectedSamples, 1);
log_pm10 = NaN(maxExpectedSamples, 1);
log_source = strings(maxExpectedSamples, 1);
log_features = cell(maxExpectedSamples, 1); 

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
    if server.Connected && server.NumBytesAvailable > 0
        % Security Check: Restrict to expected subnet / Pi IP
        if ~isempty(piIP) && ~strcmp(server.ClientAddress, piIP) && ~strcmp(server.ClientAddress, '127.0.0.1')
            fprintf('SECURITY WARNING: Unauthorized connection attempt from %s. Ignoring.\n', server.ClientAddress);
            read(server, server.NumBytesAvailable, "uint8"); % Discard unauthorized data
            pause(0.1);
            continue;
        end
        
        try
            % Receive JSON packet
            raw_data = readline(server);
            payload = jsondecode(raw_data);
            
            count = count + 1;
            pm25 = payload.pm25;
            pm10 = payload.pm10;
            timestamp = payload.timestamp;
            
            % Push to Intelligence Engine
            aqSystem.PM25Data(count) = pm25;
            aqSystem.PM10Data(count) = pm10;
            aqSystem.TimeArray(count) = count;
            
            % Extract Features & Analyze
            features = aqSystem.extractFeatures(count);
            predictedPM25 = aqSystem.forecastAQI(count);
            [source, advice] = aqSystem.analyze(count, features, predictedPM25);
            
            % --- 2. LOG DATA TO RAM ---
            log_timestamps(count) = string(timestamp);
            log_pm25(count) = pm25;
            log_pm10(count) = pm10;
            log_source(count) = string(source);
            log_features{count} = features;
            
            % Update Visual Buffers
            pm25_buffer = [pm25_buffer(2:end), pm25];
            pm10_buffer = [pm10_buffer(2:end), pm10];
            source_buffer = [source_buffer(2:end), string(source)];
            
            % --- UPDATE DASHBOARD ---
            % Set color based on status
            if contains(advice, 'DANGER')
                panelColor = [1 0.7 0.7];
            elseif contains(advice, 'PRE-EMPTIVE')
                panelColor = [1 0.9 0.6];
            else
                panelColor = [0.8 1 0.8];
            end
            
            % Added PM10 to the text readout
            statusStr = sprintf('TELEMETRY ACTIVE | %s\nPM2.5: %.1f  |  PM10: %.1f  |  Source: %s\nRecommendation: %s', ...
                timestamp, pm25, pm10, source, advice);
            set(annotationPanel, 'String', statusStr, 'BackgroundColor', panelColor);
            
            % Fast Graphic Updates (Updating YData directly)
            set(hLine25, 'YData', pm25_buffer);
            set(hLine10, 'YData', pm10_buffer);
            set(hForecast, 'YData', predictedPM25);
            set(hScatter, 'YData', pm25_buffer);
            
            drawnow limitrate;
            
        catch ME
            fprintf('Processing error: %s\n', ME.message);
        end
    end
    
    % Small pause to prevent CPU pegging
    pause(0.01);
end

clear server;
fprintf('Server stopped.\n');

% --- 3. BATCH SAVE TO CSV UPON EXIT ---
fprintf('Compiling session data...\n');

if count > 0
    % Trim unused pre-allocated rows to match the actual number of received packets
    validRows = 1:count;
    SessionData = table(log_timestamps(validRows), log_pm25(validRows), ...
                        log_pm10(validRows), log_source(validRows), log_features(validRows), ...
                        'VariableNames', {'Timestamp', 'PM25', 'PM10', 'Source', 'Features_7D'});

    if ~exist('../logs', 'dir'), mkdir('../logs'); end
    filename = sprintf('../logs/telemetry_session_%s.csv', datestr(now, 'yyyymmdd_HHMMSS'));
    writetable(SessionData, filename);
    fprintf('Session successfully saved to %s\n', filename);
else
    fprintf('No data collected during this session.\n');
end