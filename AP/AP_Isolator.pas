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
  Appearance only mode: isolated NPCs get back the original NPC data except
  their appearance, and every record not needed by them is removed.
}

unit AP_Isolator;

uses 'AP\AP_Utils';

interface

function IsolatorInitialize: integer;
function IsolatorProcess(e: IInterface; var newRecord: IInterface; const outputRoot: string): integer;
procedure IsolatorFinalize;

implementation

const
  ESL_MAX_FORMID      = $FFF;
  ESL_START_FORMID    = $800;
  EXT_ESL_VERSION     = 1.71;
  // Appearance only mode is hidden until it is tested
  SHOW_APPEARANCE_ONLY_OPTION = false;

var
  prefix: string;
  appearanceOnly: boolean;
  slCheckedFiles: TStringList;
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

// NPC_ elements that define the appearance, kept from the replacer
function IsAppearanceElement(const elementName: string): boolean;
begin
  Result := (elementName = 'Record Header') or (elementName = 'Head Parts') or (elementName = 'Tint Layers') or
    (Pos(Copy(elementName, 1, 4) + ',', 'EDID,OBND,RNAM,WNAM,ANAM,VTCK,NAM6,NAM7,HCLF,FTST,QNAM,NAM9,NAMA,') > 0);
end;

// NPC version used in game once the replacer override is removed
function GetOriginalNPC(e: IInterface): IInterface;
var
  i: integer;
  m, o: IInterface;
begin
  m := MasterOrSelf(e);
  Result := m;
  for i := 0 to OverrideCount(m) - 1 do begin
    o := OverrideByIndex(m, i);
    if GetFileName(GetFile(o)) <> GetFileName(GetFile(e)) then
      Result := o;
  end;
end;

// Replaces every non-appearance element of npc with the one of original
// (name, class, outfit, factions, AI, inventory, stats...). Gender is kept.
procedure RestoreNonAppearanceData(npc, original: IInterface);
var
  i: integer;
  el, target: IInterface;
  isFemale: boolean;
  flags: Cardinal;
begin
  isFemale := IsNPCFemale(npc);
  AddRequiredElementMasters(original, GetFile(npc), False, True);

  for i := ElementCount(npc) - 1 downto 0 do begin
    el := ElementByIndex(npc, i);
    if not IsAppearanceElement(Name(el)) and not Assigned(ElementByName(original, Name(el))) then
      Remove(el);
  end;

  for i := 0 to ElementCount(original) - 1 do begin
    el := ElementByIndex(original, i);
    if not IsAppearanceElement(Name(el)) then begin
      target := ElementByName(npc, Name(el));
      if Assigned(target) then
        ElementAssign(target, LowInteger, el, False)
      else
        wbCopyElementToRecord(el, npc, False, True);
    end;
  end;

  // ACBS comes from the original: restore the gender, the face must not come from a template
  flags := GetElementNativeValues(npc, 'ACBS - Configuration\Flags');
  if isFemale then
    flags := flags or 1
  else
    flags := flags and $FFFFFFFE;
  SetElementNativeValues(npc, 'ACBS - Configuration\Flags', flags);
  flags := GetElementNativeValues(npc, 'ACBS - Configuration\Template Flags');
  SetElementNativeValues(npc, 'ACBS - Configuration\Template Flags', flags and $FFFE);
end;

// Version of rec (or of its master) stored in plugin f, or nil
function GetRecordInFile(rec, f: IInterface): IInterface;
var
  i: integer;
  m: IInterface;
begin
  Result := nil;
  m := MasterOrSelf(rec);
  if GetFileName(GetFile(m)) = GetFileName(f) then
    Result := m
  else
    for i := 0 to OverrideCount(m) - 1 do
      if GetFileName(GetFile(OverrideByIndex(m, i))) = GetFileName(f) then
        Result := OverrideByIndex(m, i);
end;

function GetRecordKey(rec: IInterface): string;
begin
  Result := IntToHex(GetLoadOrderFormID(rec), 8);
end;

// Adds to keep the records of f referenced by el, recursively
procedure CollectReferences(el, f: IInterface; keep: TStringList);
var
  i: integer;
  child, target: IInterface;
