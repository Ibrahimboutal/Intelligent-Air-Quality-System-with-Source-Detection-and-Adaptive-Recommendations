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
            
            fprintf('Starting intelligent monitoring for %d samples...\n', numSamples);
            fprintf('------------------------------------------------------------\n');
            
            obj.CurrentStep = 0;
            obj.MaxSteps = numSamples;
            
            % Setup non-blocking timer
            obj.TimerObj = timer('ExecutionMode', 'fixedRate', 'Period', 1, ...
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
            
            % 2. Intelligence: Extract & Classify
            [source, advice] = obj.analyze(k);
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
        end
        
        function [pm25, pm10] = readSensor(obj, k)
            % Reads from SDS011 or generates intelligent mock data
            if obj.SimMode
                % Generate baseline
                pm25 = 12 + 2 * randn();
                pm10 = 15 + 3 * randn();
                
                % Inject simulated events for demonstration
                if k >= 20 && k <= 25
                    pm25 = pm25 + 30; % Dust spike
                    pm10 = pm10 + 35;
                elseif k >= 50 && k <= 60
                    pm25 = pm25 + 45; % Combustion
                    pm10 = pm10 + 50;
                elseif k >= 80 && k <= 90
                    pm25 = pm25 + 10; % Coarse particles
                    pm10 = pm10 + 40;
                end
            else
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
        
        function [source, advice] = analyze(obj, k)
            % Core AI / Intelligence logic
            pm25 = obj.PM25Data(k);
            pm10 = obj.PM10Data(k);
            
            % Feature Extraction
            ratio = pm25 / max(pm10, 0.1); % avoid div by zero
            if k > 1
                rate_of_change = pm25 - obj.PM25Data(k-1);
            else
                rate_of_change = 0;
            end
            
            % Smart Thresholding (dynamic based on moving window)
            if k > 5
                window = max(1, k-60):k-1;
                baseline = mean(obj.PM25Data(window), 'omitnan');
                threshold = baseline + 2*std(obj.PM25Data(window), 'omitnan');
                threshold = max(threshold, 15); % Minimum sensible threshold
            else
                threshold = 20;
            end
            
            % Classification Tree
            if pm25 > threshold
                if ratio > 0.8
                    source = "Combustion (cooking / smoke)";
                elseif rate_of_change > 10
                    source = "Dust / Sudden disturbance";
                elseif ratio < 0.5
                    source = "Coarse particles (outdoor dust)";
                else
                    source = "General pollution";
                end
            else
                source = "Clean";
            end
            
            % Adaptive Recommendations
            if pm25 < 15
                advice = "Air is clean";
            elseif pm25 < 35
                advice = "Moderate - consider ventilation";
            else
                advice = "Unhealthy - open window / reduce activity";
            end
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
    end
end
