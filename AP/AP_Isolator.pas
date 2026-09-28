{
  AP_Isolator.pas
  Isolation phase, based on the SkyPatcher RDF NPC Replacer Converter v2
  PreProcessor (mmsk4989): each NPC override of the replacer plugin is copied
  as a new record "<prefix>_<EditorID>", its FaceGen files are copied (or moved)
  to the new FormID, then the override is removed.
  FaceGen .nif files are copied as is, without editing.
}

unit AP_Isolator;

uses 'AP\AP_Utils';

interface

function IsolatorInitialize: integer;
function IsolatorProcess(e: IInterface; var newRecord: IInterface; const outputRoot: string): integer;
procedure IsolatorFinalize;

implementation

const
  OLD_ESL_MAX_RECORDS = 2047;
  NEW_ESL_MAX_RECORDS = 4095;
  ESL_MAX_FORMID      = $FFF;
  ESL_START_FORMID    = $800;
  EXT_ESL_VERSION     = 1.71;

var
  prefix, firstFileName: string;
  fileChecked, removeFaceGen, removeMissingFaceGen: boolean;
  isolatedCount, removedCount: integer;
  slSkipped: TStringList;

function GetFaceGenPath(const baseDir, pluginName, formID: string; isMesh: boolean): string;
begin
  if isMesh then
    Result := baseDir + 'meshes\actors\character\FaceGenData\FaceGeom\' + pluginName + '\' + formID + '.nif'
  else
    Result := baseDir + 'textures\actors\character\FaceGenData\FaceTint\' + pluginName + '\' + formID + '.dds';
end;

function CopyFaceGenFile(const oldPath, newPath: string; moveFile: boolean): boolean;
begin
  if not DirectoryExists(ExtractFilePath(newPath)) then
    ForceDirectories(ExtractFilePath(newPath));

  if moveFile then
    Result := RenameFile(PChar(oldPath), PChar(newPath))
  else
    Result := CopyFile(PChar(oldPath), PChar(newPath), False);

  if Result then
    AddMessage('  ' + oldPath + ' -> ' + newPath)
  else
    AddMessage('  Failed to copy: ' + oldPath);
end;

function CountNPCRecords(f: IInterface): integer;
var
  group: IInterface;
begin
  Result := 0;
  group := GroupBySignature(f, 'NPC_');
  if Assigned(group) then
    Result := ElementCount(group);
end;

// ESL flagged plugins: checks that enough FormIDs are left for the new records.
// Returns true if the process must stop.
function ESLFlaggedPluginTest(f: IInterface): boolean;
var
  header: IInterface;
  recordNum, maxRecordNum, npcRecordNum, nextObjectID, usedFormIDs, remainingFormIDs: Cardinal;
  headerVer: Float;
  invalidObjectID: boolean;