begin
  for i := 0 to ElementCount(el) - 1 do begin
    child := ElementByIndex(el, i);
    if CanContainFormIDs(child) then begin
      if ElementCount(child) > 0 then
        CollectReferences(child, f, keep)
      else begin
        target := LinksTo(child);
        if Assigned(target) then
          target := GetRecordInFile(target, f);
        if Assigned(target) then
          if keep.IndexOf(GetRecordKey(target)) = -1 then begin
            keep.Add(GetRecordKey(target));
            CollectReferences(target, f, keep);
          end;
      end;
    end;
  end;
end;

// Appearance only mode: removes every record of f not needed by its isolated NPCs
procedure CleanPlugin(f: IInterface);
var
  i, pass, removedCount, passRemoved: integer;
  rec: IInterface;
  keep: TStringList;
begin
  keep := TStringList.Create;
  keep.Sorted := true;
  try
    // Isolated NPCs and everything they reference in the plugin
    for i := 0 to RecordCount(f) - 1 do begin
      rec := RecordByIndex(f, i);
      if Assigned(rec) and (Signature(rec) = 'NPC_') and IsMaster(rec) and
        (Copy(EditorID(rec), 1, Length(prefix) + 1) = prefix + '_') then
        if keep.IndexOf(GetRecordKey(rec)) = -1 then begin
          keep.Add(GetRecordKey(rec));
          CollectReferences(rec, f, keep);
        end;
    end;

    // Removing a record also removes its children and shifts indexes:
    // repeat until a pass removes nothing (limited in case Remove fails).
    removedCount := 0;
    pass := 0;
    passRemoved := 1;
    while (passRemoved > 0) and (pass < 5) do begin
      passRemoved := 0;
      for i := RecordCount(f) - 1 downto 0 do
        if i < RecordCount(f) then begin
          rec := RecordByIndex(f, i);
          if Assigned(rec) and (Signature(rec) <> 'TES4') and (keep.IndexOf(GetRecordKey(rec)) = -1) then begin
            Remove(rec);
            Inc(passRemoved);
          end;
        end;
      removedCount := removedCount + passRemoved;
      Inc(pass);
    end;

    CleanMasters(f);
    AddMessage('Appearance only, ' + GetFileName(f) + ': ' + IntToStr(keep.Count) + ' records kept, ' +
      IntToStr(removedCount) + ' removed.');
  finally
    keep.Free;
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

  appearanceOnly := false;
  if SHOW_APPEARANCE_ONLY_OPTION then
    appearanceOnly := MessageDlg(
      'Convert the plugins to NPC appearance replacers only?' + #13#10 + #13#10 +
      'Yes: everything that does not change the look of NPCs is REMOVED from the' + #13#10 +
      'selected plugins: edits of quests, locations, cells, leveled lists and other' + #13#10 +
      'records, new classes, outfits... Isolated NPCs keep the original NPC data' + #13#10 +
      '(name, class, outfit, AI, inventory...): only their appearance comes from' + #13#10 +
      'the replacer (face, skin, race, gender, voice, height, weight).' + #13#10 + #13#10 +
      'No: the rest of the plugins is kept as is.' + #13#10 + #13#10 +
      'Make a backup of the plugins before saving them.',
      mtWarning, [mbYes, mbNo], 0) = mrYes;
  if appearanceOnly then
    AddMessage('Appearance only mode.');
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

  if appearanceOnly then
    RestoreNonAppearanceData(newRecord, GetOriginalNPC(e));

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
  i, j: integer;
begin
  if appearanceOnly then
    for i := 0 to slCheckedFiles.Count - 1 do
      if slCheckedFiles.ValueFromIndex[i] = 'ok' then
        for j := 0 to FileCount - 1 do
          if GetFileName(FileByIndex(j)) = slCheckedFiles.Names[i] then
            CleanPlugin(FileByIndex(j));

  AddMessage('Isolation: ' + IntToStr(isolatedCount) + ' isolated (' + IntToStr(noFaceGenCount) +
    ' without FaceGen), ' + IntToStr(slSkipped.Count) + ' skipped.');
  for i := 0 to slSkipped.Count - 1 do
    AddMessage('  Skipped: ' + slSkipped[i]);
  slSkipped.Free;
  slCheckedFiles.Free;
end;

end.
