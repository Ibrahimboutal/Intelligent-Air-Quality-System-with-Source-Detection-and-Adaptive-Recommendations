%% High-Performance Socket Intelligence Dashboard
% This script implements a TCP Server to receive real-time telemetry
% from the Raspberry Pi. It eliminates the 5-second polling delay
% and disk I/O overhead of the previous CSV-based integration.

clear; clc; close all;

% Configuration
port = 5005;

fprintf('Starting TCP Telemetry Server on port %d...\n', port);
fprintf('Waiting for connection from Raspberry Pi...\n');

% Initialize Dashboard Figure
fig = figure('Name', 'ZERO-LATENCY Adaptive Intelligence Dashboard', ...
             'Color', 'w', 'Position', [50, 50, 1100, 800]);

% Status Annotation Panel
annotationPanel = annotation('textbox', [0.1, 0.85, 0.8, 0.1], ...
    'String', 'Initializing Telemetry...', 'FitBoxToText', 'on', ...
    'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 12, 'FontWeight', 'bold');

% Create TCP Server (Enhancement: Add Timeout to prevent readline deadlock)
server = tcpserver("0.0.0.0", port, "Timeout", 1);

% Initialize Data Science state (AirQualitySystem object)
% Note: We use the AirQualitySystem class to reuse the intelligence logic
aqSystem = AirQualitySystem('127.0.0.1', 'pi', 'pass', '/dev/ttyUSB0', 9600, true);
aqSystem.setupDashboard();
delete(aqSystem.FigureHandle); % Close the internal dashboard, we'll use this script's plots

% Buffers for visualization
timeWindow = 300; % Show last 300 samples
pm25_buffer = NaN(1, timeWindow);
pm10_buffer = NaN(1, timeWindow);
source_buffer = strings(1, timeWindow);
count = 0;

% Main loop
while ishghandle(fig)
    % Check for new data
    if server.Connected && server.NumBytesAvailable > 0
        try
            % 1. Receive JSON packet
            raw_data = readline(server);
            payload = jsondecode(raw_data);
            
            count = count + 1;
            pm25 = payload.pm25;
            pm10 = payload.pm10;
            timestamp = payload.timestamp;
            
            % 2. Push to Intelligence Engine
            % We simulate the real-time update in aqSystem buffers
            aqSystem.PM25Data(count) = pm25;
            aqSystem.PM10Data(count) = pm10;
            aqSystem.TimeArray(count) = count;
            
            % Extract Features & Analyze
            features = aqSystem.extractFeatures(count);
            predictedPM25 = aqSystem.forecastAQI(count);
            [source, advice] = aqSystem.analyze(count, features, predictedPM25);
            
            % 3. Update Visual Buffers
            pm25_buffer = [pm25_buffer(2:end), pm25];
            pm10_buffer = [pm10_buffer(2:end), pm10];
            source_buffer = [source_buffer(2:end), string(source)];
            
            % --- 4. UPDATE DASHBOARD ---
            
            % Set color based on status
            if contains(advice, 'DANGER')
                panelColor = [1 0.7 0.7];
            elseif contains(advice, 'PRE-EMPTIVE')
                panelColor = [1 0.9 0.6];
            else
                panelColor = [0.8 1 0.8];
            end
            
            statusStr = sprintf('TELEMETRY ACTIVE | %s\nPM2.5: %.1f | Source: %s\nRecommendation: %s', ...
                timestamp, pm25, source, advice);
            set(annotationPanel, 'String', statusStr, 'BackgroundColor', panelColor);
            
            % Plotting
            subplot(2,1,1);
            plot(pm25_buffer, 'b', 'LineWidth', 1.5); hold on;
            plot(timeWindow + 1, predictedPM25, 'ro', 'MarkerFaceColor', 'r');
            title('Zero-Latency PM2.5 Telemetry with Dampened Forecast');
            ylabel('\mu g / m^3'); grid on; hold off;
            
            subplot(2,1,2);
            % Use categorical for gscatter
            cats = categorical(source_buffer);
            gscatter(1:timeWindow, pm25_buffer, cats, 'brgm', 'o+x*');
            title('Real-Time Dynamic Source Classification');
            ylabel('\mu g / m^3'); xlabel('Samples (Sliding Window)');
            grid on;
            
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
