function loadEnv(filename)
    % Parses a .env file and loads the variables into MATLAB's environment
    % using setenv().
    if nargin < 1
        filename = '.env';
    end
    
    if ~isfile(filename)
        warning('Environment file %s not found. Proceeding without it.', filename);
        return;
    end
    
    fid = fopen(filename, 'r');
    while ~feof(fid)
        line = strtrim(fgetl(fid));
        
        % Strip inline comments
        commentIdx = find(line == '#', 1);
        if ~isempty(commentIdx)
            line = strtrim(line(1:commentIdx-1));
        end
        
        % Skip empty lines
        if isempty(line)
            continue;
        end
        
        % Split by the first '='
        idx = find(line == '=', 1);
        if ~isempty(idx)
            key = strtrim(line(1:idx-1));
            val = strtrim(line(idx+1:end));
            
            % Remove quotes if present
            if (startsWith(val, '"') && endsWith(val, '"')) || ...
               (startsWith(val, '''') && endsWith(val, ''''))
                val = val(2:end-1);
            end
            
            setenv(key, val);
        end
    end
    fclose(fid);
end
