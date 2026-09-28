{
  AP_Isolator.pas
  Isolation phase, based on the SkyPatcher RDF NPC Replacer Converter v2
  PreProcessor (mmsk4989): each NPC override of the replacer plugin is copied
  as a new record "<prefix>_<EditorID>", its FaceGen files (loose or archived)
  are copied to the new FormID, then the override is removed.
  FaceGen .nif files are copied as is: they keep pointing to the original
  FaceTint path. Use Traits overrides are left unchanged.
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
  fileChecked: boolean;
  isolatedCount, noFaceGenCount: integer;
  slSkipped: TStringList;

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
  inputOK, canceled, valid: boolean;
  inputValue: string;
begin
  Result := 0;
  prefix := '';
  firstFileName := '';
  fileChecked := false;
  isolatedCount := 0;
  noFaceGenCount := 0;
  slSkipped := TStringList.Create;

  // No Break/Exit inside repeat: known xEdit parser issue
  canceled := false;
  valid := false;
  inputValue := '';
  repeat
    inputOK := AskInputDialog('Editor ID prefix',
      'Letters (a-z, A-Z) and digits (0-9) only.' + #13#10 + '"_" is added after the prefix:', inputValue);
    // "_" is added by the script: drop the ones typed at the end
    inputValue := Trim(inputValue);
    while (Length(inputValue) > 0) and (Copy(inputValue, Length(inputValue), 1) = '_') do
      inputValue := Copy(inputValue, 1, Length(inputValue) - 1);
    if not inputOK then
      canceled := true
    else if EditorIDInputValidation(inputValue) then
      valid := true
    else
      MessageDlg('Invalid prefix "' + inputValue + '". Use letters and digits only.', mtWarning, [mbOK], 0);
  until canceled or valid;
  prefix := inputValue;

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
  fileName, newFormID, recordID, newMeshPath, newTexturePath: string;
  hasMesh, eslFlag: boolean;
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

  // Records added by the replacer (including previously isolated NPCs)
  if IsMaster(e) then
    Exit;

  recordID := GetLocalFormIDHex(e) + ' ' + EditorID(e);

  // Race, gender, voice and face come from the template
  if IsNPCUsingTraits(e) then begin
    AddMessage('Skipped, Use Traits template flag: ' + recordID);
    slSkipped.Add(recordID + ' (Use Traits)');
    Exit;
  end;

  newRecord := wbCopyElementToFile(e, f, True, True);
  if not Assigned(newRecord) then begin
    AddMessage('Error: failed to copy ' + Name(e));
    slSkipped.Add(recordID + ' (copy failed)');
    Exit;
  end;

  SetElementEditValues(newRecord, 'EDID', prefix + '_' + EditorID(e));
  newFormID := PadLeftZero(GetLocalFormIDHex(newRecord), 8);
  AddMessage('Isolated: ' + recordID + ' -> ' + Name(newRecord));

  // FaceGen of the original NPC, as provided by the replacer
  newMeshPath    := DataPath + outputRoot + '\' + GetFaceGenRelPath(fileName, newFormID, true);
  newTexturePath := DataPath + outputRoot + '\' + GetFaceGenRelPath(fileName, newFormID, false);
  hasMesh := CopyResource(GetNPCFaceGenRelPath(e, true), newMeshPath);
  if hasMesh then begin
    // Optional: without it, the .nif FaceTint path resolves to the vanilla file
    CopyResource(GetNPCFaceGenRelPath(e, false), newTexturePath);
  end
  else begin
    AddMessage('  No FaceGen: only race, gender, voice and skin changes will be kept.');
    Inc(noFaceGenCount);
  end;

  Remove(e);
  Inc(isolatedCount);
end;

procedure IsolatorFinalize;
var
  i: integer;
begin
  AddMessage('Isolation: ' + IntToStr(isolatedCount) + ' isolated (' + IntToStr(noFaceGenCount) +
    ' without FaceGen), ' + IntToStr(slSkipped.Count) + ' skipped.');
  for i := 0 to slSkipped.Count - 1 do
    AddMessage('  Skipped: ' + slSkipped[i]);
  slSkipped.Free;
end;

end.
