%% detect_novelty.m
% Master's Level Enhancement - Phase 5: Unsupervised Learning
%
% This script implements a full "Novelty Detection" pipeline using the
% custom Isolation Forest (IsolationForestAD).
%
% Research Question:
%   "Can we detect UNKNOWN pollution events that the supervised Random Forest
%    was never trained on, using only unsupervised anomaly detection?"
%
% This is a key distinction between:
%   - Supervised RF  -> Can only detect what it was trained to see
%   - Isolation Forest -> Detects ANY statistical outlier, including novel events
%
% The script also compares the two detectors side-by-side, demonstrating
% the complementary nature of supervised + unsupervised learning.

clear; close all; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), '../src'));

FEATURE_NAMES = {'PM2.5/PM10 Ratio', 'Rate of Change', 'Acceleration', ...
                 'MA-5s', 'MA-15s', 'Volatility', ...
                 'Skewness', 'Kurtosis'};

% ===========================================================================
% 1. LOAD DATA
% ===========================================================================
logDir = 'logs';
logFiles = dir(fullfile(logDir, '*.csv'));
if isempty(logFiles)
    error('No log files in %s.', logDir);
end

allData = table();
for i = 1:length(logFiles)
    T = readtable(fullfile(logDir, logFiles(i).name));
    % Reconstruct Features matrix from CSV-split columns (writetable splits matrix cols)
    featCols = T.Properties.VariableNames(startsWith(T.Properties.VariableNames, 'Features_'));
    if ~isempty(featCols)
        T.Features = T{:, featCols};
        T = removevars(T, featCols);
    end
    if ismember('Features', T.Properties.VariableNames)
        allData = [allData; T];
    end
end

validIdx = ~isnan(allData.PM25);
data     = allData(validIdx, :);
X        = data.Features;
N        = size(X, 1);
fprintf('Loaded %d samples for novelty detection.\n', N);

% ===========================================================================
% 2. TRAIN ISOLATION FOREST ON "CLEAN" DATA ONLY
% ===========================================================================
% Strategy: use only samples labeled "Clean" for training.
% This teaches the IF what "normal" looks like, so any deviation = anomaly.
if ismember('Source', data.Properties.VariableNames)
    clean_mask = strcmp(data.Source, 'Clean');
    X_clean    = X(clean_mask, :);
    fprintf('Training on %d "Clean" samples (%.1f%% of data).\n', ...
        sum(clean_mask), 100*sum(clean_mask)/N);
else
    % Fallback: use first 70% as "baseline normal"
    X_clean = X(1:floor(0.7*N), :);
    fprintf('No labels found. Using first 70%% as training baseline.\n');
end

if size(X_clean,1) < 10
    warning('Very few clean samples. Results may be unreliable.');
    X_clean = X;
end

iforest = IsolationForestAD(100, min(256, size(X_clean,1)));
iforest.fit(X_clean);

% ===========================================================================
% 3. SCORE ALL DATA
% ===========================================================================
fprintf('Computing anomaly scores for all %d samples...\n', N);
scores = iforest.score(X);

% Choose threshold using the 95th percentile of clean scores
clean_scores  = iforest.score(X_clean);
threshold_95  = prctile(clean_scores, 95);
iforest.Threshold = threshold_95;
fprintf('Auto-selected threshold (95th pct of clean): %.4f\n', threshold_95);

anomaly_labels = scores > threshold_95;
fprintf('Detected %d anomalous samples (%.1f%% of all data).\n', ...
    sum(anomaly_labels), 100*sum(anomaly_labels)/N);

% ===========================================================================
% 4. COMPARE: ISOLATION FOREST vs SUPERVISED RANDOM FOREST
% ===========================================================================
if ismember('Source', data.Properties.VariableNames)
    known_events = ~strcmp(data.Source, 'Clean') & ~strcmp(data.Source, '');
    
    % How many known events did IF catch?
    if_caught_known = sum(anomaly_labels & known_events);
    if_missed_known = sum(~anomaly_labels & known_events);
    
    % "Novel" anomalies: IF flagged but labeled Clean (potential unknown events)
    novel_candidates = anomaly_labels & strcmp(data.Source, 'Clean');
    
    fprintf('\n--- Isolation Forest vs Supervised RF ---\n');
    fprintf('  Known pollution events detected:   %d / %d (%.1f%%)\n', ...
        if_caught_known, sum(known_events), ...
        100 * if_caught_known / max(sum(known_events), 1));
    fprintf('  Known events missed (IF blind spot): %d\n', if_missed_known);
    fprintf('  Novel/Unknown anomaly candidates:   %d\n', sum(novel_candidates));
    fprintf('  (These are samples flagged by IF but labeled "Clean" by RF)\n');
end

% ===========================================================================
% 5. VISUALIZATION
% ===========================================================================
figure('Name', 'Phase 5 - Novelty Detection', 'Color', 'w', 'Position', [50, 50, 1200, 900]);

%% Panel 1: Anomaly Score Time Series
ax1 = subplot(3, 2, [1 2]);
t = 1:N;
area(t, scores, 'FaceColor', [0.75 0.87 1.0], 'EdgeColor', [0.2 0.5 0.8], ...
    'LineWidth', 0.8, 'DisplayName', 'Anomaly Score');
