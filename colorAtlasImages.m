function [pr,lbl_lst,lbl_idx,lbl_pixel,lbl_clr] = colorAtlasImages(segIm,lblFile,debug)
% segIm : array
% lblFile : path to label file
if nargin < 3
    debug = false;
end
%% Read the labels
if exist(lblFile,'file')
    annotation = importITKLabelfile(lblFile);
else
    error('colorAtlasImages:LabelFileNotFound',['Unable to find the label file named %s. \n',...
        'Please make sure that the path is correct.'],lblFile)
end
lbl_clr_raw = table2array(annotation(:,1:4));
lbl_nm      = table2cell(annotation(:,5));

% Could be done without loop, think more
sZB = size(segIm);
pr = uint8(zeros([sZB 3])); %,'like',segIm);
%
lbl_lst = [];
lbl_idx = [];
lbl_clr = [];
for iR = 1 : sZB(1)
    for iC = 1 : sZB(2)
        if segIm(iR,iC)>0
            try
                idx_ann         = (segIm(iR,iC)==lbl_clr_raw(:,1));
                if debug
                    pr(iR,iC,:) = lbl_clr_raw(idx_ann,2:4);
                end
                if ~any(segIm(iR,iC)==lbl_idx)
                    lbl_idx(end+1)  = segIm(iR,iC);
                    lbl_lst = vertcat(lbl_lst,lbl_nm(idx_ann));
                    lbl_clr = vertcat(lbl_clr,lbl_clr_raw(idx_ann,2:4));
                end
            catch
%                 fprintf('Label %d not found in the label file. Skipping...\n',segIm(iR,iC));
            end
        end
    end
end

% Check size
if ~(length(lbl_idx)==length(lbl_lst))
   error('colorAtlasImages:Wrong','Different length between region name and region idx'); 
end

% Pixel per region
lbl_pixel = nan(length(lbl_idx),1);
for iRR = 1:length(lbl_idx)
    lbl_pixel(iRR) = length(find(segIm(:)==lbl_idx(iRR)));
end
if debug
    hF = figure;imshow(uint8(pr),'Border','tight');
    F = getframe(hF);
    imwrite(F.cdata,'colorOnlyCereb.png');
end

return

function annotation = importITKLabelfile(filename, startRow, endRow)
%IMPORTFILE Import numeric data from a text file as a matrix.
%   ANNOTATION = IMPORTFILE(FILENAME) Reads data from text file FILENAME
%   for the default selection.
%
%   ANNOTATION = IMPORTFILE(FILENAME, STARTROW, ENDROW) Reads data from
%   rows STARTROW through ENDROW of text file FILENAME.
%
% Example:
%   annotation = importfile('annotation.lbl', 16, 1302);
%
%    See also TEXTSCAN.

% Auto-generated by MATLAB on 2017/01/31 16:29:06

%% Initialize variables.
delimiter = '\t';
if nargin<=2
    startRow = 16;
    endRow = inf;
end

%% Format string for each line of text:
%   column1: double (%f)
%	column2: double (%f)
%   column3: double (%f)
%	column4: double (%f)
%   column5: double (%f)
%	column6: double (%f)
%   column7: double (%f)
%	column8: text (%q)
% For more information, see the TEXTSCAN documentation.
formatSpec = '%f%f%f%f%f%f%f%q%[^\n\r]';

%% Open the text file.
fileID = fopen(filename,'r');

%% Read columns of data according to format string.
% This call is based on the structure of the file used to generate this
% code. If an error occurs for a different file, try regenerating the code
% from the Import Tool.
dataArray = textscan(fileID, formatSpec, endRow(1)-startRow(1)+1, 'Delimiter', delimiter, 'HeaderLines', startRow(1)-1, 'ReturnOnError', false);
for block=2:length(startRow)
    frewind(fileID);
    dataArrayBlock = textscan(fileID, formatSpec, endRow(block)-startRow(block)+1, 'Delimiter', delimiter, 'HeaderLines', startRow(block)-1, 'ReturnOnError', false);
    for col=1:length(dataArray)
        dataArray{col} = [dataArray{col};dataArrayBlock{col}];
    end
end

%% Close the text file.
fclose(fileID);

%% Post processing for unimportable data.
% No unimportable data rules were applied during the import, so no post
% processing code is included. To generate code which works for
% unimportable data, select unimportable cells in a file and regenerate the
% script.

%% Create output variable
annotation = table(dataArray{1:end-1}, 'VariableNames', {'idxReg','redComp','greenComp','blueComp','VarName5','VarName6','VarName7','regName'});
% Remove 5, 6 and 7
annotation(:,5:7) = [];

return