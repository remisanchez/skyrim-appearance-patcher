{
  ==============================================================================
   Appearance Patcher.pas
  ==============================================================================
   Converts an NPC replacer plugin into runtime patches. Changes are detected
   automatically: face (FaceGen), skin, race, gender and voice.

     - NPC in leveled lists, with FaceGen -> SkyPatcher leveledList rules: the
       original NPC is replaced by the isolated NPC, same level and count.
     - Other NPCs -> SkyPatcher npc rules, or Recast when selected and able to
       apply every change (face required, no race change).

   Run it on one or more replacer plugins (one config file set per plugin,
   same prefix for all). Integration mode first isolates the NPC
   overrides (AP_Isolator), otherwise the plugin must already be isolated
   (replacer EditorIDs "<prefix>_<original EditorID>").

   Output: Data\Appearance Patcher\ (MO2: overwrite\Appearance Patcher\),
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
  OUTPUT_ROOT = 'Appearance Patcher';
  USE_FORM_ID = true;

var
  // Config buffers per plugin: Strings = plugin name, Objects = TStringList
  mapSkyPatcher, mapRecast, mapLeveledLists: TStringList;
  // Buffers of the plugin being processed
  slSkyPatcher, slRecast, slLeveledLists: TStringList;
  LVLNMap: TStringList;
  callIsolator, useRecast: boolean;
  llCount, spCount, recastCount, unchangedCount: integer;

function Initialize: integer;
var
  userChoice: integer;
begin
  Result := 0;

  mapSkyPatcher   := TStringList.Create;
  mapRecast       := TStringList.Create;
  mapLeveledLists := TStringList.Create;
  LVLNMap        := nil;
  llCount        := 0;
  spCount        := 0;
  recastCount    := 0;
  unchangedCount := 0;
  callIsolator   := false;

  if MessageDlg(
    'Run in Integration Mode?' + #13#10 +
    'Yes = Isolate the NPCs, then generate the configs' + #13#10 +
    'No = Generate the configs only (plugin already isolated)',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    callIsolator := true;

  userChoice := MessageDlg(
    'Framework:' + #13#10 +
    'Yes = SkyPatcher' + #13#10 +
    'No = Recast + SkyPatcher' + #13#10 + #13#10 +
    'With Recast, SkyPatcher still handles leveled lists and the changes' + #13#10 +
    'Recast cannot apply (race, NPCs without FaceGen).',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  if userChoice = mrCancel then begin
    AddMessage('Framework selection was canceled.');
    Result := -1;
    Exit;
  end;
  useRecast := userChoice = mrNo;

  if callIsolator then
    if IsolatorInitialize = -1 then begin
      callIsolator := false;
      Result := -1;
      Exit;
    end;

  LVLNMap := BuildLVLNMap(USE_FORM_ID);
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
  relPath := GetNPCFaceGenRelPath(npc, true);
  Result := FileExists(DataPath + OUTPUT_ROOT + '\' + relPath) or ResourceExists(relPath);
end;

procedure AddHeader(sl: TStringList; const coChar: string; targetRecord, replacerRecord: IInterface);
begin
  sl.Add(coChar + GetElementEditValues(targetRecord, 'FULL'));
  sl.Add(coChar + 'Form ID: ' + GetLocalFormIDHex(targetRecord) + '  Editor ID: ' + EditorID(targetRecord) +
    '  ->  ' + EditorID(replacerRecord));
end;

procedure AddSkyPatcherRules(targetRecord, replacerRecord, skinRecord, raceRecord, voiceRecord: IInterface;
  hasFace, skinChanged, raceChanged, sexChanged, voiceChanged: boolean);
var
  targetID: string;
begin
  targetID := 'filterByNpcs=' + GetSkyPatcherID(targetRecord, USE_FORM_ID);
  AddHeader(slSkyPatcher, ';', targetRecord, replacerRecord);

  if hasFace then
    slSkyPatcher.Add(targetID + ':copyVisualStyle=' + GetSkyPatcherID(replacerRecord, USE_FORM_ID));

  // 'null' resets the skin to the race default body
  if skinChanged then
    if Assigned(skinRecord) then
      slSkyPatcher.Add(targetID + ':skin=' + GetSkyPatcherID(skinRecord, USE_FORM_ID))
    else
      slSkyPatcher.Add(targetID + ':skin=null');

  if raceChanged then
    slSkyPatcher.Add(targetID + ':race=' + GetSkyPatcherID(raceRecord, USE_FORM_ID));

  if sexChanged then
    if IsNPCFemale(replacerRecord) then
      slSkyPatcher.Add(targetID + ':setFlags=female')
    else
      slSkyPatcher.Add(targetID + ':removeFlags=female');

  if voiceChanged then
    slSkyPatcher.Add(targetID + ':voiceType=' + GetSkyPatcherID(voiceRecord, USE_FORM_ID));

  slSkyPatcher.Add('');
  Inc(spCount);
end;

procedure AddRecastPatch(targetRecord, replacerRecord, skinRecord, voiceRecord: IInterface;
  skinChanged, sexChanged, voiceChanged: boolean);
begin
  AddHeader(slRecast, '#', targetRecord, replacerRecord);
  slRecast.Add('[[npcs]]');
  slRecast.Add('target = "' + GetRecastID(targetRecord, USE_FORM_ID, true) + '"');
  slRecast.Add('face = "' + GetRecastID(replacerRecord, USE_FORM_ID, true) + '"');

  if skinChanged and Assigned(skinRecord) then
    slRecast.Add('body = "' + GetRecastID(skinRecord, USE_FORM_ID, false) + '"');

  if sexChanged then
    if IsNPCFemale(replacerRecord) then
      slRecast.Add('sex = "female"')
    else
      slRecast.Add('sex = "male"');

  if voiceChanged then
    slRecast.Add('voice = "' + GetRecastID(voiceRecord, USE_FORM_ID, false) + '"');

  slRecast.Add('');
  Inc(recastCount);
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
  slRecast       := GetPluginBuffer(mapRecast, replacerFileName);
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
    AddLLRules(slLeveledLists, LVLNMap, idxLL, targetRecord, replacerRecord, USE_FORM_ID, false);
    Inc(llCount);
    Exit;
  end;

  // Recast needs a face and cannot change the race
  if useRecast and hasFace and not raceChanged then begin
    AddMessage('Recast:' + changes + ': ' + targetEditorID);
    AddRecastPatch(targetRecord, replacerRecord, skinRecord, voiceRecord, skinChanged, sexChanged, voiceChanged);
  end
  else begin
    if useRecast then
      AddMessage('SkyPatcher (not supported by Recast):' + changes + ': ' + targetEditorID)
    else
      AddMessage('SkyPatcher:' + changes + ': ' + targetEditorID);
    AddSkyPatcherRules(targetRecord, replacerRecord, skinRecord, raceRecord, voiceRecord,
      hasFace, skinChanged, raceChanged, sexChanged, voiceChanged);
  end;
end;

function GetRecastManifest(const pluginName: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Add('[manifest]');
  Result.Add('name = "' + pluginName + '"');
  Result.Add('priority = 100');
  Result.Add('api_version = 1');
  Result.Add('');
end;

// Saves every non-empty buffer of the map, one file per plugin
procedure SaveBuffers(map: TStringList; const saveDir, fileExt, saveLabel: string; toDefaultPath: boolean);
var
  i: integer;
  header: TStringList;
begin
  for i := 0 to map.Count - 1 do
    if TStringList(map.Objects[i]).Count > 0 then begin
      header := nil;
      if fileExt = '.toml' then
        header := GetRecastManifest(map[i]);
      try
        if toDefaultPath then
          WriteExportFile(TStringList(map.Objects[i]), header, saveDir + map[i] + fileExt)
        else
          SaveExportList(TStringList(map.Objects[i]), header, saveDir, map[i], fileExt, saveLabel + ' (' + map[i] + ')');
      finally
        if Assigned(header) then
          header.Free;
      end;
    end;
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
    ', Recast: ' + IntToStr(recastCount) + ', no change: ' + IntToStr(unchangedCount) + '.');

  // Several files: one confirmation instead of one per file
  fileCount := CountFiles(mapRecast) + CountFiles(mapSkyPatcher) + CountFiles(mapLeveledLists);
  toDefaultPath := false;
  userChoice := mrNo;
  if fileCount > 1 then
    userChoice := MessageDlg(
      IntToStr(fileCount) + ' config files to save in:' + #13#10 +
      DataPath + OUTPUT_ROOT + '\SKSE\Plugins\' + #13#10 + #13#10 +
      'Yes: Save all to their default path' + #13#10 +
      'No: Confirm each file' + #13#10 +
      'Cancel: Do not save',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0);

  if userChoice = mrCancel then
    AddMessage('Save cancelled by user.')
  else begin
    toDefaultPath := userChoice = mrYes;
    SaveBuffers(mapRecast, DataPath + OUTPUT_ROOT + '\SKSE\Plugins\Recast\Patches\', '.toml',
      'Recast NPC config', toDefaultPath);
    SaveBuffers(mapSkyPatcher, DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\npc\', '.ini',
      'SkyPatcher NPC config', toDefaultPath);
    SaveBuffers(mapLeveledLists, DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\leveledList\', '.ini',
      'SkyPatcher leveled list config', toDefaultPath);
  end;

  FreePluginBuffers(mapSkyPatcher);
  FreePluginBuffers(mapRecast);
  FreePluginBuffers(mapLeveledLists);
  FreeLVLNMap(LVLNMap);
end;

end.
