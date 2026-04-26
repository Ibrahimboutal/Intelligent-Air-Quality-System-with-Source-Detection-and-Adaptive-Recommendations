%% Phase 4: Hybrid Source Detection (Rule-Based + Random Forest)
% This script implements a hybrid intelligence layer to classify 
% the source of air pollution.

clear; clc; close all;

% --- 1. Load & Engineer Features (from Phase 3) ---
logDir = '../logs';
files = dir(fullfile(logDir, 'AQI_Log_*.csv'));
if isempty(files), error('No log files found.'); end
[~, idx] = sort([files.datenum], 'descend');
latestFile = fullfile(logDir, files(idx(1)).name);

fprintf('Processing latest data for ML Training: %s\n', latestFile);
data = readtable(latestFile);

% Engineering Core Features
data.pm25_avg = movmean(data.pm25, 5);
data.pm10_avg = movmean(data.pm10, 5);
data.pm25_diff = [0; diff(data.pm25)];
data.ratio = data.pm25 ./ max(data.pm10, 0.1);
threshold = 10;
data.spike = abs(data.pm25_diff) > threshold;

% --- 2. Phase 4: Rule-Based Labeling (The Explainable Core) ---
fprintf('Applying rule-based classification...\n');
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

data.source = categorical(source); % Convert to categorical for ML

% --- 3. Phase 4: Random Forest Training (The Intelligence Layer) ---
fprintf('Training Random Forest model (TreeBagger)...\n');

% Define feature matrix
featureNames = {'pm25', 'pm10', 'pm25_avg', 'pm10_avg', 'pm25_diff', 'ratio'};
X = data(:, featureNames);
Y = data.source;

% Train model (50 trees)
numTrees = 50;
model = TreeBagger(numTrees, X, Y, 'OOBPrediction', 'On', ...
                   'Method', 'classification', ...
                   'PredictorNames', featureNames);

% Evaluate model (Out-of-Bag Error)
oobErr = oobError(model);
fprintf('Model trained. Final Out-of-Bag Error: %.4f\n', oobErr(end));

% Save the model for future real-time use
if ~exist('../models', 'dir'), mkdir('../models'); end
save('../models/source_classifier.mat', 'model');
fprintf('Model saved to models/source_classifier.mat\n');

% --- 4. Visualization ---
figure('Name', 'Source Detection Dashboard', 'Color', 'w', 'Position', [100, 100, 1000, 600]);

% Subplot 1: PM2.5 colored by detected source
subplot(2,1,1);
gscatter(1:height(data), data.pm25, data.source, 'brgm', 'o+x*');
title('PM2.5 Concentration by Classified Source');
ylabel('\mu g / m^3');
grid on;

% Subplot 2: Feature Importance
subplot(2,1,2);
model = fillVariablesImportance(model, X, Y); % Custom importance calculation
if ~isempty(model.OOBPermutedPredictorDeltaError)
    bar(model.OOBPermutedPredictorDeltaError);
    set(gca, 'XTickLabel', featureNames);
    title('Random Forest Feature Importance');
    ylabel('Importance Score');
    grid on;
end

function model = fillVariablesImportance(model, X, Y)
    % Helper to compute variable importance if not natively calculated
    model = TreeBagger(model.NumTrees, X, Y, 'Method', 'classification', ...
                       'OOBPredictorImportance', 'on');
end
