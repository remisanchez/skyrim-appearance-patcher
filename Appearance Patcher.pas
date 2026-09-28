{
  ==============================================================================
   Appearance Patcher.pas
  ==============================================================================
   Converts an NPC replacer plugin into runtime patches:
     - unique NPCs          -> SkyPatcher npc rules or Recast patch
     - NPCs in leveled lists -> SkyPatcher leveledList rules (whatever the
                               framework): the original NPC is replaced by the
                               isolated replacer NPC, with the same level/count.

   Run it on the replacer plugin. Integration mode first isolates the NPC
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

var
  slExport, slExportLL, LVLNMap: TStringList;
  coChar, framework, replacerFileName: string;
  llNPCCount: integer;

  // Options
  callIsolator, useFormID, disableAll, replaceVS: boolean;
  outputSkin, outputRace, outputGender, outputName, outputVoiceType, outputOutfit: boolean;

function Initialize: integer;
var
  opts, disableOpts: TStringList;
  i, userChoice: integer;
begin
  Result := 0;

  slExport     := TStringList.Create;
  slExportLL   := TStringList.Create;
  LVLNMap      := nil;
  llNPCCount   := 0;
  callIsolator := false;

  if MessageDlg(
    'Run in Integration Mode?' + #13#10 +
    'Yes = Isolate the NPCs, then generate the configs' + #13#10 +
    'No = Generate the configs only (plugin already isolated)',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    callIsolator := true;

  userChoice := MessageDlg(
    'Framework for unique NPCs:' + #13#10 +
    'Yes = SkyPatcher' + #13#10 +
    'No = Recast' + #13#10 + #13#10 +
    'NPCs in leveled lists always use SkyPatcher.',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  if userChoice = mrYes then
    framework := 'SkyPatcher'
  else if userChoice = mrNo then
    framework := 'Recast'
  else begin
    AddMessage('Framework selection was canceled.');
    Result := -1;
    Exit;
  end;
  AddMessage('Framework: ' + framework);

  // SkyPatcher .ini: ';', Recast .toml: '#'
  coChar := ';';
  if framework = 'Recast' then
    coChar := '#';

  if callIsolator then
    if IsolatorInitialize = -1 then begin
      callIsolator := false;
      Result := -1;
      Exit;
    end;

  opts        := TStringList.Create;
  disableOpts := TStringList.Create;
  try
    opts.Values['Use Form ID for config file output'] := 'False';
    opts.Values['Disable the config file by default'] := 'False';
    opts.Values['Replace Visual Style']               := 'True';
    opts.Values['Output Skin or body setting']        := 'True';
    opts.Values['Output Race setting']                := 'False';
    opts.Values['Output Gender setting']              := 'False';
    opts.Values['Output Name setting']                := 'False';
    opts.Values['Output VoiceType setting']           := 'False';
    opts.Values['Output Outfit setting']              := 'False';

    // Not supported by Recast
    if framework = 'Recast' then begin
      disableOpts.Add('Output Race setting');
      disableOpts.Add('Output Outfit setting');
    end;

    if not ShowCheckboxForm(opts, disableOpts, 'Choose ' + framework + ' Option') then begin
      AddMessage('Selection was canceled.');
      Result := -1;
      Exit;
    end;

    for i := 0 to opts.Count - 1 do
      AddMessage('  ' + opts.Names[i] + ' - ' + opts.ValueFromIndex[i]);

    useFormID       := GetBoolSLValue(opts.Values['Use Form ID for config file output']);
    disableAll      := GetBoolSLValue(opts.Values['Disable the config file by default']);
    replaceVS       := GetBoolSLValue(opts.Values['Replace Visual Style']);
    outputSkin      := GetBoolSLValue(opts.Values['Output Skin or body setting']);
    outputRace      := GetBoolSLValue(opts.Values['Output Race setting']);
    outputGender    := GetBoolSLValue(opts.Values['Output Gender setting']);
    outputName      := GetBoolSLValue(opts.Values['Output Name setting']);
    outputVoiceType := GetBoolSLValue(opts.Values['Output VoiceType setting']);
    outputOutfit    := GetBoolSLValue(opts.Values['Output Outfit setting']);
  finally
    opts.Free;
    disableOpts.Free;
  end;

  LVLNMap := BuildLVLNMap(useFormID);
end;

// Comment prefix of a setting line: disabled by option, or same value as the target
function CommentOutIf(sameValue: boolean): string;
begin
  Result := '';
  if disableAll or sameValue then
    Result := coChar;
end;

// Same, for a linked record: also commented out when the replacer has none
function CommentOutLinked(replacerRecord, targetRecord: IInterface; const path: string): string;
var
  replacerLinked: IInterface;
begin
  replacerLinked := GetLinkedMasterRecord(replacerRecord, path);
  Result := CommentOutIf(not Assigned(replacerLinked) or SameLinkedRecord(replacerLinked, GetLinkedMasterRecord(targetRecord, path)));
end;

procedure AddSkyPatcherRules(targetRecord, replacerRecord: IInterface);
var
  targetID, skinID: string;
  skinRecord: IInterface;
begin
  targetID := GetSkyPatcherID(targetRecord, useFormID);

  slExport.Add(CommentOutIf(not replaceVS) + 'filterByNpcs=' + targetID +
    ':copyVisualStyle=' + GetSkyPatcherID(replacerRecord, useFormID));

  if outputSkin then begin
    // Skin always by FormID, 'null' resets to the race default body
    skinRecord := GetLinkedMasterRecord(replacerRecord, 'WNAM');
    skinID := 'null';
    if Assigned(skinRecord) then
      skinID := GetSkyPatcherID(skinRecord, true);
    slExport.Add(CommentOutIf(SameLinkedRecord(skinRecord, GetLinkedMasterRecord(targetRecord, 'WNAM'))) +
      'filterByNpcs=' + targetID + ':skin=' + skinID);
  end;

  if outputRace then
    slExport.Add(CommentOutLinked(replacerRecord, targetRecord, 'RNAM') +
      'filterByNpcs=' + targetID + ':race=' + GetSkyPatcherID(GetLinkedMasterRecord(replacerRecord, 'RNAM'), useFormID));

  if outputGender then
    if IsNPCFemale(replacerRecord) then
      slExport.Add(CommentOutIf(IsNPCFemale(targetRecord)) + 'filterByNpcs=' + targetID + ':setFlags=female')
    else
      slExport.Add(CommentOutIf(not IsNPCFemale(targetRecord)) + 'filterByNpcs=' + targetID + ':removeFlags=female');

  if outputName then
    slExport.Add(CommentOutIf(GetElementEditValues(replacerRecord, 'FULL') = GetElementEditValues(targetRecord, 'FULL')) +
      'filterByNpcs=' + targetID + ':fullName=~' + GetElementEditValues(replacerRecord, 'FULL') + '~');

  if outputVoiceType then
    slExport.Add(CommentOutLinked(replacerRecord, targetRecord, 'VTCK') +
      'filterByNpcs=' + targetID + ':voiceType=' + GetSkyPatcherID(GetLinkedMasterRecord(replacerRecord, 'VTCK'), useFormID));

  if outputOutfit then
    slExport.Add(CommentOutLinked(replacerRecord, targetRecord, 'DOFT') +
      'filterByNpcs=' + targetID + ':outfitDefault=' + GetSkyPatcherID(GetLinkedMasterRecord(replacerRecord, 'DOFT'), useFormID));
end;

procedure AddRecastPatch(targetRecord, replacerRecord: IInterface);
var
  skinRecord: IInterface;
begin
  slExport.Add('[[npcs]]');
  slExport.Add('target = "' + GetRecastID(targetRecord, useFormID, true) + '"');
  slExport.Add(CommentOutIf(not replaceVS) + 'face = "' + GetRecastID(replacerRecord, useFormID, true) + '"');

  if outputSkin then begin
    // Recast cannot reset to the default body: no skin, no line
    skinRecord := GetLinkedMasterRecord(replacerRecord, 'WNAM');
    if Assigned(skinRecord) then
      slExport.Add(CommentOutIf(SameLinkedRecord(skinRecord, GetLinkedMasterRecord(targetRecord, 'WNAM'))) +
        'body = "' + GetRecastID(skinRecord, true, false) + '"');
  end;

  if outputGender then
    if IsNPCFemale(replacerRecord) then
      slExport.Add(CommentOutIf(IsNPCFemale(targetRecord)) + 'sex = "female"')
    else
      slExport.Add(CommentOutIf(not IsNPCFemale(targetRecord)) + 'sex = "male"');

  if outputName then
    slExport.Add(CommentOutIf(GetElementEditValues(replacerRecord, 'FULL') = GetElementEditValues(targetRecord, 'FULL')) +
      'name = "' + GetElementEditValues(replacerRecord, 'FULL') + '"');

  if outputVoiceType then
    slExport.Add(CommentOutLinked(replacerRecord, targetRecord, 'VTCK') +
      'voice = "' + GetRecastID(GetLinkedMasterRecord(replacerRecord, 'VTCK'), useFormID, false) + '"');
end;

function Process(e: IInterface): integer;
var
  replacerRecord, targetRecord: IInterface;
  replacerEditorID, targetEditorID: string;
  underscorePos, idxLL, placedCount: integer;
begin
  Result := 0;

  if Signature(e) <> 'NPC_' then
    Exit;

  replacerFileName := GetFileName(GetFile(e));

  replacerRecord := e;
  if callIsolator then begin
    Result := IsolatorProcess(e, replacerRecord, OUTPUT_ROOT);
    if Result = -1 then
      Exit;
  end;

  // Not isolated (skipped or removed)
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

  // Generic NPC: leveled list rules only
  idxLL := FindLVLNEntries(LVLNMap, targetRecord);
  if idxLL <> -1 then begin
    AddMessage('Leveled lists: ' + targetEditorID + ' -> ' + replacerEditorID);
    placedCount := CountPlacedReferences(targetRecord);
    if placedCount > 0 then
      AddMessage('  Warning: also placed ' + IntToStr(placedCount) + ' time(s) in the world, these references keep the original look.');
    AddLLRules(slExportLL, LVLNMap, idxLL, targetRecord, replacerRecord, useFormID, disableAll);
    Inc(llNPCCount);
    Exit;
  end;

  // Unique NPC
  AddMessage(framework + ': ' + targetEditorID + ' -> ' + replacerEditorID);
  slExport.Add(coChar + GetElementEditValues(targetRecord, 'FULL'));
  slExport.Add(coChar + 'Form ID: ' + GetLocalFormIDHex(targetRecord) + '  Editor ID: ' + targetEditorID);
  if framework = 'Recast' then
    AddRecastPatch(targetRecord, replacerRecord)
  else
    AddSkyPatcherRules(targetRecord, replacerRecord);
  slExport.Add('');
end;

function Finalize: integer;
var
  recastManifest: TStringList;
begin
  Result := 0;

  if callIsolator then
    IsolatorFinalize;

  AddMessage('Unique NPC lines: ' + IntToStr(slExport.Count) + ', leveled list NPCs: ' + IntToStr(llNPCCount) + '.');

  if slExport.Count > 0 then begin
    if framework = 'Recast' then begin
      recastManifest := TStringList.Create;
      try
        recastManifest.Add('[manifest]');
        recastManifest.Add('name = "' + replacerFileName + '"');
        recastManifest.Add('priority = 100');
        recastManifest.Add('api_version = 1');
        recastManifest.Add('');
        SaveExportList(slExport, recastManifest,
          DataPath + OUTPUT_ROOT + '\SKSE\Plugins\Recast\Patches\', replacerFileName, '.toml',
          'Recast NPC config');
      finally
        recastManifest.Free;
      end;
    end
    else
      SaveExportList(slExport, nil,
        DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\npc\', replacerFileName, '.ini',
        'SkyPatcher NPC config');
  end;

  if slExportLL.Count > 0 then
    SaveExportList(slExportLL, nil,
      DataPath + OUTPUT_ROOT + '\SKSE\Plugins\SkyPatcher\leveledList\', replacerFileName, '.ini',
      'SkyPatcher leveled list config');

  slExport.Free;
  slExportLL.Free;
  FreeLVLNMap(LVLNMap);
end;

end.
