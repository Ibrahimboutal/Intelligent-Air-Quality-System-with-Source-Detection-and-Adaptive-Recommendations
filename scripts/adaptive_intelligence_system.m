%% Phases 5 & 6: Adaptive Intelligence & Recommendation System
% This script represents the final "brain" of the Intelligent Air Quality System.
% It integrates real-time monitoring, machine learning classification, 
% predictive forecasting, and adaptive recommendations.

clear; clc; close all;

% --- 1. Data Preparation (Load & Feature Engineering) ---
logDir = '../logs';
files = dir(fullfile(logDir, 'AQI_Log_*.csv'));
if isempty(files), error('No log files found.'); end
[~, idx] = sort([files.datenum], 'descend');
latestFile = fullfile(logDir, files(idx(1)).name);

fprintf('Powering up Adaptive Intelligence System for: %s\n', latestFile);
data = readtable(latestFile);

% Engineering Features
data.pm25_avg = movmean(data.pm25, 5);
data.pm10_avg = movmean(data.pm10, 5);
data.pm25_diff = [0; diff(data.pm25)];
data.ratio = data.pm25 ./ max(data.pm10, 0.1);
data.spike = abs(data.pm25_diff) > 10;

% --- 2. Source Detection (Explainable Rule-Based Logic) ---
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

% --- 3. Phase 5: Time Series Forecasting (Pre-emptive Warnings) ---
fprintf('Generating predictive forecasts...\n');
% Train a simple linear model on historical data
% x = current value, y = next value
x = data.pm25(1:end-1);
y = data.pm25(2:end);
forecastModel = fitlm(x, y);

% Generate 1-step-ahead forecasts for the whole series
data.forecast = [NaN; predict(forecastModel, data.pm25(1:end-1))];

% --- 4. Phase 6: Adaptive Recommendation Engine ---
fprintf('Executing adaptive recommendation logic...\n');
recommendation = strings(height(data), 1);

for i = 1:height(data)
    % Hybrid logic using current value, trend, and prediction
    currPM25 = data.pm25(i);
    trend = data.pm25_diff(i);
    predicted = data.forecast(i);
    
    % Dynamic thresholds (rolling 60-sample window)
    window_start = max(1, i-60);
    window = data.pm25(window_start:i);
    baseline = mean(window, 'omitnan');
    std_dev = std(window, 'omitnan');
    if std_dev == 0 || isnan(std_dev), std_dev = 5; end
    
    % Adaptive thresholds
    danger_thresh = baseline + 3 * std_dev;
    danger_thresh = max(danger_thresh, 50); % Minimum absolute cap
    
    moderate_thresh = baseline + 1.5 * std_dev;
    moderate_thresh = max(moderate_thresh, 25); % Minimum absolute cap
    
    if currPM25 > danger_thresh
        recommendation(i) = "DANGER: Wear mask & activate purifier";
    elseif trend > 5 || (i > 1 && predicted > danger_thresh * 0.7)
        recommendation(i) = "PRE-EMPTIVE: Close windows - quality worsening";
    elseif data.source(i) == "Dust"
        recommendation(i) = "CAUTION: Outdoor dust detected - avoid exercise";
    elseif currPM25 > moderate_thresh
        recommendation(i) = "MODERATE: Consider ventilation";
    else
        recommendation(i) = "Air is acceptable";
    end
end
data.recommendation = recommendation;

% --- 5. Visualization Dashboard ---
figure('Name', 'Adaptive Intelligence Master Dashboard', 'Color', 'w', 'Position', [50, 50, 1100, 800]);

% Subplot 1: PM2.5 with Forecast Overlay
subplot(3,1,1);
plot(data.pm25, 'k', 'LineWidth', 1, 'DisplayName', 'Actual PM2.5'); hold on;
plot(data.forecast, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Linear Forecast');
title('Air Quality Forecasting: Actual vs Predicted');
ylabel('\mu g / m^3');
legend('Location', 'best');
grid on;

% Subplot 2: Source Detection
subplot(3,1,2);
gscatter(1:height(data), data.pm25, data.source, 'brgm', 'o+x*');
title('Integrated Source Identification');
ylabel('\mu g / m^3');
grid on;

% Subplot 3: Adaptive Recommendation Feed
subplot(3,1,3);
% Visualize the recommendation severity
severity = zeros(height(data), 1);
severity(contains(data.recommendation, 'DANGER')) = 3;
severity(contains(data.recommendation, 'PRE-EMPTIVE')) = 2;
severity(contains(data.recommendation, 'MODERATE')) = 1;
severity(contains(data.recommendation, 'Acceptable')) = 0;

stairs(severity, 'LineWidth', 2, 'Color', [0.8500 0.3250 0.0980]);
yticks([0 1 2 3]);
yticklabels({'Acceptable', 'Moderate', 'Pre-emptive', 'Danger'});
title('Adaptive Intelligence: Decision Feed');
xlabel('Samples');
grid on;

% Print summary of the session
fprintf('\n--- Adaptive Intelligence Summary ---\n');
latestIdx = height(data);
fprintf('Current PM2.5: %.1f | Source: %s\n', data.pm25(latestIdx), data.source(latestIdx));
fprintf('Forecasted:    %.1f | Recommendation: %s\n', data.forecast(latestIdx), data.recommendation(latestIdx));
fprintf('-------------------------------------\n');
