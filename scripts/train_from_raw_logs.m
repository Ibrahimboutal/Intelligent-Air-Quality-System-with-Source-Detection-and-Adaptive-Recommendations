clear; clc;

% 1. Load the Raw Python Data
logDir = '../logs';
logFiles = dir(fullfile(logDir, '*.csv'));
rawTbl = table();
for i = 1:length(logFiles)
    tempTbl = readtable(fullfile(logDir, logFiles(i).name));
    % Standardize column names only when the table uses raw Python log format
    % (3-column: Timestamp, PM25, PM10) to avoid corrupting richer log files
    if ~ismember('PM25', tempTbl.Properties.VariableNames) && width(tempTbl) >= 3
        tempTbl.Properties.VariableNames(1:3) = {'Timestamp', 'PM25', 'PM10'};
    end
    % Keep only the essential columns for raw-log training
    keepCols = intersect({'Timestamp','PM25','PM10'}, tempTbl.Properties.VariableNames, 'stable');
    if numel(keepCols) == 3
        rawTbl = [rawTbl; tempTbl(:, keepCols)];
    end
end
N = height(rawTbl);
fprintf('Successfully loaded %d raw samples from %d log files.\n', N, length(logFiles));

% 2. Extract Features using the AirQualitySystem Intelligence Core
disp('Engineering 7D Features and extracting baseline labels...');
% Initialize system in simulation mode to avoid hardware connection
aq = AirQualitySystem('127.0.0.1','pi','pass','COM1',9600,true);
aq.MLModel = []; % Force the system to use dynamic heuristics to generate labels

aq.PM25Data = rawTbl.PM25';
aq.PM10Data = rawTbl.PM10';

X_raw = zeros(N, 7);
Y_raw = strings(N, 1);

for k = 1:N
    X_raw(k, :) = aq.extractFeatures(k);
    % Use the mathematical fallback heuristics to label the training data
    [Y_raw(k), ~] = aq.analyze(k, X_raw(k,:), 0); 
end

% 3. Chronological Train/Test Split
Y = categorical(Y_raw);
splitIdx = round(N * 0.8);
X_train_raw = X_raw(1:splitIdx, :);
Y_train     = Y(1:splitIdx);

% 4. Calculate Z-Score Normalization specific to your room
FeatureMu = mean(X_train_raw, 1);
FeatureSigma = std(X_train_raw, 0, 1);
FeatureSigma(FeatureSigma == 0) = 1e-6; % Prevent division by zero

X_train = (X_train_raw - FeatureMu) ./ FeatureSigma;

% 5. Train the Machine Learning Model
disp('Training 50-Tree Random Forest Classifier...');
MLModel = TreeBagger(50, X_train, Y_train, 'Method', 'classification', 'Prior', 'uniform');

% 6. Save Artifacts for Zero-Latency Deployment
if ~exist('models', 'dir'), mkdir('models'); end
save('models/trainedModel.mat', 'MLModel', 'FeatureMu', 'FeatureSigma');
disp('Success! Custom model saved to models/trainedModel.mat. System is ready for live deployment.');