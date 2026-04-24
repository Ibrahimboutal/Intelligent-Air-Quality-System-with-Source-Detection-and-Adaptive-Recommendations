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

% Enhancement: Aggregate ALL historical logs for a richer dataset
fprintf('   Aggregating data from %d historical log sessions...\n', length(logFiles));
dataTbl = table();
for i = 1:length(logFiles)
    tempTbl = readtable(fullfile(logDir, logFiles(i).name));
    dataTbl = [dataTbl; tempTbl]; % Vertical concatenation
end

% Extract Features (7D) and Source Labels
X_raw = dataTbl{:, 4:10}; 
Y_raw = dataTbl.Source;

% Convert labels to categorical for training
Y = categorical(Y_raw);
N = size(X_raw, 1);
fprintf('   Successfully loaded %d total physical samples.\n', N);

%% 2. Feature Selection Validation (Collinearity Check)
fprintf('2. Validating Feature Orthogonality (Correlation Matrix)...\n');
featureNames = {'Ratio', 'ROC', 'MA5', 'MA15', 'Std5', 'Skew15', 'Kurt15'};
R = corrcoef(X_raw);

figure('Name', 'Feature Correlation Heatmap', 'Color', 'w');
h = heatmap(featureNames, featureNames, R);
h.Title = 'Feature Correlation Matrix (Validation of Collinearity)';
h.Colormap = parula;
fprintf('   Collinearity check complete. Visualizing feature relationships.\n');

%% 4. Chronological Train-Test Split (80/20)
% For time-series data, we must split chronologically to prevent data leakage 
% (using future data to predict the past).
fprintf('4. Performing Chronological Train-Test Split (80%% / 20%%)...\n');
splitIdx = round(N * 0.8);

X_train_raw = X_raw(1:splitIdx, :);
Y_train     = Y(1:splitIdx);
X_test_raw  = X_raw(splitIdx+1:end, :);
Y_test      = Y(splitIdx+1:end);

fprintf('   Training on first %d samples, testing on final %d samples.\n', splitIdx, N - splitIdx);

%% 5. Feature Scaling (Z-score Normalization)
fprintf('5. Calculating Z-score normalization parameters...\n');
FeatureMu = mean(X_train_raw, 1);
FeatureSigma = std(X_train_raw, 0, 1);
FeatureSigma(FeatureSigma == 0) = 1e-6; % Prevent division by zero

X_train = (X_train_raw - FeatureMu) ./ FeatureSigma;
X_test  = (X_test_raw - FeatureMu) ./ FeatureSigma;

%% 6. Model Training
fprintf('6. Training Random Forest Ensemble...\n');

% Create an observation weight vector (N x 1)
% This mathematically forces the algorithm to pay attention to minority classes
obsWeights = zeros(size(Y_train));
cats = categories(Y_train);

for i = 1:length(cats)
    idx = (Y_train == cats{i});
    classCount = sum(idx);
    
    if classCount > 0
        % Inverse frequency weighting: Rare classes get massive weight multipliers
        obsWeights(idx) = 1.0 / classCount;
    end
end

% Normalize weights so they sum to the total number of training samples
obsWeights = obsWeights * (length(Y_train) / sum(obsWeights));

if exist('fitcensemble', 'file') == 2
    % Train using 'Weights' to fix the Lazy Learner problem
    MLModel = fitcensemble(X_train, Y_train, 'Method', 'Bag', ...
                           'NumLearningCycles', 50, ...
                           'Weights', obsWeights);
else
    error('Statistics and Machine Learning Toolbox is required to run this offline script.');
end

%% 7. Evaluation Metrics
fprintf('7. Evaluating Model on Unseen Test Data...\n');
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

%% 8. Save Artifacts
fprintf('8. Saving model artifacts to models/trainedModel.mat...\n');
if ~exist('../models', 'dir')
    mkdir('../models');
end
save('../models/trainedModel.mat', 'MLModel', 'FeatureMu', 'FeatureSigma');
fprintf('Done! System is ready for zero-latency online deployment.\n');