begin
  Result := false;
  header := ElementByIndex(f, 0);

  recordNum    := RecordCount(f);
  headerVer    := GetElementNativeValues(header, 'HEDR\Version');
  nextObjectID := GetElementNativeValues(header, 'HEDR\Next Object ID');
  npcRecordNum := CountNPCRecords(f);

  // Header 1.71 (extended ESL) also allows FormIDs below 0x800
  if headerVer < EXT_ESL_VERSION then begin
    maxRecordNum := OLD_ESL_MAX_RECORDS;
    invalidObjectID := (nextObjectID < ESL_START_FORMID) or (nextObjectID > ESL_MAX_FORMID);
    if not invalidObjectID then
      usedFormIDs := nextObjectID - ESL_START_FORMID
    else
      usedFormIDs := nextObjectID;
  end
  else begin
    maxRecordNum := NEW_ESL_MAX_RECORDS;
    invalidObjectID := nextObjectID > ESL_MAX_FORMID;
    if nextObjectID < ESL_START_FORMID then
      usedFormIDs := nextObjectID + ESL_START_FORMID
    else
      usedFormIDs := nextObjectID - ESL_START_FORMID;
  end;
  remainingFormIDs := maxRecordNum - usedFormIDs;

  AddMessage('ESL plugin: ' + IntToStr(recordNum) + ' records, ' + IntToStr(npcRecordNum) +
    ' NPCs, next object ID ' + IntToHex(nextObjectID and $FFFFFF, 1) +
    ', about ' + IntToStr(remainingFormIDs) + ' FormIDs left.');

  if invalidObjectID then begin
    AddMessage('Aborted: Next Object ID is invalid.');
    if MessageDlg('Next Object ID is invalid. Reset it to 800?', mtConfirmation, [mbOK, mbCancel], 0) = mrOK then begin
      SetElementNativeValues(header, 'HEDR\Next Object ID', ESL_START_FORMID);
      MessageDlg('Next Object ID has been reset to 800. Check the file header, then run the script again.', mtInformation, [mbOK], 0);
    end;
    Result := true;
  end
  else if (remainingFormIDs > 0) and (npcRecordNum > remainingFormIDs) then begin
    AddMessage('Aborted: not enough FormIDs left.');
    if MessageDlg('Not enough FormIDs left. Reset Next Object ID to 800?', mtConfirmation, [mbOK, mbCancel], 0) = mrOK then begin
      SetElementNativeValues(header, 'HEDR\Next Object ID', ESL_START_FORMID);
      MessageDlg('Next Object ID has been reset to 800. Check the file header, then run the script again.', mtInformation, [mbOK], 0);
    end;
    Result := true;
  end
  else if recordNum >= maxRecordNum then begin
    AddMessage('Aborted: the plugin holds ' + IntToStr(recordNum) + ' records, the ESL limit is ' + IntToStr(maxRecordNum) + '.');
    AddMessage('Remove the ESL flag while running the script, then set it again.');
    Result := true;
  end;
end;

function IsolatorInitialize: integer;
var
  opts, disableOpts: TStringList;
  inputOK, canceled, valid: boolean;
