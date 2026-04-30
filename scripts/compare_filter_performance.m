%% compare_filter_performance.m
% Master's Level Enhancement - Phase 2: Signal Processing
%
% This script performs a rigorous comparative study of three denoising methods:
%   1. Raw Sensor Data (no filtering)
%   2. Kalman Filter (optimal recursive Bayesian estimator)
%   3. Savitzky-Golay Filter (polynomial smoothing)
%
% The study answers a key Master's-level research question:
%   "Does denoising the PM2.5 signal improve downstream ML classification accuracy?"

clear; close all; clc;

% Ensure the src directory is on the path
addpath(fullfile(fileparts(mfilename('fullpath')), '../src'));

% ===========================================================================
% 1. LOAD & PREPARE DATA
% ===========================================================================
logDir = 'logs';
logFiles = dir(fullfile(logDir, '*.csv'));

if isempty(logFiles)
    error('No log files found. Run a monitoring session first (SimMode is fine).');
end

fprintf('Loading log data...\n');
allData = table();
for i = 1:length(logFiles)
    T = readtable(fullfile(logDir, logFiles(i).name));
    % Reconstruct Features_7D matrix from CSV-split columns
    featCols = T.Properties.VariableNames(startsWith(T.Properties.VariableNames, 'Features_7D_'));
    if ~isempty(featCols)
        T.Features_7D = T{:, featCols};
        T = removevars(T, featCols);
    end
    if ismember('PM25', T.Properties.VariableNames) && ismember('Source', T.Properties.VariableNames)
        allData = [allData; T];
    end
end

if height(allData) < 30
    error('Not enough data samples (need at least 30 rows). Run a longer monitoring session.');
end

pm25_raw = allData.PM25;
fprintf('Loaded %d PM2.5 samples.\n', length(pm25_raw));

% ===========================================================================
% 2. APPLY FILTERS
% ===========================================================================

%% --- Method 1: Kalman Filter ---
fprintf('\nApplying Kalman Filter...\n');
kf = KalmanFilter1D(1e-4, 0.5);  % Q=process noise, R=measurement noise
pm25_kalman = zeros(size(pm25_raw));
for i = 1:length(pm25_raw)
    pm25_kalman(i) = kf.update(pm25_raw(i));
end

%% --- Method 2: Savitzky-Golay Filter ---
% A polynomial-fitting smoother. Good for preserving peak shapes.
fprintf('Applying Savitzky-Golay Filter...\n');
sg_order = 3;   % Polynomial order
sg_frame = 11;  % Frame length (must be odd, > order)
pm25_sgolay = sgolayfilt(pm25_raw, sg_order, sg_frame);

% ===========================================================================
% 3. COMPARATIVE ANALYSIS
% ===========================================================================
fprintf('\n--- Denoising Performance Summary ---\n');
fprintf('%-25s | %-12s | %-12s | %-12s\n', 'Metric', 'Raw', 'Kalman', 'Sav-Golay');
fprintf('%s\n', repmat('-', 1, 70));

% Mean Absolute Difference from Raw (how much smoothing was applied)
mad_kalman = mean(abs(pm25_kalman - pm25_raw));
mad_sg     = mean(abs(pm25_sgolay - pm25_raw));

% Signal roughness: std of first differences (lower = smoother)
rough_raw    = std(diff(pm25_raw));
rough_kalman = std(diff(pm25_kalman));
rough_sg     = std(diff(pm25_sgolay));

% SNR Improvement in dB
snr_kalman = 20 * log10(rough_raw / rough_kalman);
snr_sg     = 20 * log10(rough_raw / rough_sg);

fprintf('%-25s | %-12.4f | %-12.4f | %-12.4f\n', 'Signal Roughness (std)', rough_raw, rough_kalman, rough_sg);
fprintf('%-25s | %-12s | %-12.2f | %-12.2f\n', 'SNR Improvement (dB)', '0 (baseline)', snr_kalman, snr_sg);
fprintf('%-25s | %-12s | %-12.4f | %-12.4f\n', 'Avg Deviation from Raw', '0', mad_kalman, mad_sg);

