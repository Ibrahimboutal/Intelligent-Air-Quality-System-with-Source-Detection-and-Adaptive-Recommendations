%% Phase 7: Live Intelligence Dashboard
% This script implements Option B for live integration.
% It continuously polls the latest CSV file from the Pi to provide 
% near real-time adaptive intelligence and visualization.

clear; clc; close all;

% Configuration
logDir = '../logs';
pollInterval = 5; % Seconds between updates

fprintf('Starting Live Intelligence Dashboard (Near Real-Time)...\n');
fprintf('Polling directory: %s every %d seconds.\n', logDir, pollInterval);

% Initialize Dashboard Figure
fig = figure('Name', 'LIVE Adaptive Air Quality Intelligence', 'Color', 'w', 'Position', [50, 50, 1100, 800]);

% Setup UI Panels for Status
annotationPanel = annotation('textbox', [0.1, 0.85, 0.8, 0.1], ...
    'String', 'Waiting for data...', 'FitBoxToText', 'on', ...
    'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 12, 'FontWeight', 'bold');

% Keep running until figure is closed
while ishghandle(fig)
    try
        % 1. Find the latest log file
        files = dir(fullfile(logDir, 'AQI_Log_*.csv'));
        if isempty(files)
            set(annotationPanel, 'String', 'Status: NO LOG FILES FOUND. Ensure Pi collector is running.');
            pause(pollInterval);
            continue;
        end
        
        [~, idx] = sort([files.datenum], 'descend');
        latestFile = fullfile(logDir, files(idx(1)).name);
        
        % 2. Read latest data
        data = readtable(latestFile);
        
        if height(data) < 5
            set(annotationPanel, 'String', 'Status: WAITING FOR MORE DATA (at least 5 samples)...');
            pause(pollInterval);
            continue;
        end
        
        % --- 3. FULL INTELLIGENCE PIPELINE ---
        
        % Feature Engineering
        data.pm25_avg = movmean(data.pm25, 5);
        data.pm25_diff = [0; diff(data.pm25)];
        data.ratio = data.pm25 ./ max(data.pm10, 0.1);
        data.spike = abs(data.pm25_diff) > 10;
        
        % Source Detection (Rule-based)
        source = strings(height(data), 1);
        for i = 1:height(data)
            if data.pm25(i) > 50 && data.pm10(i) < 80
                source(i) = "Traffic";
            elseif data.pm10(i) > 80
                source(i) = "Dust";
            elseif data.spike(i)
                source(i) = "Local Event";
            else
                source(i) = "Normal";
            end
        end
        data.source = source;
        
        % Forecasting (Pre-emptive)
        x = data.pm25(1:end-1);
        y = data.pm25(2:end);
        forecastModel = fitlm(x, y);
        latestPM25 = data.pm25(end);
        predPM25 = predict(forecastModel, latestPM25);
        
        % Adaptive Recommendation
        currPM25 = data.pm25(end);
        currTrend = data.pm25_diff(end);
        
        if currPM25 > 50
            recommandation = "DANGER: Wear mask & activate purifier";
            panelColor = [1 0.7 0.7]; % Red
        elseif currTrend > 5 || predPM25 > 35
            recommandation = "PRE-EMPTIVE: Close windows - quality worsening";
            panelColor = [1 0.9 0.6]; % Orange
        elseif data.source(end) == "Dust"
            recommandation = "CAUTION: Outdoor dust detected - avoid exercise";
            panelColor = [1 1 0.7]; % Yellow
        else
            recommandation = "Air is acceptable";
            panelColor = [0.8 1 0.8]; % Green
        end
        
        % --- 4. UPDATE DASHBOARD ---
        
        % Update Annotation Panel
        statusStr = sprintf('LATEST UPDATE: %s\nPM2.5: %.1f | Source: %s\nRecommendation: %s', ...
            datestr(now, 'HH:MM:SS'), currPM25, data.source(end), recommandation);
        set(annotationPanel, 'String', statusStr, 'BackgroundColor', panelColor);
        
        % Plotting
        subplot(2,1,1);
        plot(data.pm25, 'b', 'LineWidth', 1.5); hold on;
        plot(height(data)+1, predPM25, 'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'Forecast');
        title('Live PM2.5 Concentration with Pre-emptive Forecast');
        ylabel('\mu g / m^3'); grid on; hold off;
        
        subplot(2,1,2);
        gscatter(1:height(data), data.pm25, data.source, 'brgm', 'o+x*');
        title('Live Source Detection');
        ylabel('\mu g / m^3'); xlabel('Samples');
        grid on;
        
        drawnow;
        
    catch ME
        fprintf('Error during update: %s. Retrying...\n', ME.message);
    end
    
    pause(pollInterval);
end

fprintf('Dashboard closed.\n');
