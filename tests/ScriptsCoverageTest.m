classdef ScriptsCoverageTest < matlab.unittest.TestCase
    % Unit tests to execute and cover standalone scripts
    
    properties
        LogDir
        MockFilePath
    end
    
    methods(TestMethodSetup)
        function setupData(testCase)
            % Ensure paths are set
            addpath(fullfile(fileparts(mfilename('fullpath')), '../src'));
            addpath(fullfile(fileparts(mfilename('fullpath')), '../scripts'));
            
            % Setup mock log directory
            testCase.LogDir = fullfile(fileparts(mfilename('fullpath')), '../logs');
            if ~exist(testCase.LogDir, 'dir'), mkdir(testCase.LogDir); end
            
            % Generate comprehensive mock data
            numSamples = 100;
            Time_s = (1:numSamples)';
            Timestamp = datestr(now - linspace(1, 0, numSamples)', 'yyyy-mm-dd HH:MM:SS');
            Timestamp = string(Timestamp);
            PM25 = rand(numSamples, 1) * 50 + 10;
            PM10 = PM25 * 1.2 + rand(numSamples, 1) * 10;
            pm25 = PM25; % Lowercase for scripts that use it
            pm10 = PM10;
            Features_7D = rand(numSamples, 7);
            Forecast_PM25 = PM25 + rand(numSamples, 1)*5;
            NoveltyScores = rand(numSamples, 1);
            NoveltyData = false(numSamples, 1);
            Source = repmat("Clean", numSamples, 1);
            Source(10:20) = "Traffic";
            Source(50:60) = "Dust";
            Advice = repmat("OK", numSamples, 1);
            
            T = table(Time_s, Timestamp, PM25, PM10, pm25, pm10, Features_7D, ...
                      Forecast_PM25, NoveltyScores, NoveltyData, Source, Advice);
            
            testCase.MockFilePath = fullfile(testCase.LogDir, 'AQI_Log_CoverageMock.csv');
            writetable(T, testCase.MockFilePath);
            
            % Set environment variables for socket dashboard
            setenv('MATLAB_PORT', '5055');
            setenv('PI_IP', '127.0.0.1');
        end
    end
    
    methods(TestMethodTeardown)
        function teardownData(testCase)
            % Clean up mock file
            if exist(testCase.MockFilePath, 'file')
                delete(testCase.MockFilePath);
            end
            % Close any left open figures
            close all force;
        end
    end
    
    methods(Test)
        function testAdaptiveIntelligenceSystem(testCase)
            run('adaptive_intelligence_system.m');
            testCase.verifyTrue(true);
        end
        
        function testBacktestForecaster(testCase)
            run('backtest_forecaster.m');
            testCase.verifyTrue(true);
        end
        
        function testCompareFilterPerformance(testCase)
            run('compare_filter_performance.m');
            testCase.verifyTrue(true);
        end
        
        function testCrossValidateSystem(testCase)
            run('cross_validate_system.m');
            testCase.verifyTrue(true);
        end
        
        function testDetectNovelty(testCase)
            run('detect_novelty.m');
            testCase.verifyTrue(true);
        end
        
        function testEvaluateModelPerformance(testCase)
            run('evaluate_model_performance.m');
            testCase.verifyTrue(true);
        end
        
        function testExplainModel(testCase)
            run('explain_model.m');
            testCase.verifyTrue(true);
        end
        
        function testFeatureEngineering(testCase)
            run('feature_engineering.m');
            testCase.verifyTrue(true);
        end
        
        function testSourceDetectionML(testCase)
            run('source_detection_ml.m');
            testCase.verifyTrue(true);
        end
        
        function testTrainFromRawLogs(testCase)
            run('train_from_raw_logs.m');
            testCase.verifyTrue(true);
        end
        
        function testLiveIntelligenceDashboard(testCase)
            % The script uses an infinite loop "while ishghandle(fig)".
            % We spawn a timer to close the figure after 1 second.
            t = timer('ExecutionMode', 'singleShot', 'StartDelay', 1.5, ...
                      'TimerFcn', @(~,~) close('all', 'force'));
            start(t);
            
            % We also need to set pollInterval to a small value so it doesn't pause for 5s
            % The script has `pollInterval = 5;`. 
            % Since it's a script, we can't inject variables before it runs unless we overwrite it.
            % However, the timer will fire during the pause(5).
            run('live_intelligence_dashboard.m');
            
            if isvalid(t), delete(t); end
            testCase.verifyTrue(true);
        end
        
        function testSocketIntelligenceDashboard(testCase)
            % The script uses an infinite loop "while ishghandle(fig)".
            t = timer('ExecutionMode', 'singleShot', 'StartDelay', 2.0, ...
                      'TimerFcn', @(~,~) close('all', 'force'));
            start(t);
            
            % Optional: We could spawn a background client to connect and send data
            client_t = timer('ExecutionMode', 'singleShot', 'StartDelay', 0.5, ...
                             'TimerFcn', @(~,~) ScriptsCoverageTest.sendMockPacket('127.0.0.1', 5055));
            start(client_t);
            
            run('socket_intelligence_dashboard.m');
            
            if isvalid(t), delete(t); end
            if isvalid(client_t), delete(client_t); end
            testCase.verifyTrue(true);
        end
    end
    
    methods(Static)
        function sendMockPacket(ip, port)
            try
                client = tcpclient(ip, port, "Timeout", 1);
                packet = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                                'pm25', 25.5, ...
                                'pm10', 30.2);
                write(client, uint8([jsonencode(packet), newline]));
                pause(0.1);
                clear client;
            catch
                % Ignore connection errors in test background thread
            end
        end
    end
end
