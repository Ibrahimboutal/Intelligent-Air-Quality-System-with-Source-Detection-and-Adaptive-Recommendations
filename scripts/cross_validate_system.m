%% cross_validate_system.m
% Master's Level Enhancement - Phase 1: Statistical Validation
% This script performs K-Fold Cross-Validation to ensure model stability
% and robustness across different data subsets.

clear; close all; clc;

% --- 1. Load Data ---
logDir = '../logs';
logFiles = dir(fullfile(logDir, '*.csv'));

if isempty(logFiles)
    error('No log files found in %s.', logDir);
end

allData = table();
for i = 1:length(logFiles)
    T = readtable(fullfile(logDir, logFiles(i).name));
    % Reconstruct Features_7D matrix from CSV-split columns
    featCols = T.Properties.VariableNames(startsWith(T.Properties.VariableNames, 'Features_7D_'));
    if ~isempty(featCols)
        T.Features_7D = T{:, featCols};
        T = removevars(T, featCols);
    end
    allData = [allData; T];
end

validIdx = ~isnan(allData.PM25) & ~strcmp(allData.Source, "");
data = allData(validIdx, :);
X = data.Features_7D;
y = categorical(data.Source);

% Handle variable naming if Features_7D is a multi-column matrix
if size(X, 2) == 1 && iscell(X)
    X = cell2mat(data.Features_7D);
end

% --- 2. K-Fold Cross-Validation ---
K = 5; % 5-Fold Cross Validation
fprintf('Starting %d-Fold Cross-Validation...\n', K);

cp = cvpartition(y, 'KFold', K);
accuracies = zeros(K, 1);

for i = 1:K
    trainIdx = training(cp, i);
    testIdx = test(cp, i);
    
    X_train = X(trainIdx, :);
    y_train = y(trainIdx);
    X_test  = X(testIdx, :);
    y_test  = y(testIdx);
    
    % Train Random Forest
    numTrees = 50;
    B = TreeBagger(numTrees, X_train, y_train, 'Method', 'classification');
    
    % Predict
    y_pred_str = predict(B, X_test);
    y_pred = categorical(y_pred_str);
    
    % Accuracy for this fold
    accuracies(i) = sum(y_test == y_pred) / length(y_test);
    fprintf('  Fold %d Accuracy: %.2f%%\n', i, accuracies(i) * 100);
end

% --- 3. Report Results ---
meanAcc = mean(accuracies);
stdAcc = std(accuracies);

fprintf('\n--- Cross-Validation Summary ---\n');
fprintf('Mean Accuracy: %.2f%%\n', meanAcc * 100);
fprintf('Std Deviation: %.2f%%\n', stdAcc * 100);
fprintf('Confidence Interval (95%%): %.2f%% - %.2f%%\n', ...
    (meanAcc - 1.96*stdAcc/sqrt(K))*100, (meanAcc + 1.96*stdAcc/sqrt(K))*100);

% Plot Accuracy per Fold
figure('Name', 'K-Fold Cross Validation', 'Color', 'w');
bar(accuracies * 100);
hold on;
yline(meanAcc * 100, 'r--', 'LineWidth', 2, 'Label', 'Mean Accuracy');
xlabel('Fold Number');
ylabel('Accuracy (%)');
title(sprintf('%d-Fold Cross Validation Results', K));
grid on;
ylim([0 100]);
