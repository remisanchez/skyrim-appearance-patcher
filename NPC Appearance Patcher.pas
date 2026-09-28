{
  ==============================================================================
   NPC Appearance Patcher.pas
  ==============================================================================
   Converts an NPC replacer plugin into SkyPatcher runtime patches. Changes are
   detected automatically: face (FaceGen), skin, race, gender and voice.

     - NPC in leveled lists, with FaceGen -> SkyPatcher leveledList rules: the
       original NPC is replaced by the isolated NPC, same level and count.
     - Other NPCs -> SkyPatcher npc rules.

   Run it on one or more replacer plugins (one config file set per plugin,
   same prefix for all). Integration mode first isolates the NPC
   overrides (AP_Isolator), otherwise the plugin must already be isolated
   (replacer EditorIDs "<prefix>_<original EditorID>").

   Output: Data\NPC Appearance Patcher\ (MO2: overwrite\NPC Appearance Patcher\),
   to be turned into a mod.

   Author: sanchofyah. Based on SkyPatcher RDF NPC Replacer Converter /
   NPC Replacer Converter by mmsk4989.
  ==============================================================================
}

unit AppearancePatcher;

uses 'AP\AP_Utils';
uses 'AP\AP_Isolator';
uses 'AP\AP_LeveledLists';

const
  OUTPUT_ROOT = 'NPC Appearance Patcher';

var
  // Config buffers per plugin: Strings = plugin name, Objects = TStringList
  mapSkyPatcher, mapLeveledLists: TStringList;
  // Buffers of the plugin being processed
  slSkyPatcher, slLeveledLists: TStringList;
  LVLNMap: TStringList;
  callIsolator: boolean;
  llCount, spCount, unchangedCount: integer;

