classdef AirQualitySystem < handle
    % AirQualitySystem - Intelligent Air Quality Monitoring with Source Detection
    % Handles data acquisition (via Raspberry Pi + SDS011 or Simulation),
    % feature extraction, source classification, and real-time visualization.
    
    properties
        PiIPAddress     % Raspberry Pi IP Address
        PiUsername      % Raspberry Pi Username
        PiPassword      % Raspberry Pi Password
        Port            % Serial Port (e.g., '/dev/ttyUSB0')
        BaudRate        % Serial Baud Rate (default 9600 for SDS011)
        SimMode         % Boolean flag to run simulation without hardware
        
        % Data buffers
        TimeArray
        PM25Data
        PM10Data
        SourceData
        AdviceData
        % Execution state
        CurrentStep
        MaxSteps
        TimerObj
        
        % Data Science & Intelligence objects
        MLModel
        FeatureMatrix
        ForecastData
        FeatureMu       % Mean for Z-score scaling
        FeatureSigma    % StdDev for Z-score scaling
        HW_Level        % Recursive Holt-Winters Level
        HW_Trend        % Recursive Holt-Winters Trend
        
        
        % Hardware objects
        PiObj
        SerialDevObj
        
        % UI objects
        FigureHandle
        PlotLine25
        PlotLine10
        ScatterPlot
        AnnotationText
    end
    
    methods
        function obj = AirQualitySystem(ip, user, pass, port, baud, simMode)
            % Constructor
            if nargin < 6
                simMode = false;
            end
            obj.PiIPAddress = ip;
            obj.PiUsername = user;
            obj.PiPassword = pass;
            obj.Port = port;
            obj.BaudRate = baud;
            obj.SimMode = simMode;
            
            % Initialize empty buffers
            obj.TimeArray = [];
            obj.PM25Data = [];
            obj.PM10Data = [];
            obj.SourceData = strings(0);
            obj.AdviceData = strings(0);
            obj.FeatureMatrix = [];
            obj.ForecastData = [];
            
            % Initialize Recursive State
            obj.HW_Level = NaN;
            obj.HW_Trend = 0;
            
            % Load Pre-trained Machine Learning Module (Zero-latency startup)
            modelPath = fullfile('models', 'trainedModel.mat');
            if exist(modelPath, 'file')
                try
                    data = load(modelPath);
                    obj.MLModel = data.MLModel;
                    obj.FeatureMu = data.FeatureMu;
                    obj.FeatureSigma = data.FeatureSigma;
                    fprintf('Pre-trained ML model loaded successfully (Zero-latency startup).\n');
                catch ME
                    fprintf('Failed to load pre-trained model: %s. Falling back to heuristics.\n', ME.message);
                    obj.MLModel = [];
                end
            else
                fprintf('Trained model not found at %s. Falling back to heuristics.\n', modelPath);
                obj.MLModel = [];
            end
        end
        
        function delete(obj)
            % Destructor to clean up hardware connections
            if ~isempty(obj.SerialDevObj)
                delete(obj.SerialDevObj);
            end
            if ~isempty(obj.PiObj)
                delete(obj.PiObj);
            end
        end
        
        function connect(obj)
            % Establish connection to hardware if not in simulation mode
            if obj.SimMode
                fprintf('Running in SIMULATION MODE. No hardware connection required.\n');
            else
                fprintf('Connecting to Raspberry Pi at %s...\n', obj.PiIPAddress);
                try
                    obj.PiObj = raspi(obj.PiIPAddress, obj.PiUsername, obj.PiPassword);
                    fprintf('Connecting to Nova PM SDS011 on %s...\n', obj.Port);
                    obj.SerialDevObj = serialdev(obj.PiObj, obj.Port, obj.BaudRate);
                    fprintf('Hardware connection established successfully.\n');
                catch ME
                    warning('Failed to connect to hardware: %s', ME.message);
                    fprintf('Falling back to SIMULATION MODE.\n');
                    obj.SimMode = true;
                end
            end
        end
        
        function run(obj, numSamples)
            % Main execution loop for real-time monitoring
            obj.setupDashboard();
            
            % Preallocate arrays for performance
            obj.TimeArray = NaN(1, numSamples);
            obj.PM25Data = NaN(1, numSamples);
            obj.PM10Data = NaN(1, numSamples);
            obj.SourceData = strings(1, numSamples);
            obj.AdviceData = strings(1, numSamples);
            obj.FeatureMatrix = NaN(numSamples, 7);
            obj.ForecastData = NaN(1, numSamples);
            
            fprintf('Starting intelligent monitoring for %d samples...\n', numSamples);
            fprintf('------------------------------------------------------------\n');
            
            obj.CurrentStep = 0;
            obj.MaxSteps = numSamples;
            
            % Setup non-blocking timer
            obj.TimerObj = timer('ExecutionMode', 'fixedRate', 'Period', 1, ...
                'TasksToExecute', numSamples, ...  
                'TimerFcn', @(~,~) obj.timerCallback(), ...
                'StopFcn', @(~,~) disp('Monitoring session complete.'));
            
            % Cleanup hook to stop timer if user interrupts execution
            cleanupTimerHook = onCleanup(@() obj.cleanupTimer());
            
            start(obj.TimerObj);
            wait(obj.TimerObj); % Wait blocks script progression but frees UI thread
        end
        
        function timerCallback(obj)
            % Executed every second by the timer
            k = obj.CurrentStep + 1;
            obj.CurrentStep = k;
            
            % 1. Data Acquisition
            [pm25, pm10] = obj.readSensor(k);
            
            % Update buffers
            obj.TimeArray(k) = k;
            obj.PM25Data(k) = pm25;
            obj.PM10Data(k) = pm10;
            
            % 2. Intelligence: Advanced Features, Forecast, & Classify
            features = obj.extractFeatures(k);
            obj.FeatureMatrix(k, :) = features;
            
            predictedPM25 = obj.forecastAQI(k);
            obj.ForecastData(k) = predictedPM25;
            
            [source, advice] = obj.analyze(k, features, predictedPM25);
            obj.SourceData(k) = source;
            obj.AdviceData(k) = advice;
            
            % 3. Visualization
            obj.updateDashboard(k);
            
            % Print to console if event detected
            if source ~= "Clean"
                fprintf('Time %3d | PM2.5=%5.1f | Source: %-30s | Advice: %s\n', ...
                    k, pm25, source, advice);
            end
            
            % Check exit conditions
            if k >= obj.MaxSteps || ~ishghandle(obj.FigureHandle)
                if ~ishghandle(obj.FigureHandle)
                    fprintf('Dashboard closed. Stopping monitoring.\n');
                end
                stop(obj.TimerObj);
            end
        end
        
        function cleanupTimer(obj)
            if ~isempty(obj.TimerObj) && isvalid(obj.TimerObj)
                if strcmp(obj.TimerObj.Running, 'on')
                    stop(obj.TimerObj);
                end
                delete(obj.TimerObj);
            end
            
            % --- Persistent Data Logging Pipeline ---
            fprintf('\nInitiating Persistent Data Logging...\n');
            try
                if ~exist('logs', 'dir')
                    mkdir('logs');
                end
                
                % Slice valid data
                validIdx = ~isnan(obj.TimeArray);
                if any(validIdx)
                    T = table(obj.TimeArray(validIdx)', obj.PM25Data(validIdx)', obj.PM10Data(validIdx)', ...
                              obj.FeatureMatrix(validIdx, :), obj.ForecastData(validIdx)', ...
                              obj.SourceData(validIdx)', obj.AdviceData(validIdx)', ...
                              'VariableNames', {'Time_s', 'PM25', 'PM10', 'Features_7D', 'Forecast_PM25', 'Source', 'Advice'});
                    
                    filename = fullfile('logs', sprintf('AQI_Log_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
                    writetable(T, filename);
                    fprintf('Successfully saved %d records to %s\n', sum(validIdx), filename);
                else
                    fprintf('No valid data collected to save.\n');
                end
            catch ME
                fprintf(2, 'Failed to save log data: %s\n', ME.message);
            end
        end
        
        function [pm25, pm10] = readSensor(obj, k)
            % Reads from SDS011 or generates intelligent mock data
            if obj.SimMode
                % Generate baseline
                pm25 = 12 + 2 * randn();
                pm10 = 15 + 3 * randn();
                
                % Inject simulated events cyclically (every 200 samples)
                % This guarantees events appear in BOTH train and test splits
                cycle = mod(k, 200);
                
                if cycle >= 20 && cycle <= 30
                    pm25 = pm25 + 30; % Dust spike
                    pm10 = pm10 + 35;
                elseif cycle >= 80 && cycle <= 100
                    pm25 = pm25 + 45; % Combustion
                    pm10 = pm10 + 50;
                elseif cycle >= 150 && cycle <= 165
                    pm25 = pm25 + 10; % Coarse particles
                    pm10 = pm10 + 40;
                end
            else
            % ... [keep the physical hardware read logic below exactly the same]
                % Read physical sensor with synchronization
                try
                    max_retries = 20;
                    synced = false;
                    for r = 1:max_retries
                        b = read(obj.SerialDevObj, 1);
                        if ~isempty(b) && b(1) == 170
                            synced = true;
                            break;
                        end
                    end
                    
                    if synced
                        rest = read(obj.SerialDevObj, 9);
                        data = [170, rest];
                        if length(data) == 10 && data(10) == 171
                            pm25 = ((double(data(4)) * 256) + double(data(3))) / 10;
                            pm10 = ((double(data(6)) * 256) + double(data(5))) / 10;
                        else
                            error('Invalid frame tail');
                        end
                    else
                        error('Could not sync to frame header');
                    end
                catch ME
                     fprintf(2, 'Hardware read error at step %d: %s\n', k, ME.message);
                     if k > 1
                        pm25 = obj.PM25Data(k-1);
                        pm10 = obj.PM10Data(k-1);
                     else
                        pm25 = NaN; pm10 = NaN;
                     end
                end
            end
            
            % Enforce non-negativity to prevent sensor glitches from skewing ratios
            pm25 = max(0, pm25);
            pm10 = max(0, pm10);
        end
        
        function [source, advice] = analyze(obj, k, features, predictedPM25)
            % Core AI / Intelligence logic
            pm25 = obj.PM25Data(k);
            
            % Smart Thresholding (dynamic based on moving window)
            if k > 5
                window = max(1, k-60):k-1;
                baseline = mean(obj.PM25Data(window), 'omitnan');
                threshold = baseline + 2*std(obj.PM25Data(window), 'omitnan');
                threshold = max(threshold, 15); % Minimum sensible threshold
            else
                threshold = 20;
            end
            
            % --- Dynamic Heuristics (Fix: Avoid Hardcoded Thresholds) ---
            if pm25 > threshold
                if ~isempty(obj.MLModel)
                    % Use trained Random Forest model
                    predSource = predict(obj.MLModel, features);
                    if iscell(predSource)
                        source = string(predSource{1});
                    elseif iscategorical(predSource)
                        source = string(predSource);
                    else
                        source = string(predSource);
                    end
                else
                    % Fallback Dynamic Heuristics
                    ratio = features(1);
                    roc = features(2);
                    
                    % Calculate environmental baseline for dynamic scaling
                    history = obj.PM25Data(max(1, k-300):max(1, k-1));
                    valid_history = history(~isnan(history));
                    
                    if isempty(valid_history)
                        env_median = 10;
                        env_mad = 5;
                    else
                        env_median = median(valid_history);
                        env_mad = mad(valid_history, 1);
                    end
                    
                    if env_mad == 0, env_mad = 5; end
                    
                    % Heuristic decision logic scaled by environment
                    if ratio > 0.8
                        source = "Combustion (cooking / smoke)";
                    elseif roc > (env_median + 2*env_mad)
                        source = "Dust / Sudden disturbance";
                    elseif ratio < 0.5
                        source = "Coarse particles (outdoor dust)";
                    else
                        source = "General pollution";
                    end
                end
            else
                source = "Clean";
            end
            
            % --- Predictive Recommendations ---
            if pm25 >= 35
                advice = "Unhealthy - open window / reduce activity";
            elseif predictedPM25 >= 35
                advice = "PRE-EMPTIVE WARNING: Forecasted Spike - Close Windows Now";
            elseif pm25 >= 15
                advice = "Moderate - consider ventilation";
            elseif predictedPM25 >= 15
                advice = "Forecasted Moderate - monitor conditions";
            else
                advice = "Air is clean";
            end
        end
        
        function features = extractFeatures(obj, k)
            % Extract a 7D feature vector for Machine Learning
            pm25 = obj.PM25Data(k);
            pm10 = max(obj.PM10Data(k), 0.1);
            
            % 1. Ratio
            ratio = pm25 / pm10;
            
            % 2. Rate of Change
            if k > 1
                roc = pm25 - obj.PM25Data(k-1);
            else
                roc = 0;
            end
            
            % Moving Windows
            w5 = max(1, k-5):k;
            w15 = max(1, k-15):k;
            
            % 3 & 4. Moving Averages
            ma5 = mean(obj.PM25Data(w5), 'omitnan');
            ma15 = mean(obj.PM25Data(w15), 'omitnan');
            
            % 5. Volatility (Std Dev)
            std5 = std(obj.PM25Data(w5), 'omitnan');
            if isnan(std5), std5 = 0; end
            
            % 6 & 7. Skewness and Kurtosis
            if length(w15) >= 4
                skew15 = skewness(obj.PM25Data(w15), 1);
                kurt15 = kurtosis(obj.PM25Data(w15), 1);
            else
                skew15 = 0;
                kurt15 = 3; % Normal dist kurtosis
            end
            
            rawFeatures = [ratio, roc, ma5, ma15, std5, skew15, kurt15];
            
            % Apply Z-score Normalization if scaling parameters exist
            if ~isempty(obj.FeatureMu) && ~isempty(obj.FeatureSigma)
                features = (rawFeatures - obj.FeatureMu) ./ obj.FeatureSigma;
            else
                features = rawFeatures; % Unscaled fallback
            end
        end
        
        function predictedPM25 = forecastAQI(obj, k)
            % Time-Series Forecasting using Recursive Holt-Winters (O(1) complexity)
            horizon = 15; 
            y = obj.PM25Data(k);
            
            % Hyperparameters
            alpha = 0.5; % Level smoothing
            beta  = 0.3; % Trend smoothing
            phi   = 0.98; % Dampening factor (Fix: Prevent State Drift)
            
            if k == 1 || isnan(obj.HW_Level)
                % Initialization
                obj.HW_Level = y;
                obj.HW_Trend = 0;
                predictedPM25 = y;
            else
                % Recursive Update with Trend Dampening
                L_prev = obj.HW_Level;
                T_prev = obj.HW_Trend;
                
                L_new = alpha * y + (1 - alpha) * (L_prev + phi * T_prev);
                T_new = beta * (L_new - L_prev) + (1 - beta) * phi * T_prev;
                
                % Store State
                obj.HW_Level = L_new;
                obj.HW_Trend = T_new;
                
                % Multi-step Forecast with Dampening
                % Forecast = L + (phi^1 + phi^2 + ... + phi^h) * T
                steps = 1:horizon;
                predictedPM25 = L_new + sum(phi.^steps) * T_new;
            end
            
            predictedPM25 = max(0, predictedPM25); % Enforce non-negativity
        end
        
        function runFSDAAnalysis(obj)
            % Post-monitoring robust analysis using FSDA (Flexible Statistics and Data Analysis)
            % This method performs robust multivariate outlier detection to find hidden pollution anomalies.
            
            fprintf('\n--- Starting FSDA Robust Analysis ---\n');
            if isempty(obj.PM25Data) || length(obj.PM25Data) < 10
                fprintf('Not enough data to run FSDA analysis.\n');
                return;
            end
            
            try
                % Prepare multivariate data matrix: [PM2.5, PM10]
                Y = [obj.PM25Data', obj.PM10Data'];
                
                % Check if FSDA is installed by looking for FSM function
                if exist('FSM', 'file') == 2
                    % Use FSM (Forward Search for Multivariate Outliers)
                    fprintf('Running FSM (Forward Search for Multivariate data)...\n');
                    out = FSM(Y, 'plots', 0, 'msg', 0);
                    outliersIdx = out.outliers;
                    fprintf('FSDA detected %d robust anomalies in the data stream.\n', length(outliersIdx));
                    figTitle = 'FSDA Bivariate Outlier Detection (PM_{2.5} vs PM_{10})';
                else
                    fprintf('FSDA toolbox not found. Falling back to robust Mahalanobis distance.\n');
                    % Fallback using median and MAD for robust Mahalanobis
                    medY = median(Y, 1, 'omitnan');
                    madY = mad(Y, 1);
                    madY(madY == 0) = 1e-6; % Prevent division by zero
                    
                    % Simple standardized robust distance
                    dist = sum(((Y - medY) ./ madY).^2, 2);
                    chi2_thresh = chi2inv(0.975, 2); % 97.5% confidence for 2 DoF
                    outliersIdx = find(dist > chi2_thresh);
                    fprintf('Mahalanobis fallback detected %d anomalies.\n', length(outliersIdx));
                    figTitle = 'Robust Mahalanobis Outlier Detection (PM_{2.5} vs PM_{10})';
                end
                
                % Add a new figure summarizing the results
                figure('Name', 'Robust Analysis Results', 'Color', 'w');
                scatter(Y(:,1), Y(:,2), 50, 'b', 'filled'); hold on;
                if ~isempty(outliersIdx)
                    scatter(Y(outliersIdx, 1), Y(outliersIdx, 2), 100, 'r', 'filled', 'MarkerEdgeColor', 'k');
                    legend('Normal Measurements', 'Detected Anomalies', 'Location', 'best');
                else
                    legend('Measurements', 'Location', 'best');
                end
                title(figTitle, 'FontWeight', 'bold');
                xlabel('PM2.5 Concentration (\mu g / m^3)');
                ylabel('PM10 Concentration (\mu g / m^3)');
                grid on;
                
            catch ME
                fprintf('An error occurred during FSDA analysis: %s\n', ME.message);
            end
        end
        
        function setupDashboard(obj)
            % Initializes the real-time plot
            if ~isempty(obj.FigureHandle) && ishghandle(obj.FigureHandle)
                close(obj.FigureHandle);
            end
            
            obj.FigureHandle = figure('Name', 'Intelligent Air Quality Monitor', ...
                                      'Position', [100, 100, 900, 500], ...
                                      'NumberTitle', 'off', 'Color', 'w');
            
            % Main axes
            ax = axes('Parent', obj.FigureHandle);
            hold(ax, 'on');
            grid(ax, 'on');
            
            % Lines
            obj.PlotLine25 = plot(ax, NaN, NaN, 'b-', 'LineWidth', 2, 'DisplayName', 'PM2.5');
            obj.PlotLine10 = plot(ax, NaN, NaN, 'g--', 'LineWidth', 1.5, 'DisplayName', 'PM10');
            obj.ScatterPlot = scatter(ax, NaN, NaN, 100, 'r', 'filled', 'DisplayName', 'Detected Events');
            
            title(ax, 'Real-Time Air Quality & Source Detection', 'FontSize', 14, 'FontWeight', 'bold');
            xlabel(ax, 'Time (seconds)', 'FontSize', 12);
            ylabel(ax, 'Concentration (\mu g / m^3)', 'FontSize', 12);
            legend(ax, 'Location', 'northwest', 'FontSize', 11);
            
            % Status Annotation Panel
            obj.AnnotationText = annotation('textbox', [0.15, 0.75, 0.35, 0.15], ...
                'String', 'Initializing...', 'FitBoxToText', 'on', ...
                'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 11, ...
                'Margin', 10);
        end
        
        function updateDashboard(obj, k)
            % Updates plot with new data safely
            if ~ishghandle(obj.FigureHandle)
                return; % Stop updating if figure was closed
            end
            
            % Update Lines
            set(obj.PlotLine25, 'XData', obj.TimeArray(1:k), 'YData', obj.PM25Data(1:k));
            set(obj.PlotLine10, 'XData', obj.TimeArray(1:k), 'YData', obj.PM10Data(1:k));
            
            % Find events
            validSrc = obj.SourceData(1:k);
            eventIdx = find(validSrc ~= "Clean" & validSrc ~= "");
            if ~isempty(eventIdx)
                set(obj.ScatterPlot, 'XData', obj.TimeArray(eventIdx), 'YData', obj.PM25Data(eventIdx));
            else
                set(obj.ScatterPlot, 'XData', NaN, 'YData', NaN);
            end
            
            % Auto scale X axis
            ax = obj.PlotLine25.Parent;
            windowSize = 60;
            currentMax = obj.TimeArray(k);
            if isempty(currentMax) || isnan(currentMax), currentMax = 1; end
            xlim(ax, [max(1, currentMax - windowSize), max(windowSize, currentMax + 5)]);
            
            % Auto scale Y axis
            yMax = max([obj.PM10Data(1:k), 50], [], 'omitnan') * 1.2;
            ylim(ax, [0, yMax]);
            
            % Update Status Text
            latestSrc = obj.SourceData(k);
            latestAdv = obj.AdviceData(k);
            statusStr = sprintf('CURRENT STATUS\nSource: %s\nAdvice: %s', latestSrc, latestAdv);
            set(obj.AnnotationText, 'String', statusStr);
            
            % Highlight red if unhealthy
            if latestSrc ~= "Clean"
                set(obj.AnnotationText, 'BackgroundColor', [1 0.8 0.8]); % Light Red
            else
                set(obj.AnnotationText, 'BackgroundColor', [0.9 1 0.9]); % Light Green
            end
            
            drawnow;
        end
        function [X, y] = getTrainingData(obj)
            % Returns features (X) and labels (y) from current session data
            validIdx = ~isnan(obj.TimeArray) & (obj.SourceData ~= "");
            X = obj.FeatureMatrix(validIdx, :);
            y = categorical(obj.SourceData(validIdx)');
        end
    end
end
