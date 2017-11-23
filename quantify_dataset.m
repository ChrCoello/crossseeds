function [output_json,study_info_json,sp_json] = quantify_dataset(varargin)
%
%
%
% Parse inputs
if nargin==0
    [file_name,path_name] = uigetfile('*.json','Please provide with the JSON file containing the study information (i.e study_info.json)');
    study_info_json = fullfile(path_name,file_name);
elseif nargin==1
    study_info_json = varargin{1};
else
    error('Too many inputs');
end

% Check that the JSONlab is in the path and do something about it
checkJson();

%%% Parsing inputs
% Open the study info JSON
if exist(study_info_json,'file')
    study_info = loadjson(study_info_json);
else
    error('quantify_dataset:StudyInfoNotFound',['Filename %s ',...
        'was not found. Please verify the path to the study info JSON file'],...
        study_info_json);
end
%%% Parsing required name/value pair from JSON
study_name     = validate_input(study_info,'study_name');
slice_dir      = validate_input(study_info,'slice_dir','dir');
atlas_dir      = validate_input(study_info,'atlas_dir','dir');
atlas_name     = validate_input(study_info,'atlas_name');
atlas_lbl_file = validate_input(study_info,'atlas_lbl_file','file');
seg_dir        = validate_input(study_info,'seg_dir','dir');
obj_lbl        = validate_input(study_info,'obj_lbl');
output_dir     = validate_input(study_info,'output_dir','dir');
atlas_xml_file = validate_input(study_info,'atlas_xml_file','file');

%%% Parsing atlas list JSON
if exist('atlas_list.json','file')
    atlas_list   = loadjson('atlas_list.json');
    atlas_struct = [atlas_list.atlases{:}];
    curr_atlas   = atlas_struct(strcmp({atlas_struct(:).name},atlas_name));
else
    error('quantify_dataset:NoAtlasInfoFound',['The file containing',...
        ' the information about the atlases could not be found. It should',... 
        ' be placed in the same folder as the Matlab scripts.']) 
end

%%% Get info on system and start filling the output structure GlobalStats
tic;
sysinfo.username = getenv('username');
% Computer type
sysinfo.platformUsed  = computer;
% OS used
sysinfo.osType        = system_dependent('getos');
% MATLAB
sysinfo.matlabVersion = version;
%
GlobalStats.date_analysis = datestr(now);
GlobalStats.system_info = sysinfo;
%
SPcoord.type = 'FeatureCollection';
SPcoord.features = [];
% To be modified if rat or mouse 10um
GlobalStats.atlas = curr_atlas;

%%% Get the content of the segmentation directory and keep only images
seg_dir_ctn_raw = dir(seg_dir);
seg_dir_ctn = keep_images(seg_dir_ctn_raw);
%
n_slice = length(seg_dir_ctn);
GlobalStats.n_sections = n_slice;
GlobalStats.n_objects  = NaN;
GlobalStats.n_regions  = NaN;
%
fprintf(1,'\nTotal number of section detected to analyse: %d\n',n_slice);

%%% Get the content of te atlas directory
atlas_dir_ctn = dir(atlas_dir);
atlas_dir_ctn = atlas_dir_ctn(~[atlas_dir_ctn(:).isdir]);

%%% Get the content of the section directory
slice_dir_ctn_raw = dir(slice_dir);
slice_dir_ctn     = keep_images(slice_dir_ctn_raw);

%%% Coordinates
if ~isempty(atlas_xml_file) && exist(atlas_xml_file,'file')
    atlas_json_fn    = xmlcoord2jsonmat(atlas_xml_file);
    atlas_coord_json = loadjson(atlas_json_fn);
    sections_coord   = [atlas_coord_json.slice{:}];
else
    sections_coord   = [];
end

%%% Init for loop and loop on all the images
n_objects = 0;
n_regions = 0;
output_dir_xls = fullfile(output_dir,'excel');
if ~exist(output_dir_xls,'dir')
    mkdir(output_dir_xls);