function Initialize: integer;
begin
  Result := 0;

  mapSkyPatcher   := TStringList.Create;
  mapLeveledLists := TStringList.Create;
  LVLNMap        := nil;
  llCount        := 0;
  spCount        := 0;
  unchangedCount := 0;
  callIsolator   := false;

  if MessageDlg(
    'Run in Integration Mode?' + #13#10 +
    'Yes = Isolate the NPCs, then generate the configs' + #13#10 +
    'No = Generate the configs only (plugin already isolated)',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    callIsolator := true;

  if callIsolator then
    if IsolatorInitialize = -1 then begin
      callIsolator := false;
      Result := -1;
      Exit;
    end;

  LVLNMap := BuildLVLNMap;
end;

function GetPluginBuffer(map: TStringList; const pluginName: string): TStringList;
var
  idx: integer;
begin
  idx := map.IndexOf(pluginName);
  if idx = -1 then begin
    Result := TStringList.Create;
    map.AddObject(pluginName, Result);
  end
  else
    Result := TStringList(map.Objects[idx]);
end;

procedure FreePluginBuffers(map: TStringList);
var
  i: integer;
begin
  for i := 0 to map.Count - 1 do
    TStringList(map.Objects[i]).Free;
  map.Free;
end;

// FaceGen of the isolated NPC: just copied by the isolator, or already installed
function HasFaceGen(npc: IInterface): boolean;
var
  relPath: string;
begin
  if callIsolator then
    if IsolatedWithFaceGen(EditorID(npc)) then begin
      Result := true;
      Exit;
    end;
  relPath := GetNPCFaceGenRelPath(npc, true);
  Result := FileExists(DataPath + OUTPUT_ROOT + '\' + relPath) or DataResourceExists(relPath);
end;

procedure AddSkyPatcherRules(targetRecord, replacerRecord, skinRecord, raceRecord, voiceRecord: IInterface;
  hasFace, skinChanged, raceChanged, sexChanged, voiceChanged: boolean);
var
  targetID: string;
begin
  targetID := 'filterByNpcs=' + GetSkyPatcherID(targetRecord);
  slSkyPatcher.Add(';' + GetElementEditValues(targetRecord, 'FULL'));
  slSkyPatcher.Add(';Form ID: ' + GetLocalFormIDHex(targetRecord) + '  Editor ID: ' + EditorID(targetRecord) +
    '  ->  ' + EditorID(replacerRecord));

  if hasFace then
    slSkyPatcher.Add(targetID + ':copyVisualStyle=' + GetSkyPatcherID(replacerRecord));

  // 'null' resets the skin to the race default body
  if skinChanged then
    if Assigned(skinRecord) then
      slSkyPatcher.Add(targetID + ':skin=' + GetSkyPatcherID(skinRecord))
    else
      slSkyPatcher.Add(targetID + ':skin=null');

  if raceChanged then
    slSkyPatcher.Add(targetID + ':race=' + GetSkyPatcherID(raceRecord));

  if sexChanged then
    if IsNPCFemale(replacerRecord) then
      slSkyPatcher.Add(targetID + ':setFlags=female')
    else
      slSkyPatcher.Add(targetID + ':removeFlags=female');

  if voiceChanged then
    slSkyPatcher.Add(targetID + ':voiceType=' + GetSkyPatcherID(voiceRecord));

  slSkyPatcher.Add('');
  Inc(spCount);
end;

function Process(e: IInterface): integer;
var
  replacerRecord, targetRecord, skinRecord, raceRecord, voiceRecord: IInterface;
  replacerFileName, replacerEditorID, targetEditorID, changes: string;
  underscorePos, idxLL, placedCount: integer;
  hasFace, skinChanged, raceChanged, sexChanged, voiceChanged: boolean;
begin
  Result := 0;

  if Signature(e) <> 'NPC_' then
    Exit;

  replacerFileName := GetFileName(GetFile(e));
  slSkyPatcher   := GetPluginBuffer(mapSkyPatcher, replacerFileName);
  slLeveledLists := GetPluginBuffer(mapLeveledLists, replacerFileName);

  replacerRecord := e;
  if callIsolator then begin
    Result := IsolatorProcess(e, replacerRecord, OUTPUT_ROOT);
    if Result = -1 then
      Exit;
  end;

  // Not isolated (skipped)
  if not Assigned(replacerRecord) then
    Exit;

  replacerEditorID := EditorID(replacerRecord);
  underscorePos := Pos('_', replacerEditorID);
  if underscorePos = 0 then begin
    AddMessage('Skipped, no prefix in Editor ID: ' + replacerEditorID);
    Exit;
  end;

  targetRecord := FindNPCByEditorID(Copy(replacerEditorID, underscorePos + 1, Length(replacerEditorID)));
  if not Assigned(targetRecord) then begin
    AddMessage('Skipped, original NPC not found: ' + replacerEditorID);
    Exit;
  end;
  targetEditorID := EditorID(targetRecord);

  if IsNPCUsingTraits(replacerRecord) then begin
    AddMessage('Skipped, Use Traits template flag: ' + replacerEditorID);
    Exit;
  end;

  // Detected changes
  hasFace      := HasFaceGen(replacerRecord);
  skinRecord   := GetLinkedMasterRecord(replacerRecord, 'WNAM');
  raceRecord   := GetLinkedMasterRecord(replacerRecord, 'RNAM');
  voiceRecord  := GetLinkedMasterRecord(replacerRecord, 'VTCK');
  skinChanged  := not SameLinkedRecord(skinRecord, GetLinkedMasterRecord(targetRecord, 'WNAM'));
  raceChanged  := Assigned(raceRecord) and not SameLinkedRecord(raceRecord, GetLinkedMasterRecord(targetRecord, 'RNAM'));
  voiceChanged := Assigned(voiceRecord) and not SameLinkedRecord(voiceRecord, GetLinkedMasterRecord(targetRecord, 'VTCK'));
  sexChanged   := IsNPCFemale(replacerRecord) <> IsNPCFemale(targetRecord);

  changes := '';
  if hasFace then changes := changes + ' face';
  if skinChanged then changes := changes + ' skin';
  if raceChanged then changes := changes + ' race';
  if sexChanged then changes := changes + ' gender';
  if voiceChanged then changes := changes + ' voice';

  if changes = '' then begin
    AddMessage('No change: ' + targetEditorID);
    Inc(unchangedCount);
    Exit;
  end;

  // Generic NPC with a face: replace it in its leveled lists, the isolated NPC
  // carries every change. Without FaceGen it would have no face: patch the base NPC.
  idxLL := FindLVLNEntries(LVLNMap, targetRecord);
  if hasFace and (idxLL <> -1) then begin
    AddMessage('Leveled lists: ' + targetEditorID + ' -> ' + replacerEditorID);
    placedCount := CountPlacedReferences(targetRecord);
    if placedCount > 0 then
      AddMessage('  Warning: also placed ' + IntToStr(placedCount) + ' time(s) in the world, these references keep the original look.');
    AddLLRules(slLeveledLists, LVLNMap, idxLL, targetRecord, replacerRecord);
    Inc(llCount);
    Exit;
  end;

  AddMessage('SkyPatcher:' + changes + ': ' + targetEditorID);
  AddSkyPatcherRules(targetRecord, replacerRecord, skinRecord, raceRecord, voiceRecord,
    hasFace, skinChanged, raceChanged, sexChanged, voiceChanged);
end;

// Saves every non-empty buffer of the map, one file per plugin
procedure SaveBuffers(map: TStringList; const saveDir, saveLabel: string; toDefaultPath: boolean);
var
  i: integer;
begin
  for i := 0 to map.Count - 1 do
    if TStringList(map.Objects[i]).Count > 0 then
      if toDefaultPath then
        WriteExportFile(TStringList(map.Objects[i]), saveDir + map[i] + '.ini')
      else
        SaveExportList(TStringList(map.Objects[i]), saveDir, map[i], saveLabel + ' (' + map[i] + ')');
end;

function CountFiles(map: TStringList): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to map.Count - 1 do
    if TStringList(map.Objects[i]).Count > 0 then
      Inc(Result);
end;

function Finalize: integer;
var
  fileCount, userChoice: integer;
  toDefaultPath: boolean;
begin
  Result := 0;

  if callIsolator then
    IsolatorFinalize;

  AddMessage('Leveled lists: ' + IntToStr(llCount) + ', SkyPatcher: ' + IntToStr(spCount) +
    ', no change: ' + IntToStr(unchangedCount) + '.');

  // Several files: one confirmation instead of one per file
  fileCount := CountFiles(mapSkyPatcher) + CountFiles(mapLeveledLists);
  toDefaultPath := false;
  userChoice := mrNo;
  if fileCount > 1 then
    userChoice := MessageDlg(
      IntToStr(fileCount) + ' config files to save in:' + #13#10 +
      DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\' + #13#10 + #13#10 +
      'Yes: Save all to their default path' + #13#10 +
      'No: Confirm each file' + #13#10 +
      'Cancel: Do not save',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0);

  if userChoice = mrCancel then
    AddMessage('Save cancelled by user.')
  else begin
    toDefaultPath := userChoice = mrYes;
    SaveBuffers(mapSkyPatcher, DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\npc\',
      'SkyPatcher NPC config', toDefaultPath);
    SaveBuffers(mapLeveledLists, DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\leveledList\',
      'SkyPatcher leveled list config', toDefaultPath);
  end;

  FreePluginBuffers(mapSkyPatcher);
  FreePluginBuffers(mapLeveledLists);
  FreeLVLNMap(LVLNMap);
end;

end.
