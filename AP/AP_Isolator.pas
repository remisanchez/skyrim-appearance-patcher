{
  AP_Isolator.pas
  Isolation phase, based on the SkyPatcher RDF NPC Replacer Converter v2
  PreProcessor (mmsk4989): each NPC override of the replacer plugins is copied
  as a new record "<prefix>_<EditorID>", its FaceGen files (loose or archived)
  are copied to the new FormID, then the override is removed.
  FaceGen .nif files are copied as is: they keep pointing to the original
  FaceTint path. Use Traits overrides are left unchanged.
  ESL flagged plugins: Next Object ID is fixed automatically, a plugin without
  enough ESL FormIDs for the isolated NPCs is skipped.
}

unit AP_Isolator;

uses 'AP\AP_Utils';

interface

function IsolatorInitialize: integer;
function IsolatorProcess(e: IInterface; var newRecord: IInterface; const outputRoot: string): integer;
procedure IsolatorFinalize;
function IsolatedWithFaceGen(const editorID: string): boolean;

implementation

const
  ESL_MAX_FORMID      = $FFF;
  ESL_START_FORMID    = $800;
  EXT_ESL_VERSION     = 1.71;

var
  prefix: string;
  slCheckedFiles: TStringList;
  // EditorIDs of the NPCs isolated with a FaceGen during this run
  slWithFaceGen: TStringList;
  isolatedCount, noFaceGenCount: integer;
  slSkipped: TStringList;

// NPC overrides that will be isolated, i.e. new records to create
function CountNPCsToIsolate(f: IInterface): integer;
var
  i: integer;
  group, rec: IInterface;
begin
  Result := 0;
  group := GroupBySignature(f, 'NPC_');
  if not Assigned(group) then
    Exit;
  for i := 0 to ElementCount(group) - 1 do begin
    rec := ElementByIndex(group, i);
    if not IsMaster(rec) and not IsNPCUsingTraits(rec) then
      Inc(Result);
  end;
end;

// ESL FormID range: 0x800-0xFFF, or 0x001-0xFFF with header 1.71
function GetESLFirstObjectID(f: IInterface): Cardinal;
begin
  Result := ESL_START_FORMID;
  if GetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Version') >= EXT_ESL_VERSION then
    Result := 1;
end;

// Checks that the ESL plugin has enough FormIDs left for the isolated NPCs.
// reason is set when it has not.
function CheckESLCapacity(f: IInterface; var reason: string): boolean;
var
  i, newRecords, toIsolate, maxRecords: integer;
  rec: IInterface;
begin
  reason := '';
  newRecords := 0;
  for i := 0 to RecordCount(f) - 1 do begin
    rec := RecordByIndex(f, i);
    if Assigned(rec) and (Signature(rec) <> 'TES4') and IsMaster(rec) then
      Inc(newRecords);
  end;

  toIsolate := CountNPCsToIsolate(f);
  maxRecords := ESL_MAX_FORMID - GetESLFirstObjectID(f) + 1;
  if newRecords + toIsolate > maxRecords then
    reason := IntToStr(newRecords) + ' new records + ' + IntToStr(toIsolate) +
      ' NPCs to isolate exceed the ESL limit of ' + IntToStr(maxRecords) +
      '. Remove the ESL flag to process it';

  Result := reason = '';
end;

// Puts Next Object ID back in the ESL range. xEdit skips used FormIDs by itself,
// so no restart is needed.
procedure FixESLNextObjectID(f: IInterface);
var
  header: IInterface;
  nextObjectID: Cardinal;
begin
  header := ElementByIndex(f, 0);
  nextObjectID := GetElementNativeValues(header, 'HEDR\Next Object ID');
  if (nextObjectID < GetESLFirstObjectID(f)) or (nextObjectID > ESL_MAX_FORMID) then begin
    SetElementNativeValues(header, 'HEDR\Next Object ID', GetESLFirstObjectID(f));
    AddMessage('  Next Object ID reset to ' + IntToHex(GetESLFirstObjectID(f), 3) + '.');
  end;
end;

function IsolatorInitialize: integer;
var
  inputOK, canceled, valid: boolean;
  inputValue: string;
begin
  Result := 0;
  prefix := '';
  slCheckedFiles := TStringList.Create;
  slWithFaceGen := TStringList.Create;
  slWithFaceGen.Sorted := true;
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

// Plugin checks, once per plugin. Returns false if its records must be skipped.
function CheckPlugin(f: IInterface): boolean;
var
  fileName, reason: string;
  eslFlag: boolean;
begin
  fileName := GetFileName(f);
  if slCheckedFiles.IndexOfName(fileName) <> -1 then begin
    Result := slCheckedFiles.Values[fileName] = 'ok';
    Exit;
  end;

  Result := true;
  if IsOfficialMaster(fileName) then begin
    AddMessage('Skipped plugin, official master: ' + fileName);
    Result := false;
  end
  else begin
    eslFlag := GetElementNativeValues(ElementByIndex(f, 0), 'Record Header\Record Flags\ESL');
    if eslFlag then begin
      if CheckESLCapacity(f, reason) then
        FixESLNextObjectID(f)
      else begin
        AddMessage('Skipped plugin ' + fileName + ': ' + reason + '.');
        Result := false;
      end;
    end;
  end;

  if Result then
    slCheckedFiles.Values[fileName] := 'ok'
  else
    slCheckedFiles.Values[fileName] := 'skipped';
end;

// Returns -1 to abort the script. newRecord is only assigned when the NPC was isolated.
function IsolatorProcess(e: IInterface; var newRecord: IInterface; const outputRoot: string): integer;
var
  f: IInterface;
  fileName, newFormID, recordID, newMeshPath, newTexturePath: string;
  hasMesh: boolean;
begin
  Result := 0;
  newRecord := nil;
  f := GetFile(e);
  fileName := GetFileName(f);

  if Signature(e) <> 'NPC_' then
    Exit;

  if not CheckPlugin(f) then
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
  // Both files are copied independently, as in the v2 PreProcessor
  hasMesh := CopyResource(GetNPCFaceGenRelPath(e, true), newMeshPath);
  CopyResource(GetNPCFaceGenRelPath(e, false), newTexturePath);
  if hasMesh then
    slWithFaceGen.Add(EditorID(newRecord))
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
  slCheckedFiles.Free;
  slWithFaceGen.Free;
end;

// FaceGen copied during this run. Needed because FileExists may not see it yet under MO2.
function IsolatedWithFaceGen(const editorID: string): boolean;
begin
  Result := slWithFaceGen.IndexOf(editorID) <> -1;
end;

end.