hold on;
yline(threshold_95, 'r--', 'LineWidth', 2, ...
    'Label', sprintf('Threshold = %.3f (95th pct)', threshold_95));

% Highlight detected anomalies
anom_idx = find(anomaly_labels);
scatter(anom_idx, scores(anom_idx), 30, 'r', 'filled', ...
    'MarkerEdgeColor', 'none', 'DisplayName', 'Detected Anomaly');

% Overlay known labeled events if available
if ismember('Source', data.Properties.VariableNames)
    known_idx = find(known_events);
    scatter(known_idx, scores(known_idx), 50, 'g', 's', ...
        'LineWidth', 1.5, 'DisplayName', 'Known Event (RF label)');
end

xlabel('Sample Index'); ylabel('Anomaly Score');
title('Isolation Forest Anomaly Scores over Time', 'FontWeight', 'bold');
legend('Location', 'best'); grid on; ylim([0 1.05]);

%% Panel 2: Score Distribution
ax2 = subplot(3, 2, 3);
histogram(clean_scores, 30, 'FaceColor', [0.2 0.7 0.3], ...
    'EdgeColor', 'w', 'Normalization', 'probability', 'DisplayName', 'Clean Samples');
hold on;
histogram(scores(anomaly_labels), 20, 'FaceColor', [0.9 0.2 0.2], ...
    'EdgeColor', 'w', 'Normalization', 'probability', 'DisplayName', 'Detected Anomalies');
xline(threshold_95, 'k--', 'LineWidth', 2, 'Label', 'Threshold');
xlabel('Anomaly Score'); ylabel('Probability');
title('Score Distribution: Clean vs Anomalies', 'FontWeight', 'bold');
legend('Location', 'best'); grid on;

%% Panel 3: Feature Contribution to Anomalies (Mean |deviation| from clean)
ax3 = subplot(3, 2, 4);
if sum(anomaly_labels) > 0 && size(X_clean,1) > 1
    clean_mean  = mean(X_clean, 1, 'omitnan');
    anom_X      = X(anomaly_labels, :);
    contribution = mean(abs(anom_X - clean_mean), 1, 'omitnan');
    contribution_norm = contribution / max(contribution);
    
    [sorted_contrib, si] = sort(contribution_norm, 'descend');
    barh(ax3, sorted_contrib, 'FaceColor', [0.8 0.3 0.1]);
    set(ax3, 'YTick', 1:8, 'YTickLabel', flip(FEATURE_NAMES(si)));
    xlabel('Normalized Mean Deviation from Clean Baseline');
    title('Which Features Drive Anomalies?', 'FontWeight', 'bold');
    grid on;
end

%% Panel 4: PCA 2D - Normal vs Anomaly Clusters
ax4 = subplot(3, 2, 5);
[~, score_pca] = pca(X);
scatter(ax4, score_pca(~anomaly_labels,1), score_pca(~anomaly_labels,2), ...
    20, [0.4 0.7 1.0], 'filled', 'MarkerEdgeColor', 'none', ...
    'DisplayName', 'Normal');
hold on;
scatter(ax4, score_pca(anomaly_labels,1), score_pca(anomaly_labels,2), ...
    50, 'r', 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.5, ...
    'DisplayName', 'Detected Anomaly');
xlabel('PC1'); ylabel('PC2');
title('PCA Projection: Normal vs Anomaly', 'FontWeight', 'bold');
legend('Location', 'best'); grid on;

%% Panel 5: PM2.5 time series with anomaly overlay
ax5 = subplot(3, 2, 6);
plot(t, data.PM25, 'Color', [0.6 0.6 0.6], 'LineWidth', 1, ...
    'DisplayName', 'PM2.5');
hold on;
scatter(anom_idx, data.PM25(anom_idx), 40, 'r', 'filled', ...
    'MarkerEdgeColor', 'k', 'LineWidth', 0.3, ...
    'DisplayName', 'IF Anomaly');
xlabel('Sample Index'); ylabel('PM2.5 (\mug/m^3)');
title('PM2.5 Signal with Detected Anomalies', 'FontWeight', 'bold');
legend('Location', 'best'); grid on;

% ===========================================================================
% 6. SAVE ANOMALY REPORT
% ===========================================================================
if ~exist('logs', 'dir'), mkdir('logs'); end
report_file = fullfile('logs', sprintf('NoveltyReport_%s.csv', ...
    datestr(now, 'yyyymmdd_HHMMSS')));

anomaly_table = data(anomaly_labels, :);
anomaly_table.AnomalyScore = scores(anomaly_labels);
writetable(anomaly_table, report_file);
fprintf('\nAnomaly report saved: %s (%d records)\n', report_file, sum(anomaly_labels));

% ===========================================================================
% 7. SAVE TRAINED DETECTOR FOR REAL-TIME DEPLOYMENT
% ===========================================================================
if ~exist('models', 'dir'), mkdir('models'); end
modelPath = fullfile('models', 'noveltyDetector.mat');
NoveltyDetector = iforest;  % rename to match what AirQualitySystem.m expects
save(modelPath, 'NoveltyDetector');
fprintf('Isolation Forest saved to %s for real-time use.\n', modelPath);
fprintf('Phase 5 (Unsupervised Learning) complete.\n');