end
output_xls_obj_ind = fullfile(output_dir_xls,[study_name '_objects_ind.xlsx']);
output_xls_reg_ind = fullfile(output_dir_xls,[study_name '_regions_ind.xlsx']);
%
GlobalStats.objects = [];
GlobalStats.regions = [];
GlobalStats.study_info = study_info;
%
for iS = 1:n_slice
    %
    fprintf(1,' -- Analyzing slice #%d / %d\n',iS,n_slice);
    %%% Get
    seg_name_orig = seg_dir_ctn(iS).name;
    %%% Remove Object Prediction from the file name if found
    if strfind(seg_name_orig,'Object Prediction')
        seg_name = seg_name_orig(1:strfind(seg_name_orig,'Object Prediction')-2);
    else
        seg_name = seg_name_orig;
    end
    %%% Get the index of the image: s followed by three digits
    idx_str_idx = regexp(seg_name_orig,'_s\d','once');
    if isempty(idx_str_idx)
        error('quantify_dataset:StandardNamingNotFound',...
            ['The pattern ''_sXXX'' was not found in the segmentation image',...
            ' filename %s. Please read README file for more info on standard naming.'],...
            seg_name_orig);
    end
    seg_id = seg_name(idx_str_idx+2:end);
    %
    seg_name_file = fullfile(seg_dir,seg_name_orig);
    %%% Atlas
    atlas_slices = atlas_dir_ctn(~cellfun('isempty',strfind({atlas_dir_ctn(:).name},seg_id)));
    %
    atlas_name = atlas_slices(~cellfun('isempty',strfind({atlas_slices(:).name},'.bin'))).name;
    atlas_name_file = fullfile(atlas_dir,atlas_name);
    %%% Section
    slice_name = slice_dir_ctn(~cellfun('isempty',strfind({slice_dir_ctn(:).name},seg_id))).name;
    slice_name_file = fullfile(slice_dir,slice_name);

    %%% Transformation vectors and matrix
    anchoring_data = struct('pixel_to_atlas_mat',[],...
        'o_vec',[],...
        'u_vec',[],...
        'v_vec',[]);
    if ~isempty(sections_coord)
        idx_seg_mat = ~cellfun('isempty',...
            strfind({sections_coord(:).filename},seg_id));
        anchoring_data.pixel_to_atlas_mat = sections_coord(idx_seg_mat).transf_mat;
        anchoring_data.o_vec = [sections_coord(idx_seg_mat).ox,...
            sections_coord(idx_seg_mat).oy,...
            sections_coord(idx_seg_mat).oz];
        anchoring_data.u_vec = [sections_coord(idx_seg_mat).ux,...
            sections_coord(idx_seg_mat).uy,...
            sections_coord(idx_seg_mat).uz];
        anchoring_data.v_vec = [sections_coord(idx_seg_mat).vx,...
            sections_coord(idx_seg_mat).vy,...
            sections_coord(idx_seg_mat).vz];
    end
        

    %%% we have everything we need: calling quantify_single_section
    curr_atlas.atlas_lbl_file = atlas_lbl_file;
    [obj_stats,reg_stats,sp_stats] = quantify_single_section(atlas_name_file,...
        seg_name_file,...
        slice_name_file,...
        output_dir,...
        obj_lbl,...
        curr_atlas,...
        anchoring_data);

    %%% Concatenate the individual objects with the ones from preivous
    % sections
    n_objects =+ length(obj_stats);
    n_regions =+ length(reg_stats);
    %
    GlobalStats.objects = vertcat(GlobalStats.objects,obj_stats);
    GlobalStats.regions = vertcat(GlobalStats.regions,reg_stats);
    SPcoord.features = vertcat(SPcoord.features,sp_stats);
    %as excel
    objects = struct2table(obj_stats);
    regions = struct2table(reg_stats);
    %
    warning('off','MATLAB:xlswrite:AddSheet');
    writetable(objects,output_xls_obj_ind,'Sheet',seg_id);
    writetable(regions,output_xls_reg_ind,'Sheet',seg_id);
    %
    fprintf(' -- Analyzing slice #%d / %d -- done\n',iS,n_slice);
    %Clear metadata not to mix information between sections
    clear metadata
end

%%% Write output as json
GlobalStats.n_objects = n_objects;
GlobalStats.n_regions = n_regions;
GlobalStats.curr_atlas = curr_atlas;
%objects
output_json = fullfile(output_dir,[study_name '_objects.json']);
savejson('',GlobalStats,output_json);
%spatial data in a standard way
output_dir_spcoord = fullfile(output_dir,'sp_query');
if ~exist(output_dir_spcoord,'dir')
    mkdir(output_dir_spcoord);
end
sp_json = fullfile(output_dir_spcoord,[study_name '_spatial_data.json']);
savejson('',SPcoord,sp_json);

