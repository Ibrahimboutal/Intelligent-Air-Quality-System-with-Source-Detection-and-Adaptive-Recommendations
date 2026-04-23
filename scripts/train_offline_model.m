% scripts/train_offline_model.m
% -------------------------------------------------------------------------
% Offline Training & Evaluation Script
% This script simulates physical sensor data, extracts features, calculates
% Z-score scaling parameters, trains a Random Forest ensemble, evaluates
% the model (Confusion Matrix, F1-Score, Precision, Recall), and saves
% the trained model for zero-latency online inference.
% -------------------------------------------------------------------------

clc; clear; close all;

fprintf('=== Offline ML Training & Evaluation Pipeline ===\n\n');

%% 1. Data Collection Placeholder
fprintf('1. Collecting/Generating Dataset...\n');
%% 1. Data Collection Phase
fprintf('1. Loading Physical Dataset from logs...\n');

% Path to your collected data
logDir = '../logs';
logFiles = dir(fullfile(logDir, 'AQI_Log_*.csv'));

if isempty(logFiles)
    error('No log files found in %s. Please run a monitoring session first to collect data!', logDir);
end

% Auto-select the most recent log file
[~, idx] = sort([logFiles.datenum], 'descend');
latestLog = fullfile(logDir, logFiles(idx(1)).name);
fprintf('   Training on: %s\n', latestLog);

% Load the data
dataTbl = readtable(latestLog);

% Extract Features (7D) and Source Labels
% The Features are stored in columns 4 through 10 based on our logging format
X_raw = dataTbl{:, 4:10}; 
Y_raw = dataTbl.Source;

% Convert labels to categorical for training
Y = categorical(Y_raw);
N = size(X_raw, 1);
fprintf('   Successfully loaded %d physical samples.\n', N);

%% 2. Chronological Train-Test Split (80/20)
% For time-series data, we must split chronologically to prevent data leakage 
% (using future data to predict the past).
fprintf('2. Performing Chronological Train-Test Split (80%% / 20%%)...\n');
splitIdx = round(N * 0.8);

X_train_raw = X_raw(1:splitIdx, :);
Y_train     = Y(1:splitIdx);
X_test_raw  = X_raw(splitIdx+1:end, :);
Y_test      = Y(splitIdx+1:end);

fprintf('   Training on first %d samples, testing on final %d samples.\n', splitIdx, N - splitIdx);

%% 3. Feature Scaling (Z-score Normalization)
fprintf('3. Calculating Z-score normalization parameters...\n');
FeatureMu = mean(X_train_raw, 1);
FeatureSigma = std(X_train_raw, 0, 1);
FeatureSigma(FeatureSigma == 0) = 1e-6; % Prevent division by zero

X_train = (X_train_raw - FeatureMu) ./ FeatureSigma;
X_test  = (X_test_raw - FeatureMu) ./ FeatureSigma;

%% 4. Model Training
fprintf('4. Training Random Forest Ensemble...\n');
if exist('fitcensemble', 'file') == 2
    MLModel = fitcensemble(X_train, Y_train, 'Method', 'Bag', 'NumLearningCycles', 50);
else
    error('Statistics and Machine Learning Toolbox is required to run this offline script.');
end

%% 5. Evaluation Metrics
fprintf('5. Evaluating Model on Unseen Test Data...\n');
Y_pred = predict(MLModel, X_test);

% Confusion Matrix
figure('Name', 'Confusion Matrix');
confusionchart(Y_test, Y_pred, 'Title', 'Test Set Confusion Matrix');

% Precision, Recall, F1-Score
classes = categories(Y_test);
fprintf('\n--- Classification Report ---\n');
for i = 1:length(classes)
    c = classes{i};
    TP = sum((Y_pred == c) & (Y_test == c));
    FP = sum((Y_pred == c) & (Y_test ~= c));
    FN = sum((Y_pred ~= c) & (Y_test == c));
    
    precision = TP / max((TP + FP), 1e-6);
    recall    = TP / max((TP + FN), 1e-6);
    f1_score  = 2 * (precision * recall) / max((precision + recall), 1e-6);
    
    fprintf('Class: %s\n', char(c));
    fprintf('  Precision: %.2f%%\n', precision * 100);
    fprintf('  Recall:    %.2f%%\n', recall * 100);
    fprintf('  F1-Score:  %.2f\n\n', f1_score);
end

%% 6. Save Artifacts
fprintf('6. Saving model artifacts to models/trainedModel.mat...\n');
if ~exist('../models', 'dir')
    mkdir('../models');
end
save('../models/trainedModel.mat', 'MLModel', 'FeatureMu', 'FeatureSigma');
fprintf('Done! System is ready for zero-latency online deployment.\n');
