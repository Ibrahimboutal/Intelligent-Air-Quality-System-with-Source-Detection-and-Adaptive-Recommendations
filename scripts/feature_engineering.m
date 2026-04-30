%% Phase 3: Feature Engineering & Data Science Module
% This script loads collected air quality data, engineers features, 
% and detects pollution spikes to provide baseline "intelligence".

clear; clc; close all;

% 1. Load your CSV in MATLAB
% Find the most recent log file in the logs/ directory
logDir = '../logs';
if ~exist(logDir, 'dir')
    error('Logs directory not found. Please ensure you have run the collector.');
end

files = dir(fullfile(logDir, 'AQI_Log_*.csv'));
if isempty(files)
    error('No log files found in %s', logDir);
end

% Sort by date to get the newest file
[~, idx] = sort([files.datenum], 'descend');
latestFile = fullfile(logDir, files(idx(1)).name);

fprintf('Loading data from: %s\n', latestFile);
data = readtable(latestFile);

% Ensure columns are standardized (as per Phase 2)
% Expected: Timestamp, PM25, PM10
if ~ismember('PM25', data.Properties.VariableNames)
    error('Data table is missing PM25 column. Check your collector format.');
end

% 2. Create Core Features
fprintf('Engineering features...\n');

% Moving Average (Smoothing noise)
% Window size 5 samples
data.pm25_avg = movmean(data.PM25, 5);
data.pm10_avg = movmean(data.PM10, 5);

% Rate of Change (Velocity of pollution increase)
% Pad with 0 to maintain table size
data.pm25_diff = [0; diff(data.PM25)];
data.pm10_diff = [0; diff(data.PM10)];

% Acceleration (Rate of rate of change)
data.pm25_accel = [0; diff(data.pm25_diff)];
data.pm10_accel = [0; diff(data.pm10_diff)];

% Ratio (Intelligence: High ratio indicates combustion/smoke, Low indicates dust)
data.ratio = data.PM25 ./ max(data.PM10, 0.1); % Prevent division by zero

% 3. Detect Spikes (Dynamic Intelligence)
% Define a threshold for sudden pollution increases
threshold = 10; 
data.spike = abs(data.pm25_diff) > threshold;

fprintf('Detected %d sudden spikes in air quality.\n', sum(data.spike));

% 4. Visualization
figure('Name', 'Feature Engineering & Spike Detection', 'Color', 'w', 'Position', [100, 100, 1000, 600]);

% Subplot 1: Raw Data vs Moving Average
subplot(3,1,1);
plot(data.PM25, 'Color', [0.7 0.7 0.7], 'DisplayName', 'Raw PM2.5'); hold on;
plot(data.pm25_avg, 'b', 'LineWidth', 1.5, 'DisplayName', '5-Sample Moving Avg');
% Highlight spikes
spikeIdx = find(data.spike);
if ~isempty(spikeIdx)
    scatter(spikeIdx, data.PM25(spikeIdx), 50, 'r', 'filled', 'DisplayName', 'Detected Spikes');
end
title('PM2.5: Raw vs Smoothed with Spike Detection');
ylabel('\mu g / m^3');
legend('Location', 'best');
grid on;

% Subplot 2: Rate of Change
subplot(3,1,2);
stem(data.pm25_diff, 'Marker', 'none', 'Color', [0.4660 0.6740 0.1880]);
title('Rate of Change (PM2.5 Velocity)');
ylabel('\Delta \mu g / m^3');
grid on;

% Subplot 3: PM2.5/PM10 Ratio
subplot(3,1,3);
plot(data.ratio, 'm', 'LineWidth', 1.2);
ylim([0 1.2]);
title('PM2.5 / PM10 Ratio (Source Identifier)');
ylabel('Ratio');
xlabel('Samples');
grid on;

fprintf('Feature Engineering Complete.\n');
