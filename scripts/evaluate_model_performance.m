%% evaluate_model_performance.m
% Master's Level Enhancement - Phase 1: Statistical Validation
% This script loads historical logs, performs a chronological 80/20 split,
% and evaluates the Random Forest model using Precision, Recall, and F1-Score.

clear; close all; clc;

% --- 1. Load Data ---
logDir = 'logs';
logFiles = dir(fullfile(logDir, '*.csv'));

if isempty(logFiles)
    error('No log files found in %s. Run a monitoring session first.', logDir);
end

fprintf('Loading data from %d log files...\n', length(logFiles));
allData = table();
for i = 1:length(logFiles)
    T = readtable(fullfile(logDir, logFiles(i).name));
    allData = [allData; T];
end

% --- 2. Preprocess Data ---
% Remove rows with missing labels or features
validIdx = ~isnan(allData.PM25) & ~strcmp(allData.Source, "");
data = allData(validIdx, :);

X = data.Features_7D;
y = categorical(data.Source);

% Handle variable naming if Features_7D is a multi-column matrix in the table
if size(X, 2) == 1 && iscell(X)
    % Sometimes writetable/readtable flattens or cell-wraps arrays
    % This is a safeguard
    X = cell2mat(data.Features_7D);
end

fprintf('Total samples collected: %d\n', size(X, 1));
fprintf('Unique Classes: %s\n', strjoin(string(categories(y)), ', '));

% --- 3. Chronological 80/20 Split ---
% For time-series, we don't shuffle! We take the first 80% for training
% and the last 20% for testing to avoid "future leakage".
splitIdx = floor(0.8 * size(X, 1));

X_train = X(1:splitIdx, :);
y_train = y(1:splitIdx);
X_test  = X(splitIdx+1:end, :);
y_test  = y(splitIdx+1:end);

% --- 4. Model Training (Random Forest) ---
fprintf('\nTraining Random Forest model (80%% split)...\n');
numTrees = 50;
B = TreeBagger(numTrees, X_train, y_train, 'Method', 'classification', ...
               'OOBPrediction', 'on');

% --- 5. Evaluation ---
fprintf('Predicting on Test Set (20%% split)...\n');
y_pred_str = predict(B, X_test);
y_pred = categorical(y_pred_str);

% Generate Confusion Matrix
figure('Name', 'Model Validation Results', 'Color', 'w', 'Position', [100, 100, 800, 600]);
cm = confusionchart(y_test, y_pred, 'Title', 'Confusion Matrix: Air Quality Source Detection', ...
    'RowSummary', 'row-normalized', 'ColumnSummary', 'column-normalized');
cm.FontSize = 12;

% Calculate Precision, Recall, and F1-Score manually for per-class details
stats = confusionmat(y_test, y_pred);
classes = categories(y_test);
numClasses = length(classes);

precision = zeros(numClasses, 1);
recall = zeros(numClasses, 1);
f1Score = zeros(numClasses, 1);

fprintf('\n--- Performance Metrics ---\n');
fprintf('%-25s | %-10s | %-10s | %-10s\n', 'Class', 'Precision', 'Recall', 'F1-Score');
fprintf('%s\n', repmat('-', 1, 65));

for i = 1:numClasses
    tp = stats(i,i);
    fp = sum(stats(:,i)) - tp;
    fn = sum(stats(i,:)) - tp;
    
    if (tp + fp) > 0, precision(i) = tp / (tp + fp); else, precision(i) = 0; end
    if (tp + fn) > 0, recall(i) = tp / (tp + fn); else, recall(i) = 0; end
    if (precision(i) + recall(i)) > 0
        f1Score(i) = 2 * (precision(i) * recall(i)) / (precision(i) + recall(i));
    else
        f1Score(i) = 0;
    end
    
    fprintf('%-25s | %-10.3f | %-10.3f | %-10.3f\n', classes{i}, precision(i), recall(i), f1Score(i));
end

fprintf('%s\n', repmat('-', 1, 65));
fprintf('%-25s | %-10.3f | %-10.3f | %-10.3f\n', 'AVERAGE (Macro)', mean(precision), mean(recall), mean(f1Score));

% --- 6. Save Model for Deployment ---
% Save the trained model and scaling parameters back to models/
modelPath = fullfile('models', 'trainedModel.mat');
if ~exist('models', 'dir'), mkdir('models'); end

% For scaling, we'd normally use the training set statistics
FeatureMu = mean(X_train);
FeatureSigma = std(X_train);
MLModel = B;

save(modelPath, 'MLModel', 'FeatureMu', 'FeatureSigma');
fprintf('\nModel saved to %s for real-time deployment.\n', modelPath);