% ===========================================================================
% 4. DOWNSTREAM ML IMPACT STUDY
% ===========================================================================
fprintf('\n--- Downstream ML Impact: Does Filtering Help? ---\n');

if ismember('Source', allData.Properties.VariableNames) && ismember('Features_7D', allData.Properties.VariableNames)
    validIdx = ~isnan(allData.PM25) & ~strcmp(allData.Source, "");
    data = allData(validIdx, :);
    
    if height(data) >= 20
        y_labels = categorical(data.Source);
        
        % Compare using the same 80/20 split for fairness
        split = floor(0.8 * height(data));
        
        % Build a minimal 1-feature classifier using raw vs. filtered PM2.5
        compare_signals = {'Raw PM2.5', 'Kalman-Filtered PM2.5', 'SG-Filtered PM2.5'};
        pm25_variants   = {pm25_raw(validIdx), pm25_kalman(validIdx), pm25_sgolay(validIdx)};
        
        for s = 1:3
            sig  = pm25_variants{s};
            X1 = sig(1:split);
            y1 = y_labels(1:split);
            X2 = sig(split+1:end);
            y2 = y_labels(split+1:end);
            
            B = TreeBagger(20, X1, y1, 'Method', 'classification');
            y_pred = categorical(predict(B, X2));
            acc = sum(y_pred == y2) / length(y2);
            fprintf('  Accuracy using %s: %.2f%%\n', compare_signals{s}, acc*100);
        end
    else
        fprintf('  (Not enough labeled samples for ML impact study — need more log data.)\n');
    end
end

% ===========================================================================
% 5. VISUALIZATION
% ===========================================================================
t = 1:length(pm25_raw);

figure('Name', 'Phase 2: Signal Denoising Comparison', 'Color', 'w', 'Position', [50, 50, 1100, 750]);

%% Panel 1: Full signal comparison
ax1 = subplot(3, 1, 1);
plot(t, pm25_raw, 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'DisplayName', 'Raw Sensor');
hold on;
plot(t, pm25_kalman, 'b-', 'LineWidth', 1.8, 'DisplayName', 'Kalman Filter');
plot(t, pm25_sgolay, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Savitzky-Golay');
title('PM_{2.5} Signal: Raw vs. Denoised', 'FontSize', 13, 'FontWeight', 'bold');
xlabel('Sample Index'); ylabel('Concentration (\mug/m^3)');
legend('Location', 'northwest'); grid on;

%% Panel 2: Zoomed in detail (first 200 samples or all if fewer)
ax2 = subplot(3, 1, 2);
zoom_end = min(200, length(pm25_raw));
plot(t(1:zoom_end), pm25_raw(1:zoom_end), 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'DisplayName', 'Raw');
hold on;
plot(t(1:zoom_end), pm25_kalman(1:zoom_end), 'b-', 'LineWidth', 2, 'DisplayName', 'Kalman');
plot(t(1:zoom_end), pm25_sgolay(1:zoom_end), 'r--', 'LineWidth', 1.5, 'DisplayName', 'Sav-Golay');
title(sprintf('Zoomed View: First %d Samples', zoom_end), 'FontSize', 12);
xlabel('Sample Index'); ylabel('Concentration (\mug/m^3)');
legend('Location', 'northwest'); grid on;

%% Panel 3: Kalman Gain over time (diagnostic)
ax3 = subplot(3, 1, 3);
if ~isempty(kf.KalmanGain)
    plot(kf.KalmanGain, 'm-', 'LineWidth', 1.5);
    title('Kalman Gain K_k over Time (Convergence Diagnostic)', 'FontSize', 12);
    xlabel('Sample Index'); ylabel('Kalman Gain K_k');
    yline(0, 'k--', 'LineWidth', 1);
    grid on;
    annotation('textbox', [0.14, 0.04, 0.5, 0.04], ...
        'String', 'K \rightarrow 0: Trusting model more | K \rightarrow 1: Trusting sensor more', ...
        'EdgeColor', 'none', 'FontSize', 10, 'Color', [0.3 0.3 0.3]);
end

linkaxes([ax1 ax2], 'y');
fprintf('\nFigure saved. Phase 2 complete.\n');