%%% Write output as excel through table
objects = struct2table(GlobalStats.objects);
regions = struct2table(GlobalStats.regions);
%
output_xls_obj = fullfile(output_dir_xls,[study_name '_objects.xlsx']);
output_xls_reg = fullfile(output_dir_xls,[study_name '_regions.xlsx']);
%
writetable(objects,output_xls_obj);
writetable(regions,output_xls_reg);
%
t_p = toc;
fprintf(1,'\nAnalysis completed in %.0f seconds\n',t_p);
return



% function struct_txt = load_txt(filename, startRow, endRow)
% %IMPORTFILE Import text from the automatically generated text file that
% %contains the resolution of the original file
% %
% % Example:
% %   tg2576m2871D1s054 = importfile('tg2576_m287_1D1_s054.txt', 2, 7);
% %
% %    See also TEXTSCAN.
% % Auto-generated by MATLAB on 2017/08/15 11:39:55
% 
% % Initialize variables.
% delimiter = ' ';
% if nargin<=2
%     startRow = 2;
%     endRow = 7;
% end
% 
% % Read columns of data as text:
% % For more information, see the TEXTSCAN documentation.
% formatSpec = '%s%s%s%s%s%s%[^\n\r]';
% 
% % Open the text file.
% fileID = fopen(filename,'r');
% 
% % Read columns of data according to the format.
% % This call is based on the structure of the file used to generate this
% % code. If an error occurs for a different file, try regenerating the code
% % from the Import Tool.
% dataArray = textscan(fileID, formatSpec, endRow(1)-startRow(1)+1, 'Delimiter', delimiter, 'MultipleDelimsAsOne', true, 'HeaderLines', startRow(1)-1, 'ReturnOnError', false, 'EndOfLine', '\r\n');
% for block=2:length(startRow)
%     frewind(fileID);
%     dataArrayBlock = textscan(fileID, formatSpec, endRow(block)-startRow(block)+1, 'Delimiter', delimiter, 'MultipleDelimsAsOne', true, 'HeaderLines', startRow(block)-1, 'ReturnOnError', false, 'EndOfLine', '\r\n');
%     for col=1:length(dataArray)
%         dataArray{col} = [dataArray{col};dataArrayBlock{col}];
%     end
% end
% 
% % Close the text file.
% fclose(fileID);
% 
% % Convert the contents of columns containing numeric text to numbers.
% % Replace non-numeric text with NaN.
% raw = repmat({''},length(dataArray{1}),length(dataArray)-1);
% for col=1:length(dataArray)-1
%     raw(1:length(dataArray{col}),col) = dataArray{col};
% end
% numericData = NaN(size(dataArray{1},1),size(dataArray,2));
% 
% % Converts text in the input cell array to numbers. Replaced non-numeric
% % text with NaN.
% rawData = dataArray{3};
% for row=1:size(rawData, 1)
%     % Create a regular expression to detect and remove non-numeric prefixes and
%     % suffixes.
%     regexstr = '(?<prefix>.*?)(?<numbers>([-]*(\d+[\,]*)+[\.]{0,1}\d*[eEdD]{0,1}[-+]*\d*[i]{0,1})|([-]*(\d+[\,]*)*[\.]{1,1}\d+[eEdD]{0,1}[-+]*\d*[i]{0,1}))(?<suffix>.*)';
%     try
%         result = regexp(rawData{row}, regexstr, 'names');
%         numbers = result.numbers;
% 
%         % Detected commas in non-thousand locations.
%         invalidThousandsSeparator = false;
%         if any(numbers==',')
%             thousandsRegExp = '^\d+?(\,\d{3})*\.{0,1}\d*$';
%             if isempty(regexp(numbers, thousandsRegExp, 'once'))
%                 numbers = NaN;
%                 invalidThousandsSeparator = true;
%             end
%         end
%         % Convert numeric text to numbers.
%         if ~invalidThousandsSeparator
%             numbers = textscan(strrep(numbers, ',', ''), '%f');
%             numericData(row, 3) = numbers{1};
%             raw{row, 3} = numbers{1};
%         end
%     catch me
%     end
% end
% 
% %
% struct_txt = raw;
% 
% return