begin
  Result := 0;
  prefix := '';
  firstFileName := '';
  fileChecked := false;
  isolatedCount := 0;
  removedCount := 0;
  slSkipped := TStringList.Create;

  opts := TStringList.Create;
  disableOpts := TStringList.Create;
  try
    opts.Values['Remove FaceGen files in the replacer mod'] := 'False';
    opts.Values['Remove NPC records without FaceGen files'] := 'False';

    if not ShowCheckboxForm(opts, disableOpts, 'Choose Isolation Option') then begin
      AddMessage('Selection was canceled.');
      Result := -1;
      Exit;
    end;

    removeFaceGen        := GetBoolSLValue(opts.Values['Remove FaceGen files in the replacer mod']);
    removeMissingFaceGen := GetBoolSLValue(opts.Values['Remove NPC records without FaceGen files']);
  finally
    opts.Free;
    disableOpts.Free;
  end;

  // No Break/Exit inside repeat: known xEdit parser issue
  canceled := false;
  valid := false;
  repeat
    inputOK := InputQuery('Editor ID prefix',
      'Letters (a-z, A-Z) and digits (0-9) only.' + #13#10 + '"_" is added after the prefix:', prefix);
    if not inputOK then
      canceled := true
    else if EditorIDInputValidation(prefix) then
      valid := true
    else
      MessageDlg('Invalid prefix. Use letters and digits only.', mtWarning, [mbOK], 0);
  until canceled or valid;

  if canceled then begin
    AddMessage('Prefix input was canceled.');
    Result := -1;
    Exit;
  end;

  AddMessage('Prefix: ' + prefix);
end;

// Returns -1 to abort the script. newRecord is only assigned when the NPC was isolated.
function IsolatorProcess(e: IInterface; var newRecord: IInterface; const outputRoot: string): integer;
var
  f: IInterface;
  fileName, baseFileName, oldFormID, newFormID, oldEditorID, recordID: string;
  oldMeshPath, oldTexturePath, newMeshPath, newTexturePath: string;
  missingMesh, missingTint, eslFlag: boolean;
begin
  Result := 0;
  newRecord := nil;
  f := GetFile(e);
  fileName := GetFileName(f);

  // Plugin checks, on the first record only
  if not fileChecked then begin
    if IsOfficialMaster(fileName) then begin
      AddMessage(fileName + ' is an official master and must not be edited.');
      Result := -1;
      Exit;
    end;

    eslFlag := GetElementNativeValues(ElementByIndex(f, 0), 'Record Header\Record Flags\ESL');
    if eslFlag then
      if ESLFlaggedPluginTest(f) then begin
        Result := -1;
        Exit;
      end;

    firstFileName := fileName;
    fileChecked := true;
  end;

  if fileName <> firstFileName then begin
    AddMessage('Skipped, not in ' + firstFileName + ': ' + Name(e));
    Exit;
  end;

  if Signature(e) <> 'NPC_' then
    Exit;

  if IsMaster(e) then begin
    AddMessage('Skipped, not an override: ' + Name(e));
    Exit;
  end;

  baseFileName := GetFileName(GetFile(MasterOrSelf(e)));
  oldFormID    := IntToHex64(GetElementNativeValues(e, 'Record Header\FormID') and $FFFFFF, 8);
  oldEditorID  := EditorID(e);
  recordID     := oldFormID + ' ' + oldEditorID;

  oldMeshPath    := GetFaceGenPath(DataPath, baseFileName, oldFormID, true);
  oldTexturePath := GetFaceGenPath(DataPath, baseFileName, oldFormID, false);
  missingMesh    := not FileExists(oldMeshPath);
  missingTint    := not FileExists(oldTexturePath);

  if missingMesh <> missingTint then begin
    if missingMesh then
      AddMessage('Skipped, FaceGeom missing: ' + recordID)
    else
      AddMessage('Skipped, FaceTint missing: ' + recordID);
    slSkipped.Add(recordID);
    Exit;
  end;

  if missingMesh and missingTint then begin
    if removeMissingFaceGen then begin
      AddMessage('Removed, no FaceGen files: ' + recordID);
      Remove(e);
      Inc(removedCount);
      Exit;
    end;
    // Use Traits NPCs get their face from their template
    if not IsNPCUsingTraits(e) then begin
      AddMessage('Skipped, no FaceGen files: ' + recordID);
      slSkipped.Add(recordID);
      Exit;
    end;
  end;

  newRecord := wbCopyElementToFile(e, f, True, True);
  if not Assigned(newRecord) then begin
    AddMessage('Error: failed to copy ' + Name(e));
    Exit;
  end;

  SetElementEditValues(newRecord, 'EDID', prefix + '_' + oldEditorID);
  newFormID := IntToHex64(GetElementNativeValues(newRecord, 'Record Header\FormID') and $FFFFFF, 8);
  AddMessage('Isolated: ' + recordID + ' -> ' + Name(newRecord));

  if not missingMesh then begin
    newMeshPath    := GetFaceGenPath(DataPath + outputRoot + '\', fileName, newFormID, true);
    newTexturePath := GetFaceGenPath(DataPath + outputRoot + '\', fileName, newFormID, false);
    CopyFaceGenFile(oldMeshPath, newMeshPath, removeFaceGen);
    CopyFaceGenFile(oldTexturePath, newTexturePath, removeFaceGen);
  end;

  Remove(e);
  Inc(isolatedCount);
end;

procedure IsolatorFinalize;
var
  i: integer;
begin
  AddMessage('Isolation: ' + IntToStr(isolatedCount) + ' isolated, ' + IntToStr(removedCount) +
    ' removed, ' + IntToStr(slSkipped.Count) + ' skipped.');
  for i := 0 to slSkipped.Count - 1 do
    AddMessage('  Skipped: ' + slSkipped[i]);
  slSkipped.Free;
end;

end.
