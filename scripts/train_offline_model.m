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
% Placeholder: Generate synthetic dataset representing physical events
% Replace this block with readtable('your_physical_data.csv') once collected!
N = 2000;
X_raw = zeros(N, 7);
Y = strings(N, 1);

for i = 1:N
    pm25_base = 10 + 5*rand();
    pm10_base = 12 + 6*rand();
    
    sourceType = randi(4);
    if sourceType == 1 % Clean
        X_raw(i,:) = [pm25_base/pm10_base, 2*randn(), pm25_base, pm25_base, 1+rand(), 0, 3];
        Y(i) = "Clean";
    elseif sourceType == 2 % Combustion
        pm25 = pm25_base + 50 + 20*rand();
        pm10 = pm10_base + 55 + 20*rand();
        X_raw(i,:) = [pm25/pm10, 5+5*rand(), pm25-10, pm25-20, 10+5*rand(), 2*rand(), 4+rand()];
        Y(i) = "Combustion (cooking / smoke)";
    elseif sourceType == 3 % Dust Spike
        pm25 = pm25_base + 30 + 10*rand();
        pm10 = pm10_base + 35 + 10*rand();
        X_raw(i,:) = [pm25/pm10, 15+10*rand(), pm25-15, pm25-25, 15+5*rand(), -1+2*rand(), 5+2*rand()];
        Y(i) = "Dust / Sudden disturbance";
    else % Coarse Particles
        pm25 = pm25_base + 5 + 5*rand();
        pm10 = pm10_base + 40 + 20*rand();
        X_raw(i,:) = [pm25/pm10, 2+3*rand(), pm25-2, pm25-5, 5+2*rand(), 0.5*rand(), 3+rand()];
        Y(i) = "Coarse particles (outdoor dust)";
    end
end
Y = categorical(Y);

%% 2. Train-Test Split (80/20)
fprintf('2. Performing Train-Test Split (80%% / 20%%)...\n');
cv = cvpartition(N, 'HoldOut', 0.2);
X_train_raw = X_raw(training(cv), :);
Y_train     = Y(training(cv));
X_test_raw  = X_raw(test(cv), :);
Y_test      = Y(test(cv));

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