% function outData = unit_convert(inData,inUnits,outUnits)
% %
% conversionFactors = {
%     'length',...
%     {'m','cm','Centimeter','mm','um','nm','km','in','ft','yd','mile','AU'},...
%     [1 1e-2 1e-2 1e-3 1e-6 1e-9 1e3 2.54e-2 12*2.54e-2 36*2.54e-2 1760*36*2.54e-2 1.49598e11]};
% 
% inUnits  = strtrim(inUnits);
% outUnits = strtrim(outUnits);
% %
% if ~ismember(inUnits,conversionFactors{2}) || ~ismember(outUnits,conversionFactors{2})
%     error('UnitConvert:IncompatibleUnits','%s%s%s%s%s','Specified input (',inUnits,') and output (',outUnits,') units are incompatible.')
% end
% %
% factorInToStandard  = conversionFactors{3}(strcmp(inUnits,conversionFactors{2}));
% factorStandardToOut = 1/conversionFactors{3}(strcmp(outUnits,conversionFactors{2}));
% factorInToOut = factorInToStandard*factorStandardToOut;
% %
% outData       = factorInToOut*inData;
% 
% return

function out_var = validate_input(study_info,field_nm,varargin)
type_entry = 'none';
if nargin>2
    type_entry = varargin{1};
end
% Validate existence of the field in the JSON file
if isfield(study_info,field_nm)
    out_var     = study_info.(field_nm);
    if ~strcmp(type_entry,'none') && ~exist(out_var,type_entry)
        fprintf('\n*********************** WRONG INPUT IN JSON ****************\n');
        fprintf('*** The program could not find the entry associated to the field "%s" : \n',field_nm);
        fprintf('*** %s\n',out_var);
        fprintf('*** is either : \n')
        fprintf('***  -> not existing \n');
        fprintf('*** or\n'); 
        fprintf('***  -> typed incorrectly \n');
        fprintf('*************************************************************\n');
        error('Input JSON field %s not valid. Check entry as described above.',field_nm);
    end
else
    error('quantify_dataset:MissingJSONentry',...
        'Field %s missing in the json file',field_nm);
end


function out_var = validate_opt_input(study_info,field_nm,varargin)
type_entry = 'none';
if nargin>2
    type_entry = varargin{1};
end
% Validate existence of the field in the JSON file
out_var = '';
if isfield(study_info,field_nm)
    out_var     = study_info.(field_nm);
    if ~strcmp(type_entry,'none') && ~exist(out_var,type_entry)
        fprintf('\n************** WRONG OPTIONAL INPUT IN JSON ****************\n');
        fprintf('*** The program could not find the entry associated to the field "%s" : \n',field_nm);
        fprintf('*** %s\n',out_var);
        fprintf('*** is either : \n')
        fprintf('***  -> not existing \n');
        fprintf('*** or\n'); 
        fprintf('***  -> typed incorrectly \n');
        fprintf('*************************************************************\n');
        warning('Input JSON field %s not valid. Check entry as described above.',field_nm);
    end
end

function ctn_out = keep_images(ctn_in)
%%% Get current image format list supported by the
formatsAvail = {'jpg','png','tif'};

listFiles = {ctn_in(:).name}';
% Beautiful way to get indexes of all the patterns in a cell string
fun = @(s)~cellfun('isempty',strfind(listFiles,s));
out = cellfun(fun,formatsAvail,'UniformOutput',false);
idxToKeep = any(horzcat(out{:}),2);
% Keep only the images and create a list
ctn_out = ctn_in(idxToKeep);
return

function checkJson()
if ~(exist('loadjson','file')==2)
    try
        %install local
        if exist('jsonlab-1.5','dir')
            addpath(genpath(fullfile(pwd,'jsonlab-1.5')));
        else  %install on the nesys server
            if exist('Z:\NESYS_Tools\Matlab\jsonlab-1.5','dir')
                addpath(genpath('Z:\NESYS_Tools\Matlab\jsonlab-1.5'));
            elseif exist('Y:\NESYS_Tools\Matlab\jsonlab-1.5','dir')
                addpath(genpath('Y:\NESYS_Tools\Matlab\jsonlab-1.5'));
            end
        end
        if ~(exist('loadjson','file')==2)
            error('quantify_dataset:add_jsonlab',['Program tried to add the ',...
                'JSONlab package without success. Please follow instruction',...
                'on the README document to install the package']);
        end
    catch
        error('quantify_dataset:add_jsonlab',['Program tried to add the ',...
            'JSONlab package without success. Please follow instruction',...
            'on the README document to install the package']);
    end
else
    fprintf(1,'\nJSONlab toolbox is detected.\n');
end
return
